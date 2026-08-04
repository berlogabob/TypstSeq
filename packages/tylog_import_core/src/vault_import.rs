use std::path::Path;

use crate::{convert_markdown, escape_markup};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceDialect {
    Logseq,
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
}

#[derive(Debug)]
struct Preprocessed {
    markdown: String,
    tasks: Vec<Task>,
    wikilinks: Vec<String>,
    assets: Vec<String>,
    dropped_block_refs: usize,
    stripped_macros: usize,
}

pub fn convert_logseq_note(source_rel_path: &str, markdown: &str) -> Option<ConvertedNote> {
    let (meta, body, source_name) = extract_metadata(source_rel_path, markdown);
    if body_is_empty(&body) {
        return None;
    }

    let preprocessed = preprocess(&body);
    let converted = convert_markdown(&preprocessed.markdown, &meta.title, None);
    let mut typst = converted.typst;

    for (index, target) in preprocessed.wikilinks.iter().enumerate() {
        typst = typst.replace(
            &format!("QQWL{index}QQ"),
            &format!(
                "#tylog.ref-note({})[{}]",
                typst_string(target),
                escape_markup(target)
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
        call.push(')');
        typst = typst.replace(&format!("QQTASK{index}QQ"), &call);
    }
    typst = rewrite_asset_links(&typst);

    let rel_path = if let Some(date) = &meta.date {
        format!("daily/{}/{}/{}.typ", &date[..4], &date[5..7], date)
    } else {
        format!("notes/{}.typ", sanitize_title(&meta.title))
    };
    let typst = assemble_note(&meta, &source_name, &typst);

    Some(ConvertedNote {
        rel_path,
        typst,
        referenced_assets: preprocessed.assets,
        wikilink_targets: preprocessed.wikilinks,
        diagnostics: converted
            .diagnostics
            .into_iter()
            .map(|diagnostic| diagnostic.message)
            .collect(),
        meta,
        dropped_block_refs: preprocessed.dropped_block_refs,
        stripped_macros: preprocessed.stripped_macros,
    })
}

fn extract_metadata(source_rel_path: &str, markdown: &str) -> (NoteMeta, String, String) {
    let source_name = source_rel_path
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(source_rel_path)
        .to_owned();
    let stem = source_name.strip_suffix(".md").unwrap_or(&source_name);
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
        "collapsed" | "id" | "ls-type" | "hl-page" | "hl-color" | "hl-stamp"
    )
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

fn preprocess(markdown: &str) -> Preprocessed {
    let (markdown, stripped_macros) = rewrite_macros(markdown);
    let mut wikilinks = Vec::new();
    let (markdown, tasks, task_block_refs) = extract_tasks(&markdown, &mut wikilinks);
    let markdown = replace_wikilinks(&markdown, &mut wikilinks);
    let (markdown, body_block_refs) = drop_block_refs(&markdown);
    let (markdown, assets) = rewrite_asset_destinations(&markdown);
    Preprocessed {
        markdown,
        tasks,
        wikilinks,
        assets,
        dropped_block_refs: task_block_refs + body_block_refs,
        stripped_macros,
    }
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

fn extract_tasks(markdown: &str, wikilinks: &mut Vec<String>) -> (String, Vec<Task>, usize) {
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
        let mut next = index + 1;
        while next < lines.len() {
            let next_line = lines[next];
            let next_indent = leading_indent(next_line);
            if next_indent < indent {
                break;
            }
            let trimmed = next_line.trim_start_matches([' ', '\t']);
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
        });
        index = next;
    }
    (out.join("\n"), tasks, dropped_block_refs)
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

fn replace_task_wikilinks(value: &str, targets: &mut Vec<String>) -> String {
    replace_wikilinks_with(value, targets, |target, _| target.to_owned())
}

fn replace_wikilinks(value: &str, targets: &mut Vec<String>) -> String {
    replace_wikilinks_with(value, targets, |_, index| format!("QQWL{index}QQ"))
}

fn replace_wikilinks_with(
    value: &str,
    targets: &mut Vec<String>,
    replacement: impl Fn(&str, usize) -> String,
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
        let target = after[..end].trim();
        let index = targets.len();
        targets.push(target.to_owned());
        out.push_str(&replacement(target, index));
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    out
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
        if token.len() >= 8
            && token
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
        {
            dropped += 1;
        } else {
            out.push_str(&rest[start..start + 2 + end + 2]);
        }
        rest = &after[end + 2..];
    }
    out.push_str(rest);
    (out, dropped)
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

fn rewrite_asset_links(value: &str) -> String {
    const PREFIX: &str = "#link(\"assets/logseq/";
    let mut out = String::with_capacity(value.len());
    let mut cursor = 0;
    while let Some(offset) = value[cursor..].find(PREFIX) {
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

fn assemble_note(meta: &NoteMeta, source_name: &str, converted: &str) -> String {
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
        "  properties: (\"import_format\": \"logseq\", \"import_source_name\": {}",
        typst_string(source_name)
    ));
    for (key, value) in &meta.properties {
        if matches!(key.as_str(), "import_format" | "import_source_name") {
            continue;
        }
        out.push_str(&format!(", {}: {}", typst_string(key), typst_string(value)));
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

    #[test]
    fn maps_logseq_journal_path() {
        let note = convert_logseq_note("journals/2022_01_05.md", "- journal entry").unwrap();
        assert_eq!(note.rel_path, "daily/2022/01/2022-01-05.typ");
        assert_eq!(note.meta.kind, "daily");
        assert_eq!(note.meta.id, "2022-01-05");
    }

    #[test]
    fn skips_empty_bullets() {
        assert!(convert_logseq_note("pages/Empty.md", "- \n-").is_none());
    }
}
