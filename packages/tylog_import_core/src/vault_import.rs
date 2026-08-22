use std::collections::HashMap;
use std::path::Path;

use crate::{convert_markdown, escape_markup};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceDialect {
    Logseq,
    Obsidian,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteMeta {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub date: Option<String>,
    pub tags: Vec<String>,
    pub aliases: Vec<String>,
    pub properties: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConvertedNote {
    pub rel_path: String,
    pub typst: String,
    pub referenced_assets: Vec<String>,
    pub wikilink_targets: Vec<String>,
    pub diagnostics: Vec<String>,
    pub meta: NoteMeta,
    pub dropped_block_refs: usize,
    pub stripped_macros: usize,
}

#[derive(Debug)]
struct Task {
    text: String,
    status: &'static str,
    priority: &'static str,
    scheduled: Option<String>,
    due: Option<String>,
    /// `(start, end)` ISO-8601 pairs from the task's `:LOGBOOK:` drawer. `end`
    /// is `None` for a clock that was started and never stopped.
    clocked: Vec<(String, Option<String>)>,
}

#[derive(Debug)]
struct Wikilink {
    target: String,
    display: String,
}

#[derive(Debug)]
struct Preprocessed {
    markdown: String,
    tasks: Vec<Task>,
    wikilinks: Vec<Wikilink>,
    highlights: Vec<String>,
    math: Vec<String>,
    assets: Vec<String>,
    dropped_block_refs: usize,
    stripped_macros: usize,
}

pub fn convert_logseq_note(source_rel_path: &str, markdown: &str) -> Option<ConvertedNote> {
    convert_vault_note(SourceDialect::Logseq, source_rel_path, markdown)
}

pub fn convert_vault_note(
    dialect: SourceDialect,
    source_rel_path: &str,
    markdown: &str,
) -> Option<ConvertedNote> {
    let (meta, body, source_name, mut diagnostics) = match dialect {
        SourceDialect::Logseq => {
            let (meta, body, source_name) = extract_logseq_metadata(source_rel_path, markdown);
            (meta, body, source_name, Vec::new())
        }
        SourceDialect::Obsidian => extract_obsidian_metadata(source_rel_path, markdown),
    };
    if body_is_empty(&body) {
        return None;
    }

    let preprocessed = preprocess(dialect, &body);
    let converted = convert_markdown(&preprocessed.markdown, &meta.title, None);
    let mut typst = converted.typst;

    for (index, highlight) in preprocessed.highlights.iter().enumerate() {
        typst = typst.replace(
            &format!("QQHL{index}QQ"),
            &format!("#highlight[{}]", escape_markup(highlight)),
        );
    }
    for (index, wikilink) in preprocessed.wikilinks.iter().enumerate() {
        typst = typst.replace(
            &format!("QQWL{index}QQ"),
            &format!(
                "#tylog.ref-note({})[{}]",
                typst_string(&wikilink.target),
                escape_markup(&wikilink.display)
            ),
        );
    }
    for (index, task) in preprocessed.tasks.iter().enumerate() {
        let mut call = format!(
            "#tylog.task(id: {}, text: {}, status: {}, priority: {}",
            typst_string(&format!("{}-t{}", meta.id, index + 1)),
            typst_string(&task.text),
            typst_string(task.status),
            typst_string(task.priority),
        );
        if let Some(date) = &task.scheduled {
            call.push_str(&format!(", scheduled: {}", typst_string(date)));
        }
        if let Some(date) = &task.due {
            call.push_str(&format!(", due: {}", typst_string(date)));
        }
        if !task.clocked.is_empty() {
            let pairs: Vec<String> = task
                .clocked
                .iter()
                .map(|(start, end)| {
                    format!(
                        "({}, {})",
                        typst_string(start),
                        end.as_deref().map(typst_string).unwrap_or_else(|| "none".to_owned())
                    )
                })
                .collect();
            // Into `properties`, never as a named argument. A dict tolerates
            // keys an older tylog package has never seen; an unknown named
            // argument is a hard Typst compile error, and `_system/packages/`
            // syncs between devices that may be on different builds. Emitting
            // it as an argument is what stopped 167 notes compiling.
            //
            // A single-element Typst array needs the trailing comma to stay an
            // array rather than collapsing to its element.
            call.push_str(&format!(
                ", properties: (\"clocked\": ({},),)",
                pairs.join(", ")
            ));
        }
        call.push(')');
        typst = typst.replace(&format!("QQTASK{index}QQ"), &call);
    }
    typst = rewrite_asset_links(&typst, dialect);
    for (index, math) in preprocessed.math.iter().enumerate() {
        typst = typst.replace(&format!("QQMATH{index}QQ"), math);
    }

    let rel_path = if let Some(date) = &meta.date {
        format!("daily/{}/{}/{}.typ", &date[..4], &date[5..7], date)
    } else {
        let title = match dialect {
            SourceDialect::Logseq => &meta.title,
            SourceDialect::Obsidian => source_stem(&source_name),
        };
        format!("notes/{}.typ", sanitize_title(title))
    };
    let typst = assemble_note(dialect, &meta, &source_name, &typst);
    diagnostics.extend(
        converted
            .diagnostics
            .into_iter()
            .map(|diagnostic| diagnostic.message),
    );

    Some(ConvertedNote {
        rel_path,
        typst,
        referenced_assets: preprocessed.assets,
        wikilink_targets: preprocessed
            .wikilinks
            .into_iter()
            .map(|wikilink| wikilink.target)
            .collect(),
        diagnostics,
        meta,
        dropped_block_refs: preprocessed.dropped_block_refs,
        stripped_macros: preprocessed.stripped_macros,
    })
}

fn extract_logseq_metadata(source_rel_path: &str, markdown: &str) -> (NoteMeta, String, String) {
    let source_name = source_name(source_rel_path);
    let stem = source_stem(&source_name);
    let markdown = replace_same_file_block_refs(markdown, &collect_same_file_blocks(markdown));
    let markdown = rewrite_ordered_lists(&markdown);
    let mut title = percent_decode(stem);
    let mut tags = Vec::new();
    let mut aliases = Vec::new();
    let mut properties = Vec::new();
    let mut body = Vec::new();
    let mut leading = true;

    for line in markdown.lines() {
        let property = property_line(line);
        if leading {
            if let Some((key, value)) = property.as_ref() {
                let key = key.to_ascii_lowercase();
                match key.as_str() {
                    "title" => title = value.trim().to_owned(),
                    "tags" | "tag" => extend_unique(&mut tags, parse_list(value)),
                    "alias" | "allias" => extend_unique(&mut aliases, parse_list(value)),
                    key if !is_noise_property(key) => {
                        properties.push((key.to_owned(), value.trim().to_owned()))
                    }
                    _ => {}
                }
                continue;
            }
            if line.trim().is_empty() {
                continue;
            }
            leading = false;
        }

        if property
            .as_ref()
            .is_some_and(|(key, _)| is_noise_property(&key.to_ascii_lowercase()))
        {
            continue;
        }
        body.push(line);
    }

    let journal_date = journal_date(source_rel_path, stem);
    let (id, kind, date) = if let Some(date) = journal_date {
        title = date.clone();
        if !tags.iter().any(|tag| tag.eq_ignore_ascii_case("journal")) {
            tags.push("journal".to_owned());
        }
        (date.clone(), "daily".to_owned(), Some(date))
    } else {
        (
            format!("lsq-{:016x}", fnv1a(source_rel_path.as_bytes())),
            "note".to_owned(),
            None,
        )
    };

    (
        NoteMeta {
            id,
            title,
            kind,
            date,
            tags,
            aliases,
            properties,
        },
        body.join("\n"),
        source_name,
    )
}

fn extract_obsidian_metadata(
    source_rel_path: &str,
    markdown: &str,
) -> (NoteMeta, String, String, Vec<String>) {
    let source_name = source_name(source_rel_path);
    let stem = source_stem(&source_name);
    let mut title = stem.to_owned();
    let mut tags = Vec::new();
    let mut aliases = Vec::new();
    let mut properties = Vec::new();
    let mut diagnostics = Vec::new();
    let mut body = markdown.to_owned();

    if markdown.lines().next() == Some("---") {
        let lines: Vec<_> = markdown.lines().collect();
        if let Some(end) = lines[1..].iter().position(|line| *line == "---") {
            let end = end + 1;
            match parse_frontmatter(&lines[1..end]) {
                Ok(entries) => {
                    for (key, values) in entries {
                        match key.to_ascii_lowercase().as_str() {
                            "title" => title = values.join(", "),
                            "tags" | "tag" => extend_unique(
                                &mut tags,
                                values
                                    .into_iter()
                                    .map(|tag| tag.trim_start_matches('#').to_owned())
                                    .filter(|tag| !tag.is_empty())
                                    .collect(),
                            ),
                            "aliases" | "alias" => extend_unique(&mut aliases, values),
                            _ => properties.push((key, values.join(", "))),
                        }
                    }
                    body = lines[end + 1..].join("\n");
                }
                Err(message) => diagnostics.push(message),
            }
        } else {
            diagnostics.push(
                "Obsidian frontmatter has no closing delimiter; it was kept in the body".to_owned(),
            );
        }
    }

    let date = obsidian_journal_date(stem);
    let (id, kind) = if let Some(date) = &date {
        title.clone_from(date);
        if !tags.iter().any(|tag| tag.eq_ignore_ascii_case("journal")) {
            tags.push("journal".to_owned());
        }
        (date.clone(), "daily".to_owned())
    } else {
        (
            format!("obs-{:016x}", fnv1a(source_rel_path.as_bytes())),
            "note".to_owned(),
        )
    };

    (
        NoteMeta {
            id,
            title,
            kind,
            date,
            tags,
            aliases,
            properties,
        },
        body,
        source_name,
        diagnostics,
    )
}

fn parse_frontmatter(lines: &[&str]) -> Result<Vec<(String, Vec<String>)>, String> {
    let mut entries = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        let line = lines[index];
        if line.trim().is_empty() {
            index += 1;
            continue;
        }
        if line.starts_with([' ', '\t']) || line.trim_start().starts_with("- ") {
            return Err(format!(
                "Obsidian frontmatter line {} is not a flat key/value; frontmatter was kept in the body",
                index + 2
            ));
        }
        let Some((key, value)) = line.split_once(':') else {
            return Err(format!(
                "Obsidian frontmatter line {} is not a key/value; frontmatter was kept in the body",
                index + 2
            ));
        };
        let key = key.trim();
        if key.is_empty() {
            return Err(format!(
                "Obsidian frontmatter line {} has an empty key; frontmatter was kept in the body",
                index + 2
            ));
        }
        let value = value.trim();
        if value.starts_with('[') {
            let Some(value) = value.strip_suffix(']') else {
                return Err(format!(
                    "Obsidian frontmatter line {} has an invalid inline list; frontmatter was kept in the body",
                    index + 2
                ));
            };
            entries.push((
                key.to_owned(),
                value[1..]
                    .split(',')
                    .map(yaml_scalar)
                    .filter(|item| !item.is_empty())
                    .collect(),
            ));
            index += 1;
            continue;
        }
        if value.is_empty() {
            let mut values = Vec::new();
            while index + 1 < lines.len() {
                let Some(item) = lines[index + 1].trim_start().strip_prefix("- ") else {
                    break;
                };
                values.push(yaml_scalar(item));
                index += 1;
            }
            entries.push((key.to_owned(), values));
        } else {
            entries.push((key.to_owned(), vec![yaml_scalar(value)]));
        }
        index += 1;
    }
    Ok(entries)
}

fn yaml_scalar(value: &str) -> String {
    let value = value.trim();
    if value.len() >= 2
        && ((value.starts_with('"') && value.ends_with('"'))
            || (value.starts_with('\'') && value.ends_with('\'')))
    {
        value[1..value.len() - 1].to_owned()
    } else {
        value.to_owned()
    }
}

fn source_name(source_rel_path: &str) -> String {
    source_rel_path
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(source_rel_path)
        .to_owned()
}

fn source_stem(source_name: &str) -> &str {
    source_name.strip_suffix(".md").unwrap_or(source_name)
}

fn property_line(line: &str) -> Option<(String, &str)> {
    let mut value = line.trim_start_matches([' ', '\t']);
    if let Some(rest) = value.strip_prefix("- ") {
        value = rest.trim_start_matches([' ', '\t']);
    }
    let (key, value) = value.split_once("::")?;
    let key = key.trim();
    (!key.is_empty()).then(|| (key.to_owned(), value.trim()))
}

fn is_noise_property(key: &str) -> bool {
    matches!(
        key,
        "collapsed"
            | "id"
            | "ls-type"
            | "hl-page"
            | "hl-color"
            | "hl-stamp"
            | "logseq.order-list-type"
    )
}

fn rewrite_ordered_lists(value: &str) -> String {
    let mut lines: Vec<_> = value.lines().map(str::to_owned).collect();
    let mut removed = vec![false; lines.len()];
    for index in 0..lines.len() {
        let Some((key, list_type)) = property_line(&lines[index]) else {
            continue;
        };
        if !key.eq_ignore_ascii_case("logseq.order-list-type") {
            continue;
        }
        removed[index] = true;
        if !list_type.eq_ignore_ascii_case("number") {
            continue;
        }

        let indent = leading_indent(&lines[index]);
        let mut number = 1;
        for line in &mut lines[index + 1..] {
            if line.trim().is_empty() {
                break;
            }
            let line_indent = leading_indent(line);
            if line_indent < indent {
                break;
            }
            let trimmed = &line[line_indent..];
            if line_indent == indent {
                let Some(text) = trimmed.strip_prefix("- ") else {
                    break;
                };
                *line = format!("{}{}. {text}", &line[..line_indent], number);
                number += 1;
            } else if !is_markdown_bullet(trimmed) {
                break;
            }
        }
    }
    lines
        .into_iter()
        .enumerate()
        .filter_map(|(index, line)| (!removed[index]).then_some(line))
        .collect::<Vec<_>>()
        .join("\n")
}

fn is_markdown_bullet(value: &str) -> bool {
    value.starts_with("- ")
        || value.split_once(". ").is_some_and(|(number, _)| {
            !number.is_empty() && number.bytes().all(|b| b.is_ascii_digit())
        })
}

fn collect_same_file_blocks(value: &str) -> HashMap<String, String> {
    let lines: Vec<_> = value.lines().collect();
    let mut blocks = HashMap::new();
    for (index, line) in lines.iter().enumerate() {
        let Some((key, id)) = property_line(line) else {
            continue;
        };
        if !key.eq_ignore_ascii_case("id") || !is_block_ref_token(id) {
            continue;
        }
        let property_indent = leading_indent(line);
        for parent in lines[..index].iter().rev() {
            if parent.trim().is_empty() {
                break;
            }
            if leading_indent(parent) >= property_indent {
                continue;
            }
            if let Some(text) = parent.trim_start_matches([' ', '\t']).strip_prefix("- ") {
                blocks.insert(id.to_owned(), text.trim().to_owned());
            }
            break;
        }
    }
    blocks
}

fn replace_same_file_block_refs(value: &str, blocks: &HashMap<String, String>) -> String {
    let mut out = String::with_capacity(value.len());
    let mut rest = value;
    while let Some(start) = rest.find("((") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let Some(end) = after.find("))") else {
            out.push_str(&rest[start..]);
            return out;
        };
        let token = after[..end].trim();
        if is_block_ref_token(token)
            && let Some(text) = blocks.get(token)
        {
            out.push_str(text);
        } else {
            out.push_str(&rest[start..start + 2 + end + 2]);
        }
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    out
}

fn parse_list(value: &str) -> Vec<String> {
    if value.contains("[[") {
        let mut items = Vec::new();
        let mut rest = value;
        while let Some(start) = rest.find("[[") {
            let after = &rest[start + 2..];
            let Some(end) = after.find("]]") else {
                break;
            };
            let item = after[..end].trim();
            if !item.is_empty() {
                items.push(item.to_owned());
            }
            rest = &after[end + 2..];
        }
        return items;
    }
    if value.trim_start().starts_with('#') {
        return value
            .split('#')
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(str::to_owned)
            .collect();
    }
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_owned)
        .collect()
}

fn extend_unique(target: &mut Vec<String>, values: Vec<String>) {
    for value in values {
        if !target.iter().any(|item| item.eq_ignore_ascii_case(&value)) {
            target.push(value);
        }
    }
}

fn journal_date(source_rel_path: &str, stem: &str) -> Option<String> {
    if !source_rel_path.replace('\\', "/").starts_with("journals/") {
        return None;
    }
    let bytes = stem.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'_'
        || bytes[7] != b'_'
        || bytes
            .iter()
            .enumerate()
            .any(|(index, byte)| index != 4 && index != 7 && !byte.is_ascii_digit())
    {
        return None;
    }
    Some(format!("{}-{}-{}", &stem[..4], &stem[5..7], &stem[8..]))
}

fn obsidian_journal_date(stem: &str) -> Option<String> {
    let bytes = stem.as_bytes();
    (bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit()))
    .then(|| stem.to_owned())
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn sanitize_title(title: &str) -> String {
    title
        .chars()
        .filter_map(|character| match character {
            '/' | '\\' => Some('-'),
            ':' | '*' | '?' | '"' | '<' | '>' | '|' => None,
            _ => Some(character),
        })
        .collect::<String>()
        .trim()
        .to_owned()
}

fn body_is_empty(body: &str) -> bool {
    body.lines()
        .all(|line| line.trim().is_empty() || line.trim() == "-")
}

fn preprocess(dialect: SourceDialect, markdown: &str) -> Preprocessed {
    match dialect {
        SourceDialect::Logseq => {
            let (markdown, math) = extract_math(markdown);
            let markdown = rewrite_bullet_headings(&markdown);
            let markdown = strip_image_sizing_hints(&markdown);
            let (markdown, stripped_macros) = rewrite_macros(&markdown);
            let mut wikilinks = Vec::new();
            let (markdown, tasks, task_block_refs) = extract_tasks(&markdown, &mut wikilinks);
            // After extract_tasks, which claims each task's own :LOGBOOK: drawer
            // as `clocked`. What is left here is orphaned bookkeeping and the
            // empty block every page trails.
            let markdown = strip_logseq_noise(&markdown);
            let markdown = replace_wikilinks(&markdown, &mut wikilinks);
            let (markdown, highlights) = extract_highlights(&markdown);
            let (markdown, body_block_refs) = drop_block_refs(&markdown);
            let (markdown, assets) = rewrite_asset_destinations(&markdown);
            Preprocessed {
                markdown,
                tasks,
                wikilinks,
                highlights,
                math,
                assets,
                dropped_block_refs: task_block_refs + body_block_refs,
                stripped_macros,
            }
        }
        SourceDialect::Obsidian => {
            let (markdown, mut assets) = rewrite_obsidian_embeds(markdown);
            let mut wikilinks = Vec::new();
            let markdown = replace_wikilinks(&markdown, &mut wikilinks);
            let (markdown, markdown_assets) = rewrite_obsidian_images(&markdown);
            extend_unique(&mut assets, markdown_assets);
            Preprocessed {
                markdown,
                tasks: Vec::new(),
                wikilinks,
                highlights: Vec::new(),
                math: Vec::new(),
                assets,
                dropped_block_refs: 0,
                stripped_macros: 0,
            }
        }
    }
}

/// Drops the org-mode bookkeeping a Logseq export carries but a reader never
/// wants: `:LOGBOOK:` drawers with their `CLOCK:` records and state-change
/// lines, plus the empty block every page trails.
///
/// By line shape, not by parsing the drawer: a real vault has orphan `:END:`
/// lines and unclosed `:LOGBOOK:` openers, and a state machine would either
/// leak those or swallow real content past an unclosed opener. Only *trailing*
/// empty bullets go — an empty item between two others is deliberate spacing.
///
/// Keep in step with `stripLogseqNoise` in tylog_core's scanner.dart, which
/// repairs notes imported before this existed.
fn strip_logseq_noise(value: &str) -> String {
    let mut lines: Vec<&str> = value
        .lines()
        .filter(|line| !is_org_bookkeeping(line))
        .collect();
    while lines
        .last()
        .is_some_and(|line| is_empty_bullet(line) || line.trim().is_empty())
    {
        lines.pop();
    }
    lines.join("\n")
}

fn is_org_bookkeeping(line: &str) -> bool {
    let trimmed = line.trim();
    trimmed == ":LOGBOOK:"
        || trimmed == ":END:"
        || trimmed.starts_with("CLOCK:")
        || trimmed.starts_with("- State \"")
}

fn is_empty_bullet(line: &str) -> bool {
    matches!(line.trim(), "-" | "+" | "*")
}

fn extract_math(value: &str) -> (String, Vec<String>) {
    let mut out = String::with_capacity(value.len());
    let mut math = Vec::new();
    let mut rest = value;
    while let Some(start) = rest.find('$') {
        out.push_str(&rest[..start]);
        let display = rest[start..].starts_with("$$");
        let delimiter = if display { "$$" } else { "$" };
        let after = &rest[start + delimiter.len()..];
        let search_end = if display {
            after.len()
        } else {
            after.find('\n').unwrap_or(after.len())
        };
        let Some(end) = after[..search_end].find(delimiter) else {
            out.push_str(delimiter);
            rest = after;
            continue;
        };
        let inner = &after[..end];
        if display {
            math.push(format!("$ {inner} $"));
        } else {
            math.push(format!("${inner}$"));
        }
        out.push_str(&format!("QQMATH{}QQ", math.len() - 1));
        rest = &after[end + delimiter.len()..];
    }
    out.push_str(rest);
    (out, math)
}

fn rewrite_bullet_headings(value: &str) -> String {
    let mut out = Vec::new();
    for line in value.lines() {
        let trimmed = line.trim_start_matches([' ', '\t']);
        let Some(heading) = trimmed.strip_prefix("- ") else {
            out.push(line.to_owned());
            continue;
        };
        let level = heading.bytes().take_while(|byte| *byte == b'#').count();
        if (1..=6).contains(&level) && heading.as_bytes().get(level) == Some(&b' ') {
            out.push(String::new());
            out.push(heading.to_owned());
            out.push(String::new());
        } else {
            out.push(line.to_owned());
        }
    }
    out.join("\n")
}

fn strip_image_sizing_hints(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut rest = value;
    while let Some(start) = rest.find("![") {
        let Some(label_end) = rest[start + 2..].find("](").map(|end| start + 2 + end) else {
            break;
        };
        let destination_start = label_end + 2;
        let Some(close) = rest[destination_start..].find(')') else {
            break;
        };
        let image_end = destination_start + close + 1;
        out.push_str(&rest[..image_end]);
        rest = &rest[image_end..];
        if let Some(hint) = rest.strip_prefix("{:")
            && let Some(end) = hint.find('}')
        {
            rest = &hint[end + 1..];
        }
    }
    out.push_str(rest);
    out
}

fn extract_highlights(value: &str) -> (String, Vec<String>) {
    let mut out = String::with_capacity(value.len());
    let mut highlights = Vec::new();
    let mut rest = value;
    loop {
        let marker = match (rest.find("=="), rest.find("^^")) {
            (Some(equals), Some(carets)) if equals <= carets => Some((equals, "==")),
            (Some(_), Some(carets)) => Some((carets, "^^")),
            (Some(equals), None) => Some((equals, "==")),
            (None, Some(carets)) => Some((carets, "^^")),
            (None, None) => None,
        };
        let Some((start, delimiter)) = marker else {
            break;
        };
        out.push_str(&rest[..start]);
        let after = &rest[start + delimiter.len()..];
        let line_end = after.find('\n').unwrap_or(after.len());
        let Some(end) = after[..line_end].find(delimiter) else {
            out.push_str(delimiter);
            rest = after;
            continue;
        };
        highlights.push(after[..end].to_owned());
        out.push_str(&format!("QQHL{}QQ", highlights.len() - 1));
        rest = &after[end + delimiter.len()..];
    }
    out.push_str(rest);
    (out, highlights)
}

fn rewrite_macros(markdown: &str) -> (String, usize) {
    let mut out = String::with_capacity(markdown.len());
    let mut rest = markdown;
    let mut stripped = 0;
    while let Some(start) = rest.find("{{") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let Some(end) = after.find("}}") else {
            out.push_str(&rest[start..]);
            return (out, stripped);
        };
        let inner = after[..end].trim();
        let command_end = inner.find(char::is_whitespace).unwrap_or(inner.len());
        let command = &inner[..command_end];
        let argument = inner[command_end..].trim();
        if command.eq_ignore_ascii_case("embed")
            && argument.starts_with("[[")
            && argument.ends_with("]]")
        {
            out.push_str(argument);
        } else if command.eq_ignore_ascii_case("video") {
            out.push_str(argument);
        } else {
            stripped += 1;
        }
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    (out, stripped)
}

fn extract_tasks(markdown: &str, wikilinks: &mut Vec<Wikilink>) -> (String, Vec<Task>, usize) {
    let lines: Vec<_> = markdown.lines().collect();
    let mut out = Vec::with_capacity(lines.len());
    let mut tasks = Vec::new();
    let mut dropped_block_refs = 0;
    let mut index = 0;
    while index < lines.len() {
        let line = lines[index];
        let Some((indent, status, rest)) = parse_task_line(line) else {
            out.push(line.to_owned());
            index += 1;
            continue;
        };
        let (priority, text) = parse_priority(rest);
        let text = replace_task_wikilinks(text, wikilinks);
        let (text, dropped) = drop_block_refs(&text);
        dropped_block_refs += dropped;
        if text.trim().is_empty() {
            out.push(format!("{}-", &line[..indent]));
            index += 1;
            continue;
        }
        let mut scheduled = None;
        let mut due = None;
        let mut clocked = Vec::new();
        let mut in_drawer = false;
        let mut next = index + 1;
        while next < lines.len() {
            let next_line = lines[next];
            let next_indent = leading_indent(next_line);
            if next_indent < indent {
                break;
            }
            let trimmed = next_line.trim_start_matches([' ', '\t']);

            // The task's own time tracking. Deliberately shape-driven rather
            // than a drawer parser: a real export stacks several :LOGBOOK:
            // blocks under one task and leaves stray CLOCK: lines between
            // them, so anything that breaks out on the first unexpected line
            // abandons the rest (one journal lost 102 of its 107 records that
            // way). Orphan :END: and empty drawers fall out for free.
            if trimmed == ":LOGBOOK:" || trimmed == ":END:" {
                in_drawer = trimmed == ":LOGBOOK:";
                next += 1;
                continue;
            }
            // org state-change records, which sit inside the drawer, and blank
            // lines that a real export leaves in there. Blanks are skipped only
            // *inside* a drawer: elsewhere a blank line ends the block and
            // swallowing it would merge this task into what follows.
            if trimmed.starts_with("- State \"") || (in_drawer && trimmed.is_empty()) {
                next += 1;
                continue;
            }
            // A noise property (`collapsed:: true`) can sit between the task
            // and its drawer. Only the known-noise keys are stepped over —
            // other `key:: value` lines are the user's own data and must stay.
            if property_line(next_line)
                .is_some_and(|(key, _)| is_noise_property(&key.to_ascii_lowercase()))
            {
                next += 1;
                continue;
            }
            if trimmed.starts_with("CLOCK:") {
                if let Some(entry) = parse_clock_line(trimmed) {
                    clocked.push(entry);
                }
                next += 1;
                continue;
            }

            let slot = if let Some(value) = trimmed.strip_prefix("SCHEDULED:") {
                Some((&mut scheduled, value))
            } else if let Some(value) = trimmed.strip_prefix("DEADLINE:") {
                Some((&mut due, value))
            } else {
                None
            };
            let Some((slot, value)) = slot else {
                break;
            };
            let Some(date) = first_date(value) else {
                break;
            };
            *slot = Some(date);
            next += 1;
        }
        out.push(format!("{}- QQTASK{}QQ", &line[..indent], tasks.len()));
        tasks.push(Task {
            text,
            status,
            priority,
            scheduled,
            due,
            clocked,
        });
        index = next;
    }
    (out.join("\n"), tasks, dropped_block_refs)
}

/// `CLOCK: [2025-12-25 Thu 12:33:43]--[2025-12-27 Sat 09:15:31] =>  44:41:48`
/// into `("2025-12-25T12:33:43", Some("2025-12-27T09:15:31"))`.
///
/// The trailing `=>` duration is ignored: it is redundant given both
/// timestamps, and in a real export it is sometimes damaged (`=> 01:22:[[10]]`,
/// `=> 1:0:00`). A clock that was started and never stopped has no second
/// timestamp and keeps `None`, so the record survives instead of being dropped.
fn parse_clock_line(line: &str) -> Option<(String, Option<String>)> {
    // Logseq linkifies bare numbers, so an hour can arrive as `[[11]]`. Undoing
    // that first keeps the bracket scan below honest — otherwise the `]]`
    // closes the timestamp early and the stamp is truncated.
    let line = line.replace("[[", "").replace("]]", "");
    let rest = line.trim().strip_prefix("CLOCK:")?;
    let mut stamps = rest.split("--").filter_map(|chunk| {
        let open = chunk.find('[')?;
        let close = chunk[open..].find(']')? + open;
        parse_clock_stamp(&chunk[open + 1..close])
    });
    let start = stamps.next()?;
    Some((start, stamps.next()))
}

/// `2025-12-25 Thu 12:33:43` into `2025-12-25T12:33:43`.
fn parse_clock_stamp(value: &str) -> Option<String> {
    let mut parts = value.split_whitespace();
    let date = parts.next()?;
    if date.len() != 10
        || !date.as_bytes().iter().enumerate().all(|(index, byte)| {
            if index == 4 || index == 7 {
                *byte == b'-'
            } else {
                byte.is_ascii_digit()
            }
        })
    {
        return None;
    }
    let mut units = parts.last()?.split(':').map(|unit| unit.parse::<u32>().ok());
    let hour = units.next()??;
    let minute = units.next()??;
    let second = units.next()??;
    if hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    Some(format!("{date}T{hour:02}:{minute:02}:{second:02}"))
}

fn parse_task_line(line: &str) -> Option<(usize, &'static str, &str)> {
    let indent = leading_indent(line);
    let value = line[indent..].strip_prefix("- ")?;
    let status_end = value.find(char::is_whitespace)?;
    let status = match &value[..status_end] {
        "TODO" | "LATER" | "WAITING" => "todo",
        "NOW" | "DOING" => "doing",
        "DONE" => "done",
        "CANCELED" | "CANCELLED" => "cancelled",
        _ => return None,
    };
    Some((indent, status, value[status_end..].trim_start()))
}

fn leading_indent(line: &str) -> usize {
    line.len() - line.trim_start_matches([' ', '\t']).len()
}

fn parse_priority(value: &str) -> (&'static str, &str) {
    for (marker, priority) in [("[#A]", "urgent"), ("[#B]", "high"), ("[#C]", "normal")] {
        if let Some(rest) = value.strip_prefix(marker) {
            return (priority, rest.trim_start());
        }
    }
    ("normal", value)
}

fn first_date(value: &str) -> Option<String> {
    value.as_bytes().windows(10).find_map(|date| {
        (date[4] == b'-'
            && date[7] == b'-'
            && date
                .iter()
                .enumerate()
                .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit()))
        .then(|| String::from_utf8_lossy(date).into_owned())
    })
}

fn replace_task_wikilinks(value: &str, targets: &mut Vec<Wikilink>) -> String {
    replace_wikilinks_with(value, targets, |_, display, _| display.to_owned())
}

fn replace_wikilinks(value: &str, targets: &mut Vec<Wikilink>) -> String {
    replace_wikilinks_with(value, targets, |_, _, index| format!("QQWL{index}QQ"))
}

fn replace_wikilinks_with(
    value: &str,
    targets: &mut Vec<Wikilink>,
    replacement: impl Fn(&str, &str, usize) -> String,
) -> String {
    let mut out = String::with_capacity(value.len());
    let mut rest = value;
    while let Some(start) = rest.find("[[") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let Some(end) = after.find("]]") else {
            out.push_str(&rest[start..]);
            return out;
        };
        let (target, display) = wikilink_parts(&after[..end]);
        let index = targets.len();
        targets.push(Wikilink {
            target: target.to_owned(),
            display: display.to_owned(),
        });
        out.push_str(&replacement(target, display, index));
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    out
}

fn wikilink_parts(value: &str) -> (&str, &str) {
    let (target, alias) = value.split_once('|').unwrap_or((value, ""));
    let target = target.trim();
    let alias = alias.trim();
    (target, if alias.is_empty() { target } else { alias })
}

fn rewrite_obsidian_embeds(value: &str) -> (String, Vec<String>) {
    let mut out = String::with_capacity(value.len());
    let mut assets = Vec::new();
    let mut rest = value;
    while let Some(start) = rest.find("![[") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 3..];
        let Some(end) = after.find("]]") else {
            out.push_str(&rest[start..]);
            return (out, assets);
        };
        let (target, display) = wikilink_parts(&after[..end]);
        if is_image_path(target) {
            let name = asset_basename(target);
            out.push_str(&format!("![{display}](assets/obsidian/{name})"));
            if !assets.iter().any(|asset| asset == target) {
                assets.push(target.to_owned());
            }
        } else {
            out.push_str("[[");
            out.push_str(&after[..end]);
            out.push_str("]]");
        }
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    (out, assets)
}

fn rewrite_obsidian_images(value: &str) -> (String, Vec<String>) {
    let mut out = String::with_capacity(value.len());
    let mut assets = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = value[cursor..].find("![") {
        let start = cursor + offset;
        let Some(label_end) = value[start + 2..].find("](").map(|end| start + 2 + end) else {
            break;
        };
        let destination_start = label_end + 2;
        let Some(close) = value[destination_start..].find(')') else {
            break;
        };
        let destination_end = destination_start + close;
        let inner = &value[destination_start..destination_end];
        let (prefix, destination, suffix) = image_destination(inner);
        out.push_str(&value[cursor..destination_start]);
        if is_relative_image(destination) && !destination.starts_with("assets/obsidian/") {
            out.push_str(prefix);
            out.push_str("assets/obsidian/");
            out.push_str(asset_basename(destination));
            out.push_str(suffix);
            if !assets.iter().any(|asset| asset == destination) {
                assets.push(destination.to_owned());
            }
        } else {
            out.push_str(inner);
        }
        out.push(')');
        cursor = destination_end + 1;
    }
    out.push_str(&value[cursor..]);
    (out, assets)
}

fn image_destination(value: &str) -> (&str, &str, &str) {
    let trimmed = value.trim_start();
    let leading = &value[..value.len() - trimmed.len()];
    if let Some(rest) = trimmed.strip_prefix('<')
        && let Some(end) = rest.find('>')
    {
        return (&value[..leading.len() + 1], &rest[..end], &rest[end..]);
    }
    let end = trimmed.find(char::is_whitespace).unwrap_or(trimmed.len());
    (leading, &trimmed[..end], &trimmed[end..])
}

fn is_relative_image(destination: &str) -> bool {
    !destination.is_empty()
        && !destination.starts_with(['/', '\\', '#'])
        && !destination.to_ascii_lowercase().starts_with("http://")
        && !destination.to_ascii_lowercase().starts_with("https://")
}

fn asset_basename(path: &str) -> &str {
    path.rsplit(['/', '\\']).next().unwrap_or(path)
}

fn drop_block_refs(value: &str) -> (String, usize) {
    let mut out = String::with_capacity(value.len());
    let mut rest = value;
    let mut dropped = 0;
    while let Some(start) = rest.find("((") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let Some(end) = after.find("))") else {
            out.push_str(&rest[start..]);
            return (out, dropped);
        };
        let token = after[..end].trim();
        if is_block_ref_token(token) {
            dropped += 1;
        } else {
            out.push_str(&rest[start..start + 2 + end + 2]);
        }
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    (out, dropped)
}

fn is_block_ref_token(value: &str) -> bool {
    value.len() >= 8
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

fn rewrite_asset_destinations(value: &str) -> (String, Vec<String>) {
    const PREFIX: &str = "../assets/";
    let mut out = String::with_capacity(value.len());
    let mut assets = Vec::new();
    let mut cursor = 0;
    while let Some(offset) = value[cursor..].find(PREFIX) {
        let start = cursor + offset;
        let before = &value[..start];
        let angle = before.ends_with("(<");
        if !angle && !before.ends_with('(') {
            out.push_str(&value[cursor..start + PREFIX.len()]);
            cursor = start + PREFIX.len();
            continue;
        }
        let name_start = start + PREFIX.len();
        let name_end = value[name_start..]
            .find(|character: char| {
                if angle {
                    character == '>'
                } else {
                    character == ')' || character.is_whitespace()
                }
            })
            .map(|offset| name_start + offset)
            .unwrap_or(value.len());
        let name = &value[name_start..name_end];
        out.push_str(&value[cursor..start]);
        out.push_str("assets/logseq/");
        out.push_str(name);
        let recorded = format!("assets/{}", percent_decode(name));
        if !assets.contains(&recorded) {
            assets.push(recorded);
        }
        cursor = name_end;
    }
    out.push_str(&value[cursor..]);
    (out, assets)
}

fn rewrite_asset_links(value: &str, dialect: SourceDialect) -> String {
    let format = match dialect {
        SourceDialect::Logseq => "logseq",
        SourceDialect::Obsidian => "obsidian",
    };
    let prefix = format!("#link(\"assets/{format}/");
    let mut out = String::with_capacity(value.len());
    let mut cursor = 0;
    while let Some(offset) = value[cursor..].find(&prefix) {
        let start = cursor + offset;
        out.push_str(&value[cursor..start]);
        let path_start = start + "#link(\"".len();
        let Some(path_end) = find_string_end(value, path_start) else {
            out.push_str(&value[start..]);
            return out;
        };
        if !value[path_end..].starts_with("\")[") {
            out.push_str(&value[start..path_end]);
            cursor = path_end;
            continue;
        }
        let content_start = path_end + 3;
        let Some(content_end) = find_bracket_end(value, content_start) else {
            out.push_str(&value[start..]);
            return out;
        };
        let path = percent_decode(&unescape_typst_string(&value[path_start..path_end]));
        let label = &value[content_start..content_end];
        if is_image_path(&path) {
            out.push_str(&format!("#image({})", typst_string(&format!("/{path}"))));
        } else {
            out.push_str(&format!(
                "#tylog.attachment({}, kind: \"file\")[{}]",
                typst_string(&path),
                label
            ));
        }
        cursor = content_end + 1;
    }
    out.push_str(&value[cursor..]);
    out
}

fn find_string_end(value: &str, start: usize) -> Option<usize> {
    let bytes = value.as_bytes();
    let mut index = start;
    while index < bytes.len() {
        match bytes[index] {
            b'\\' => index += 2,
            b'"' => return Some(index),
            _ => index += 1,
        }
    }
    None
}

fn find_bracket_end(value: &str, start: usize) -> Option<usize> {
    let bytes = value.as_bytes();
    let mut depth = 1;
    let mut index = start;
    while index < bytes.len() {
        match bytes[index] {
            b'\\' => index += 2,
            b'[' => {
                depth += 1;
                index += 1;
            }
            b']' => {
                depth -= 1;
                if depth == 0 {
                    return Some(index);
                }
                index += 1;
            }
            _ => index += 1,
        }
    }
    None
}

fn unescape_typst_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut characters = value.chars();
    while let Some(character) = characters.next() {
        if character == '\\' {
            if let Some(next) = characters.next() {
                out.push(next);
            }
        } else {
            out.push(character);
        }
    }
    out
}

fn is_image_path(path: &str) -> bool {
    let path = path.split(['?', '#']).next().unwrap_or(path);
    Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg"
            )
        })
}

fn assemble_note(
    dialect: SourceDialect,
    meta: &NoteMeta,
    source_name: &str,
    converted: &str,
) -> String {
    let mut out = String::new();
    out.push_str("#import \"/_system/tylog.typ\" as tylog\n\n");
    out.push_str("#show: tylog.note.with(\n");
    out.push_str(&format!("  id: {},\n", typst_string(&meta.id)));
    out.push_str(&format!("  title: {},\n", typst_string(&meta.title)));
    out.push_str(&format!("  kind: {},\n", typst_string(&meta.kind)));
    out.push_str(&format!(
        "  date: {},\n",
        meta.date
            .as_deref()
            .map(typst_string)
            .unwrap_or_else(|| "none".to_owned())
    ));
    out.push_str(&format!("  tags: {},\n", typst_tuple(&meta.tags)));
    out.push_str(&format!("  aliases: {},\n", typst_tuple(&meta.aliases)));
    out.push_str("  project: none,\n");
    out.push_str(&format!(
        "  properties: (\"import_format\": {}, \"import_source_name\": {}",
        typst_string(match dialect {
            SourceDialect::Logseq => "logseq",
            SourceDialect::Obsidian => "obsidian",
        }),
        typst_string(source_name)
    ));
    // A Typst dictionary rejects a repeated key outright, so the note stops
    // compiling and every reader falls back to source parsing. Logseq pages
    // routinely repeat a property line — one imported daily carried `login::`
    // and `pswrd::` eleven times each, and had been unqueryable ever since.
    // Suffixing keeps every value: dropping the duplicates would silently
    // delete ten of eleven credentials.
    let mut seen: HashMap<String, usize> = HashMap::new();
    seen.insert("import_format".to_owned(), 1);
    seen.insert("import_source_name".to_owned(), 1);
    for (key, value) in &meta.properties {
        if matches!(key.as_str(), "import_format" | "import_source_name") {
            continue;
        }
        let count = seen.entry(key.clone()).or_insert(0);
        *count += 1;
        let key = if *count == 1 {
            key.clone()
        } else {
            format!("{key}-{count}")
        };
        out.push_str(&format!(", {}: {}", typst_string(&key), typst_string(value)));
    }
    out.push_str(",),\n)\n\n");
    out.push_str(converted);
    out
}

fn typst_tuple(values: &[String]) -> String {
    if values.is_empty() {
        return "()".to_owned();
    }
    let mut tuple = "(".to_owned();
    for value in values {
        tuple.push_str(&typst_string(value));
        tuple.push_str(", ");
    }
    tuple.pop();
    tuple.push(')');
    tuple
}

fn typst_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%'
            && index + 2 < bytes.len()
            && let (Some(high), Some(low)) = (hex(bytes[index + 1]), hex(bytes[index + 2]))
        {
            decoded.push(high * 16 + low);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_logseq_page_end_to_end() {
        let note = convert_logseq_note(
            "pages/Shopping.md",
            "tags:: #A #B\n\n- TODO [#A] buy [[Milk]]\n  SCHEDULED: <2026-08-10 Mon>\n- See [[Milk]]\n- ![x](../assets/pic.png)\n",
        )
        .unwrap();

        assert!(note.typst.contains("  title: \"Shopping\","));
        assert!(note.typst.contains("  kind: \"note\","));
        assert!(note.typst.contains("  date: none,"));
        assert!(note.typst.contains("  tags: (\"A\", \"B\",),"));
        assert!(note.typst.contains("  aliases: (),"));
        assert!(
            note.typst
                .contains("\"import_format\": \"logseq\", \"import_source_name\": \"Shopping.md\"")
        );
        assert!(note.typst.contains("#tylog.task("));
        assert!(
            note.typst
                .contains("status: \"todo\", priority: \"urgent\", scheduled: \"2026-08-10\"")
        );
        assert!(note.typst.contains("#tylog.ref-note(\"Milk\")[Milk]"));
        assert!(note.typst.contains("#image(\"/assets/logseq/pic.png\")"));
        assert_eq!(note.referenced_assets, ["assets/pic.png"]);
    }

    /// The drawer sits between the task and its SCHEDULED: line, so the scan
    /// has to step over it — it used to stop at the first line that was not
    /// SCHEDULED:/DEADLINE:, hiding the date entirely.
    #[test]
    fn org_bookkeeping_is_dropped_and_stops_hiding_scheduled_dates() {
        let markdown = concat!(
            "- DONE Ship it\n",
            ":LOGBOOK:\n",
            "CLOCK: [2025-12-25 Thu 12:33:43]--[2025-12-27 Sat 09:15:31] =>  44:41:48\n",
            "- State \"DONE\" from \"LATER\" [2023-10-01 Sun]\n",
            ":END:\n",
            "SCHEDULED: <2026-08-10 Mon>\n",
            "- Real content\n",
            "-\n",
            "-\n",
        );

        let note = convert_logseq_note("pages/Log.md", markdown).expect("note");

        assert!(!note.typst.contains("LOGBOOK"));
        assert!(!note.typst.contains("CLOCK:"));
        assert!(!note.typst.contains("State \\\""));
        assert!(note.typst.contains("scheduled: \"2026-08-10\""));
        assert!(note.typst.contains("Real content"));
        // The trailing empty blocks every Logseq page ends with are gone, and
        // nothing else picked up a stray bullet.
        assert!(note.typst.trim_end().ends_with("Real content"));
    }

    /// An unclosed drawer and an orphan :END: both exist in the real vault; a
    /// drawer parser would either leak them or eat everything after the opener.
    /// Time tracking is the whole point of the drawer: the CLOCK records are
    /// the user's own data and must land on the task, not be discarded.
    #[test]
    fn logbook_clock_records_are_captured_onto_the_task() {
        let markdown = concat!(
            "- DONE Ship it\n",
            "  :LOGBOOK:\n",
            "  CLOCK: [2025-12-25 Thu 12:33:43]--[2025-12-27 Sat 09:15:31] =>  44:41:48\n",
            "  CLOCK: [2025-12-28 Sun 10:02:11]\n",
            "  :END:\n",
        );

        let note = convert_logseq_note("pages/Log.md", markdown).expect("note");

        assert!(note.typst.contains(
            r#"properties: ("clocked": (("2025-12-25T12:33:43", "2025-12-27T09:15:31"), ("2025-12-28T10:02:11", none),),)"#
        ));
        assert!(!note.typst.contains("LOGBOOK"));
        assert!(!note.typst.contains("CLOCK:"));
    }

    /// Both damage patterns seen in the real export: Logseq linkified a number
    /// inside the timestamp, and the trailing `=>` duration is unreliable, so
    /// elapsed time is derived from the stamps instead.
    #[test]
    fn damaged_clock_lines_still_parse() {
        let markdown = concat!(
            "- DONE A\n",
            "  :LOGBOOK:\n",
            "  CLOCK: [2023-02-20 Mon 17:08:32]--[2023-02-20 Mon 18:08:32] =>  1:0:00\n",
            "  CLOCK: [2025-12-23 Tue [[11]]:51:04]--[2025-12-23 Tue 13:13:14] =>  01:22:[[10]]\n",
            "  :END:\n",
        );

        let note = convert_logseq_note("pages/Odd.md", markdown).expect("note");

        assert!(note.typst.contains(r#"("2023-02-20T17:08:32", "2023-02-20T18:08:32")"#));
        assert!(note.typst.contains(r#"("2025-12-23T11:51:04", "2025-12-23T13:13:14")"#));
    }

    #[test]
    fn unbalanced_drawers_do_not_swallow_content() {
        let note = convert_logseq_note(
            "pages/Odd.md",
            "- before\n:END:\n- middle\n:LOGBOOK:\nCLOCK: x\n- after\n",
        )
        .expect("note");

        assert!(note.typst.contains("before"));
        assert!(note.typst.contains("middle"));
        assert!(note.typst.contains("after"));
        assert!(!note.typst.contains(":END:"));
        assert!(!note.typst.contains("LOGBOOK"));
    }

    #[test]
    fn repeated_property_keys_do_not_break_the_dictionary() {
        // A Typst dictionary rejects a repeated key, so this note stopped
        // compiling and every reader fell back to source parsing. One imported
        // daily in the real vault carried `login::` and `pswrd::` eleven times
        // each and had been unqueryable since the import.
        let note = convert_logseq_note(
            "journals/2025_03_14.md",
            "login:: a@example.com\npswrd:: one\nlogin:: b@example.com\npswrd:: two\n\n- entry",
        )
        .unwrap();
        let typst = assemble_note(SourceDialect::Logseq, &note.meta, "2025_03_14.md", "");

        assert!(typst.contains("\"login\": \"a@example.com\""));
        assert!(typst.contains("\"login-2\": \"b@example.com\""));
        assert!(typst.contains("\"pswrd\": \"one\""));
        assert!(
            typst.contains("\"pswrd-2\": \"two\""),
            "every value survives - dropping duplicates would delete data"
        );
        // And no key appears twice, which is the whole point.
        let keys: Vec<&str> = typst
            .split(", \"")
            .skip(1)
            .filter_map(|part| part.split("\": ").next())
            .collect();
        let mut unique = keys.clone();
        unique.sort_unstable();
        unique.dedup();
        assert_eq!(keys.len(), unique.len(), "duplicate key in {typst}");
    }

    #[test]
    fn maps_logseq_journal_path() {
        let note = convert_logseq_note("journals/2022_01_05.md", "- journal entry").unwrap();
        assert_eq!(note.rel_path, "daily/2022/01/2022-01-05.typ");
        assert_eq!(note.meta.kind, "daily");
        assert_eq!(note.meta.id, "2022-01-05");
    }

    #[test]
    fn converts_obsidian_note_end_to_end() {
        let note = convert_vault_note(
            SourceDialect::Obsidian,
            "folder/sub/Original.md",
            "---\ntitle: Override\ntags: [#one, two]\naliases:\n  - Other\nextra: value\n---\nSee [[Real|Shown]].\n\n![[pic.png]]\n\n![other](folder/other.jpg)\n\n- [ ] waiting\n",
        )
        .unwrap();

        assert_eq!(note.rel_path, "notes/Original.typ");
        assert_eq!(note.meta.title, "Override");
        assert_eq!(note.meta.tags, ["one", "two"]);
        assert_eq!(note.meta.aliases, ["Other"]);
        assert_eq!(note.meta.properties, [("extra".into(), "value".into())]);
        assert!(note.typst.contains("\"import_format\": \"obsidian\""));
        assert!(note.typst.contains("#tylog.ref-note(\"Real\")[Shown]"));
        assert!(note.typst.contains("#image(\"/assets/obsidian/pic.png\")"));
        assert!(
            note.typst
                .contains("#image(\"/assets/obsidian/other.jpg\")")
        );
        assert!(note.typst.contains("☐ waiting"));
        assert_eq!(note.referenced_assets, ["pic.png", "folder/other.jpg"]);
        assert_eq!(note.wikilink_targets, ["Real"]);
    }

    #[test]
    fn maps_obsidian_journal_path() {
        let note = convert_vault_note(
            SourceDialect::Obsidian,
            "daily notes/2024-05-01.md",
            "journal entry",
        )
        .unwrap();

        assert_eq!(note.rel_path, "daily/2024/05/2024-05-01.typ");
        assert_eq!(note.meta.kind, "daily");
        assert_eq!(note.meta.id, "2024-05-01");
        assert_eq!(note.meta.title, "2024-05-01");
    }

    #[test]
    fn converts_logseq_pipe_alias() {
        let note = convert_logseq_note(
            "pages/List.md",
            "- Buy [[Milk|молоко]]\n- TODO [[Eggs|яйца]]",
        )
        .unwrap();

        assert!(note.typst.contains("#tylog.ref-note(\"Milk\")[молоко]"));
        assert!(note.typst.contains("text: \"яйца\""));
        assert!(note.wikilink_targets.iter().any(|target| target == "Milk"));
        assert!(note.wikilink_targets.iter().any(|target| target == "Eggs"));
    }

    #[test]
    fn skips_empty_bullets() {
        assert!(convert_logseq_note("pages/Empty.md", "- \n-").is_none());
    }

    #[test]
    fn converts_logseq_highlights() {
        let note = convert_logseq_note("pages/Highlights.md", "- ==marked== and ^^also^^").unwrap();

        assert!(note.typst.contains("#highlight[marked]"));
        assert!(note.typst.contains("#highlight[also]"));
    }

    #[test]
    fn preserves_logseq_math() {
        let note = convert_logseq_note("pages/Math.md", "- $E = mc^2$\n- $$\\int x$$").unwrap();

        assert!(note.typst.contains("$E = mc^2$"));
        assert!(!note.typst.contains("\\$E \\= mc^2\\$"));
        assert!(note.typst.contains("$ \\int x $"));
    }

    #[test]
    fn promotes_logseq_bullet_headings() {
        let note = convert_logseq_note("pages/Heading.md", "- # Section\n- body line").unwrap();

        assert!(note.typst.lines().any(|line| line == "= Section"));
        assert!(note.typst.lines().any(|line| line == "- body line"));
    }

    #[test]
    fn strips_logseq_image_sizing_hints() {
        let note =
            convert_logseq_note("pages/Image.md", "- ![x](../assets/p.png){:width 320}").unwrap();

        assert!(!note.typst.contains("{:width"));
        assert!(note.typst.contains("#image(\"/assets/logseq/p.png\")"));
    }

    #[test]
    fn converts_logseq_order_list_property() {
        let note = convert_logseq_note(
            "pages/List.md",
            "- logseq.order-list-type:: number\n- First\n  - nested\n- Second\n- Third",
        )
        .unwrap();

        assert!(!note.typst.contains("order-list-type"));
        assert!(note.typst.contains("+ First"));
        assert!(note.typst.contains("- nested"));
        assert!(note.typst.contains("+ Second"));
        assert!(note.typst.contains("+ Third"));
    }

    #[test]
    fn resolves_same_file_logseq_block_refs() {
        let note = convert_logseq_note(
            "pages/Refs.md",
            "- The target block [[topic]]\n  id:: abc12345-6789\n- see ((abc12345-6789))\n- missing ((deadbeef-0000))",
        )
        .unwrap();

        assert!(
            note.typst
                .contains("see The target block #tylog.ref-note(\"topic\")[topic]")
        );
        assert!(note.typst.contains("- missing"));
        assert!(!note.typst.contains("deadbeef-0000"));
        assert_eq!(note.dropped_block_refs, 1);
    }
}
