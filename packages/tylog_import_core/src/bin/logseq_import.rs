use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

use tylog_import_core::vault_import::{ConvertedNote, convert_logseq_note};

struct WorkNote {
    source_rel: String,
    note: ConvertedNote,
    append: bool,
}

#[derive(Default)]
struct Report {
    pages: usize,
    journals: usize,
    appended: usize,
    skipped_empty: usize,
    assets_copied: usize,
    assets_missing: usize,
    dropped_block_refs: usize,
    stripped_macros: usize,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("logseq_import: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let arguments: Vec<_> = env::args_os().skip(1).collect();
    let (source_root, target_root, dry_run) = match arguments.as_slice() {
        [source, target] => (PathBuf::from(source), PathBuf::from(target), false),
        [source, target, flag] if flag == "--dry-run" => {
            (PathBuf::from(source), PathBuf::from(target), true)
        }
        _ => {
            return Err(
                "usage: logseq_import <logseq_vault_dir> <tylog_vault_dir> [--dry-run]".into(),
            );
        }
    };
    if !source_root.is_dir() {
        return Err(format!("source vault does not exist: {}", source_root.display()).into());
    }
    if !dry_run && !target_root.join(".tylog/settings.json").exists() {
        return Err(format!("target is not a TyLog vault: {}", target_root.display()).into());
    }

    let mut report = Report::default();
    let mut notes = Vec::new();
    for (source_rel, source_path, is_journal) in source_files(&source_root)? {
        let markdown = fs::read_to_string(&source_path)?;
        let Some(note) = convert_logseq_note(&source_rel, &markdown) else {
            report.skipped_empty += 1;
            continue;
        };
        if is_journal {
            report.journals += 1;
        } else {
            report.pages += 1;
        }
        report.dropped_block_refs += note.dropped_block_refs;
        report.stripped_macros += note.stripped_macros;
        notes.push(WorkNote {
            source_rel,
            note,
            append: false,
        });
    }

    assign_output_paths(&mut notes, &target_root, dry_run);
    fs::create_dir_all(&target_root)?;
    for work in &notes {
        let target = target_root.join(&work.note.rel_path);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        if work.append {
            let mut file = OpenOptions::new().append(true).open(&target)?;
            write!(file, "\n== From Logseq\n\n{}", note_body(&work.note.typst))?;
            report.appended += 1;
        } else {
            OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&target)?
                .write_all(work.note.typst.as_bytes())?;
        }
    }

    copy_assets(&source_root, &target_root, &notes, &mut report)?;
    let unresolved = unresolved_wikilinks(&target_root, &notes)?;
    print_report(&report, &unresolved, &notes);
    Ok(())
}

fn source_files(source_root: &Path) -> io::Result<Vec<(String, PathBuf, bool)>> {
    let mut files = Vec::new();
    for (directory, is_journal) in [("pages", false), ("journals", true)] {
        let path = source_root.join(directory);
        let entries = match fs::read_dir(path) {
            Ok(entries) => entries,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error),
        };
        for entry in entries {
            let entry = entry?;
            if !entry.file_type()?.is_file()
                || !entry
                    .path()
                    .extension()
                    .and_then(OsStr::to_str)
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("md"))
            {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            files.push((format!("{directory}/{name}"), entry.path(), is_journal));
        }
    }
    files.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(files)
}

fn assign_output_paths(notes: &mut [WorkNote], target_root: &Path, dry_run: bool) {
    let mut used = HashSet::new();
    for work in notes {
        let canonical = PathBuf::from(&work.note.rel_path);
        let target = target_root.join(&canonical);
        if !dry_run
            && work.note.meta.kind == "daily"
            && target.exists()
            && used.insert(canonical.clone())
        {
            work.append = true;
            continue;
        }

        let mut candidate = canonical.clone();
        let mut number = 2;
        while target_root.join(&candidate).exists() || used.contains(&candidate) {
            candidate = suffixed_path(&canonical, number);
            number += 1;
        }
        used.insert(candidate.clone());
        work.note.rel_path = candidate.to_string_lossy().replace('\\', "/");
    }
}

fn suffixed_path(path: &Path, number: usize) -> PathBuf {
    let stem = path.file_stem().and_then(OsStr::to_str).unwrap_or_default();
    path.with_file_name(format!("{stem} ({number}).typ"))
}

fn note_body(typst: &str) -> &str {
    let Some(heading) = typst.find("\n= ").map(|index| index + 1) else {
        return typst;
    };
    let Some(end) = typst[heading..].find('\n').map(|index| heading + index + 1) else {
        return "";
    };
    typst[end..].trim_start_matches('\n')
}

fn copy_assets(
    source_root: &Path,
    target_root: &Path,
    notes: &[WorkNote],
    report: &mut Report,
) -> io::Result<()> {
    let assets: BTreeSet<_> = notes
        .iter()
        .flat_map(|work| work.note.referenced_assets.iter().cloned())
        .collect();
    for asset in assets {
        let Some(name) = asset.strip_prefix("assets/").and_then(safe_relative_path) else {
            report.assets_missing += 1;
            continue;
        };
        let source = source_root.join("assets").join(&name);
        let target = target_root.join("assets/logseq").join(&name);
        if !source.is_file() {
            report.assets_missing += 1;
            continue;
        }
        if target.exists() {
            continue;
        }
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(source, target)?;
        report.assets_copied += 1;
    }
    Ok(())
}

fn safe_relative_path(value: &str) -> Option<PathBuf> {
    let path = Path::new(value);
    path.components()
        .all(|component| matches!(component, Component::Normal(_)))
        .then(|| path.to_owned())
}

fn unresolved_wikilinks(target_root: &Path, notes: &[WorkNote]) -> io::Result<Vec<String>> {
    let mut resolved = BTreeSet::new();
    for work in notes {
        resolved.insert(work.note.meta.title.to_lowercase());
        resolved.extend(
            work.note
                .meta
                .aliases
                .iter()
                .map(|alias| alias.to_lowercase()),
        );
        if let Some(date) = &work.note.meta.date {
            resolved.insert(date.to_lowercase());
        }
    }
    for directory in ["notes", "articles", "projects", "daily"] {
        collect_typst_stems(&target_root.join(directory), &mut resolved)?;
    }

    let mut unresolved = BTreeMap::new();
    for target in notes
        .iter()
        .flat_map(|work| work.note.wikilink_targets.iter())
    {
        let folded = target.to_lowercase();
        if !resolved.contains(&folded) {
            unresolved.entry(folded).or_insert_with(|| target.clone());
        }
    }
    Ok(unresolved.into_values().collect())
}

fn collect_typst_stems(directory: &Path, resolved: &mut BTreeSet<String>) -> io::Result<()> {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    for entry in entries {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            collect_typst_stems(&entry.path(), resolved)?;
        } else if file_type.is_file()
            && entry
                .path()
                .extension()
                .and_then(OsStr::to_str)
                .is_some_and(|extension| extension.eq_ignore_ascii_case("typ"))
            && let Some(stem) = entry.path().file_stem().and_then(OsStr::to_str)
        {
            resolved.insert(stem.to_lowercase());
        }
    }
    Ok(())
}

fn print_report(report: &Report, unresolved: &[String], notes: &[WorkNote]) {
    println!("pages converted: {}", report.pages);
    println!("journals converted: {}", report.journals);
    println!("journals appended-to-existing: {}", report.appended);
    println!("files skipped-empty: {}", report.skipped_empty);
    println!("assets copied: {}", report.assets_copied);
    println!("assets missing: {}", report.assets_missing);
    println!("unresolved wikilink targets: {}", unresolved.len());
    for target in unresolved.iter().take(50) {
        println!("- {target}");
    }
    println!("dropped block refs: {}", report.dropped_block_refs);
    println!("stripped macros: {}", report.stripped_macros);
    for work in notes {
        for diagnostic in &work.note.diagnostics {
            println!("{}: {}", work.source_rel, diagnostic);
        }
    }
}
