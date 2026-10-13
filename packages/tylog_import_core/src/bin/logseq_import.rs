use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

use tylog_import_core::vault_import::{
    ConvertedNote, SourceDialect, convert_logseq_note, convert_vault_note,
};

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
    unchanged: usize,
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
    let mut arguments: Vec<_> = env::args_os().skip(1).collect();
    let mut dry_run = false;
    let mut obsidian: Option<String> = None;
    let mut only: Option<HashSet<String>> = None;
    let mut assets_from: Option<PathBuf> = None;
    let mut positional = Vec::new();
    while !arguments.is_empty() {
        let argument = arguments.remove(0);
        match argument.to_str() {
            Some("--dry-run") => dry_run = true,
            // ponytail: Obsidian mode takes one vault tag per run; loop in the shell for several vaults.
            Some("--obsidian") if !arguments.is_empty() => {
                obsidian = Some(arguments.remove(0).to_string_lossy().into_owned());
            }
            Some("--assets-from") if !arguments.is_empty() => {
                assets_from = Some(PathBuf::from(arguments.remove(0)));
            }
            Some("--only") if !arguments.is_empty() => {
                let list = fs::read_to_string(arguments.remove(0))?;
                only = Some(list.lines().map(str::to_owned).collect());
            }
            _ => positional.push(argument),
        }
    }
    let [source_root, target_root] = positional.as_slice() else {
        return Err("usage: logseq_import <vault_dir> <tylog_vault_dir> [--dry-run] [--obsidian <tag> [--only <rel-path-list>] [--assets-from <dir>]]".into());
    };
    let (source_root, target_root) = (PathBuf::from(source_root), PathBuf::from(target_root));
    if !source_root.is_dir() {
        return Err(format!("source vault does not exist: {}", source_root.display()).into());
    }
    if !dry_run && !target_root.join(".tylog/settings.json").exists() {
        return Err(format!("target is not a TyLog vault: {}", target_root.display()).into());
    }

    let mut report = Report::default();
    let mut notes = Vec::new();
    let files = match &obsidian {
        Some(_) => obsidian_files(&source_root, only.as_ref())?,
        None => source_files(&source_root)?,
    };
    let already = match &obsidian {
        Some(_) => imported_sources(&target_root),
        None => HashSet::new(),
    };
    for (source_rel, source_path, is_journal) in files {
        let bytes = fs::read(&source_path)?;
        let markdown = String::from_utf8_lossy(&bytes).into_owned();
        let note = match &obsidian {
            Some(tag) => {
                let key = format!("{tag}/{source_rel}");
                if already.contains(&key) {
                    report.unchanged += 1;
                    continue;
                }
                convert_vault_note(SourceDialect::Obsidian, &key, &markdown)
                    .map(|note| stamp_obsidian(note, tag, &key))
            }
            None => convert_logseq_note(&source_rel, &markdown),
        };
        let Some(note) = note else {
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

    match &obsidian {
        Some(tag) => copy_obsidian_assets(&source_root, assets_from.as_deref(), &target_root, tag, &notes, &mut report)?,
        None => copy_assets(&source_root, &target_root, &notes, &mut report)?,
    }
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
    println!("unchanged (already imported): {}", report.unchanged);
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

/// Every `.md` under `root` outside dot-directories; `--only` narrows by relative path.
fn obsidian_files(
    root: &Path,
    only: Option<&HashSet<String>>,
) -> io::Result<Vec<(String, PathBuf, bool)>> {
    fn walk(dir: &Path, root: &Path, out: &mut Vec<(String, PathBuf, bool)>) -> io::Result<()> {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if entry.file_name().to_string_lossy().starts_with('.') {
                continue;
            }
            if entry.file_type()?.is_dir() {
                walk(&path, root, out)?;
            } else if path.extension().and_then(OsStr::to_str) == Some("md") {
                let rel = path.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/");
                out.push((rel, path, false));
            }
        }
        Ok(())
    }
    let mut files = Vec::new();
    walk(root, root, &mut files)?;
    if let Some(only) = only {
        files.retain(|(rel, _, _)| only.contains(rel));
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(files)
}

/// `import_source_path` values already present in the target, so a re-run is a no-op.
fn imported_sources(target_root: &Path) -> HashSet<String> {
    const KEY: &str = "\"import_source_path\": \"";
    fn walk(dir: &Path, found: &mut HashSet<String>) {
        let Ok(entries) = fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, found);
            } else if path.extension().and_then(OsStr::to_str) == Some("typ")
                && let Ok(text) = fs::read_to_string(&path)
                && let Some(start) = text.find(KEY)
                && let Some(len) = text[start + KEY.len()..].find('"')
            {
                found.insert(text[start + KEY.len()..start + KEY.len() + len].to_owned());
            }
        }
    }
    let mut found = HashSet::new();
    walk(&target_root.join("notes"), &mut found);
    found
}

/// Tags the note with its vault, records the source path, and namespaces image assets per vault.
fn stamp_obsidian(mut note: ConvertedNote, tag: &str, key: &str) -> ConvertedNote {
    let tag = tag.replace('"', "");
    note.typst = note
        .typst
        .replacen("tags: (", &format!("tags: (\"{tag}\", "), 1)
        .replacen(
            "\"import_format\": \"obsidian\", ",
            &format!("\"import_format\": \"obsidian\", \"import_source_path\": \"{}\", ", key.replace(['"', '\\'], "")),
            1,
        )
        .replace("\"/assets/obsidian/", &format!("\"/assets/obsidian/{tag}/"));
    note.meta.tags.insert(0, tag);
    note
}

fn copy_obsidian_assets(
    source_root: &Path,
    assets_from: Option<&Path>,
    target_root: &Path,
    tag: &str,
    notes: &[WorkNote],
    report: &mut Report,
) -> io::Result<()> {
    // Obsidian resolves embeds by shortest unique path; index every non-md file by basename.
    fn index(dir: &Path, by_name: &mut BTreeMap<String, PathBuf>) {
        let Ok(entries) = fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if entry.file_name().to_string_lossy().starts_with('.') {
                continue;
            }
            if path.is_dir() {
                index(&path, by_name);
            } else if let Some(name) = path.file_name().and_then(OsStr::to_str) {
                by_name.entry(name.to_owned()).or_insert(path);
            }
        }
    }
    let mut by_name = BTreeMap::new();
    index(source_root, &mut by_name);
    if let Some(extra) = assets_from {
        index(extra, &mut by_name);
    }
    let wanted: BTreeSet<_> = notes
        .iter()
        .flat_map(|work| work.note.referenced_assets.iter())
        .filter_map(|asset| Path::new(asset).file_name()?.to_str().map(str::to_owned))
        .collect();
    for name in wanted {
        let Some(source) = by_name.get(&name) else {
            report.assets_missing += 1;
            println!("missing asset: {name}");
            continue;
        };
        let target = target_root.join("assets/obsidian").join(tag).join(&name);
        if target.exists() {
            continue;
        }
        fs::create_dir_all(target.parent().unwrap())?;
        fs::copy(source, target)?;
        report.assets_copied += 1;
    }
    Ok(())
}
