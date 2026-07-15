use comrak::nodes::{AstNode, ListType, NodeValue};
use comrak::{Arena, Options, parse_document};
use url::Url;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportDiagnostic {
    pub code: String,
    pub message: String,
    pub line: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownConversion {
    pub typst: String,
    pub diagnostics: Vec<ImportDiagnostic>,
}

pub fn convert_markdown(markdown: &str, title: &str, base_url: Option<&str>) -> MarkdownConversion {
    let arena = Arena::new();
    let mut options = Options::default();
    options.extension.strikethrough = true;
    options.extension.tagfilter = true;
    options.extension.table = true;
    options.extension.autolink = true;
    options.extension.tasklist = true;
    options.parse.sourcepos_chars = true;

    let root = parse_document(&arena, markdown, &options);
    let mut renderer = TypstRenderer {
        base_url: base_url.and_then(|value| Url::parse(value).ok()),
        diagnostics: Vec::new(),
    };
    if base_url.is_some() && renderer.base_url.is_none() {
        renderer.diagnostics.push(ImportDiagnostic {
            code: "invalid-base-url".into(),
            message: "Article URL is invalid; relative links were left unresolved".into(),
            line: None,
        });
    }

    let mut typst = format!("= {}\n\n", escape_markup(title.trim()));
    let mut first = true;
    for child in root.children() {
        if first && is_matching_title(child, title) {
            first = false;
            continue;
        }
        first = false;
        renderer.render_block(child, 0, &mut typst);
    }

    MarkdownConversion {
        typst: typst.trim_end().to_owned() + "\n",
        diagnostics: renderer.diagnostics,
    }
}

struct TypstRenderer {
    base_url: Option<Url>,
    diagnostics: Vec<ImportDiagnostic>,
}

impl TypstRenderer {
    fn render_block<'a>(&mut self, node: &'a AstNode<'a>, indent: usize, out: &mut String) {
        let value = node.data().value.clone();
        match value {
            NodeValue::Paragraph => {
                self.render_inline_children(node, out);
                out.push_str("\n\n");
            }
            NodeValue::Heading(heading) => {
                out.push_str(&"=".repeat(usize::from(heading.level)));
                out.push(' ');
                self.render_inline_children(node, out);
                out.push_str("\n\n");
            }
            NodeValue::BlockQuote => {
                out.push_str("#quote(block: true)[\n");
                for child in node.children() {
                    self.render_block(child, indent + 1, out);
                }
                out.push_str("]\n\n");
            }
            NodeValue::List(list) => self.render_list(node, list.list_type, indent, out),
            NodeValue::CodeBlock(code) => {
                write_raw_block(out, &code.literal, &code.info);
                out.push_str("\n\n");
            }
            NodeValue::ThematicBreak => out.push_str("#line(length: 100%)\n\n"),
            NodeValue::Table(table) => self.render_table(node, table.num_columns, out),
            NodeValue::HtmlBlock(html) => {
                self.warn(node, "html-block", "HTML block preserved as raw text");
                write_raw_block(out, &html.literal, "html");
                out.push_str("\n\n");
            }
            NodeValue::Document => {
                for child in node.children() {
                    self.render_block(child, indent, out);
                }
            }
            NodeValue::FrontMatter(front) => {
                self.warn(
                    node,
                    "front-matter",
                    "Unexpected nested frontmatter preserved as raw text",
                );
                write_raw_block(out, &front, "yaml");
                out.push_str("\n\n");
            }
            NodeValue::FootnoteDefinition(_) | NodeValue::DescriptionList => {
                self.warn(
                    node,
                    "unsupported-block",
                    "Unsupported Markdown block preserved as text",
                );
                self.render_inline_children(node, out);
                out.push_str("\n\n");
            }
            _ => {
                if node.first_child().is_some() {
                    for child in node.children() {
                        self.render_block(child, indent, out);
                    }
                }
            }
        }
    }

    fn render_list<'a>(
        &mut self,
        node: &'a AstNode<'a>,
        kind: ListType,
        indent: usize,
        out: &mut String,
    ) {
        for item in node.children() {
            let marker = if kind == ListType::Ordered { '+' } else { '-' };
            out.push_str(&"  ".repeat(indent));
            out.push(marker);
            out.push(' ');
            if let NodeValue::TaskItem(task) = item.data().value {
                out.push_str(if task.symbol.is_some() {
                    "☒ "
                } else {
                    "☐ "
                });
            }

            let mut wrote = false;
            for child in item.children() {
                match child.data().value.clone() {
                    NodeValue::Paragraph => {
                        if wrote {
                            out.push_str(&"  ".repeat(indent + 1));
                        }
                        self.render_inline_children(child, out);
                        out.push('\n');
                        wrote = true;
                    }
                    NodeValue::List(nested) => {
                        if !wrote {
                            out.push('\n');
                            wrote = true;
                        }
                        self.render_list(child, nested.list_type, indent + 1, out);
                    }
                    _ => {
                        self.render_inline(child, out);
                        wrote = true;
                    }
                }
            }
            if !wrote {
                out.push('\n');
            }
        }
        if indent == 0 {
            out.push('\n');
        }
    }

    fn render_table<'a>(&mut self, node: &'a AstNode<'a>, columns: usize, out: &mut String) {
        out.push_str(&format!("#table(\n  columns: {columns},\n"));
        for row in node.children() {
            let header = matches!(row.data().value, NodeValue::TableRow(true));
            if header {
                out.push_str("  table.header(");
            } else {
                out.push_str("  ");
            }
            for cell in row.children() {
                out.push('[');
                self.render_inline_children(cell, out);
                out.push_str("], ");
            }
            if header {
                out.push_str("),\n");
            } else {
                out.push('\n');
            }
        }
        out.push_str(")\n\n");
    }

    fn render_inline_children<'a>(&mut self, node: &'a AstNode<'a>, out: &mut String) {
        for child in node.children() {
            self.render_inline(child, out);
            if needs_markup_boundary(child) {
                out.push(' ');
            }
        }
    }

    fn render_inline<'a>(&mut self, node: &'a AstNode<'a>, out: &mut String) {
        let value = node.data().value.clone();
        match value {
            NodeValue::Text(text) => out.push_str(&escape_markup(&text)),
            NodeValue::SoftBreak => out.push('\n'),
            NodeValue::LineBreak => out.push_str("\\\n"),
            NodeValue::Code(code) => write_raw_inline(out, &code.literal),
            NodeValue::Emph => self.wrap_inline(node, "#emph[", "]", out),
            NodeValue::Strong => self.wrap_inline(node, "#strong[", "]", out),
            NodeValue::Strikethrough => self.wrap_inline(node, "#strike[", "]", out),
            NodeValue::Link(link) => {
                let label = collect_plain_text(node);
                if let Some(url) = self.resolve_link(node, &link.url) {
                    out.push_str("#link(");
                    out.push_str(&typst_string(&url));
                    out.push_str(")[");
                    self.render_inline_children(node, out);
                    out.push(']');
                } else if label.is_empty() {
                    out.push_str(&escape_markup(&link.url));
                } else {
                    self.render_inline_children(node, out);
                }
            }
            NodeValue::Image(link) => {
                self.warn(
                    node,
                    "remote-image",
                    "Image kept as a link; asset import is not part of article import",
                );
                let alt = collect_plain_text(node);
                let label = if alt.trim().is_empty() {
                    "Image"
                } else {
                    alt.trim()
                };
                if let Some(url) = self.resolve_link(node, &link.url) {
                    out.push_str("#link(");
                    out.push_str(&typst_string(&url));
                    out.push_str(")[Image: ");
                    out.push_str(&escape_markup(label));
                    out.push(']');
                } else {
                    out.push_str("Image: ");
                    out.push_str(&escape_markup(label));
                }
            }
            NodeValue::HtmlInline(html) => {
                self.warn(node, "html-inline", "Inline HTML preserved as raw text");
                write_raw_inline(out, &html);
            }
            NodeValue::TaskItem(task) => {
                out.push_str(if task.symbol.is_some() {
                    "☒ "
                } else {
                    "☐ "
                });
                self.render_inline_children(node, out);
            }
            NodeValue::FootnoteReference(reference) => {
                self.warn(node, "footnote", "Footnote reference preserved as text");
                out.push('[');
                out.push_str(&escape_markup(&reference.name));
                out.push(']');
            }
            _ => self.render_inline_children(node, out),
        }
    }

    fn wrap_inline<'a>(
        &mut self,
        node: &'a AstNode<'a>,
        before: &str,
        after: &str,
        out: &mut String,
    ) {
        out.push_str(before);
        self.render_inline_children(node, out);
        out.push_str(after);
    }

    fn resolve_link<'a>(&mut self, node: &'a AstNode<'a>, target: &str) -> Option<String> {
        let parsed = Url::parse(target).ok().or_else(|| {
            self.base_url
                .as_ref()
                .and_then(|base| base.join(target).ok())
        });
        let Some(url) = parsed else {
            self.warn(
                node,
                "unresolved-link",
                "Relative link has no valid article URL base",
            );
            return None;
        };
        if matches!(url.scheme(), "http" | "https" | "mailto") {
            Some(url.to_string())
        } else {
            self.warn(
                node,
                "unsafe-link",
                "Unsupported link scheme was kept as plain text",
            );
            None
        }
    }

    fn warn<'a>(&mut self, node: &'a AstNode<'a>, code: &str, message: &str) {
        self.diagnostics.push(ImportDiagnostic {
            code: code.into(),
            message: message.into(),
            line: Some(node.data().sourcepos.start.line),
        });
    }
}

fn is_matching_title<'a>(node: &'a AstNode<'a>, title: &str) -> bool {
    matches!(node.data().value, NodeValue::Heading(ref heading) if heading.level == 1)
        && normalize_title(&collect_plain_text(node)) == normalize_title(title)
}

fn normalize_title(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn collect_plain_text<'a>(node: &'a AstNode<'a>) -> String {
    let mut value = String::new();
    for child in node.descendants() {
        match &child.data().value {
            NodeValue::Text(text) => value.push_str(text),
            NodeValue::Code(code) => value.push_str(&code.literal),
            NodeValue::SoftBreak | NodeValue::LineBreak => value.push(' '),
            _ => {}
        }
    }
    value
}

fn needs_markup_boundary<'a>(node: &'a AstNode<'a>) -> bool {
    if !matches!(
        node.data().value,
        NodeValue::Link(_)
            | NodeValue::Image(_)
            | NodeValue::Emph
            | NodeValue::Strong
            | NodeValue::Strikethrough
    ) {
        return false;
    }
    let Some(next) = node.next_sibling() else {
        return false;
    };
    matches!(
        &next.data().value,
        NodeValue::Text(text)
            if text.starts_with('(') || text.starts_with('[') || text.starts_with('{')
    )
}

fn escape_markup(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for character in value.chars() {
        if matches!(
            character,
            '\\' | '#'
                | '$'
                | '*'
                | '_'
                | '`'
                | '<'
                | '>'
                | '@'
                | '['
                | ']'
                | '~'
                | '='
                | '-'
                | '+'
                | '/'
        ) {
            out.push('\\');
        }
        out.push(character);
    }
    out
}

fn typst_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn raw_fence(value: &str, minimum: usize) -> String {
    let longest = value
        .split(|character| character != '`')
        .map(str::len)
        .max()
        .unwrap_or_default();
    "`".repeat(minimum.max(longest + 1))
}

fn write_raw_inline(out: &mut String, value: &str) {
    let fence = raw_fence(value, 1);
    out.push_str(&fence);
    out.push_str(value);
    out.push_str(&fence);
}

fn write_raw_block(out: &mut String, value: &str, info: &str) {
    let fence = raw_fence(value, 3);
    out.push_str(&fence);
    let language = info.split_whitespace().next().unwrap_or_default();
    if !language.is_empty()
        && language
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
    {
        out.push_str(language);
    }
    out.push('\n');
    out.push_str(value.trim_end());
    out.push('\n');
    out.push_str(&fence);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_core_gfm_to_editable_typst() {
        let converted = convert_markdown(
            "# Article\n\nHello **strong** and *soft* with [docs](/guide).\n\n- one\n- [x] done\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n```rust\nfn main() {}\n```\n",
            "Article",
            Some("https://example.com/post"),
        );
        assert!(
            converted
                .typst
                .starts_with("= Article\n\nHello #strong[strong] and #emph[soft]")
        );
        assert!(
            converted
                .typst
                .contains("#link(\"https://example.com/guide\")[docs]")
        );
        assert!(converted.typst.contains("- one"));
        assert!(converted.typst.contains("☒ done"));
        assert!(converted.typst.contains("#table("));
        assert!(converted.typst.contains("```rust"));
    }

    #[test]
    fn escapes_typst_and_reports_unsupported_content() {
        let converted = convert_markdown(
            "Text with #hash, $money, @ref, [brackets], and <span>html</span>.\n\n<div>block</div>\n",
            "A *literal* title",
            None,
        );
        assert!(converted.typst.starts_with("= A \\*literal\\* title"));
        assert!(converted.typst.contains("\\#hash"));
        assert!(converted.typst.contains("\\$money"));
        assert!(
            converted
                .diagnostics
                .iter()
                .any(|item| item.code.starts_with("html-"))
        );
    }

    #[test]
    fn unsafe_and_unresolved_links_degrade_to_text() {
        let converted = convert_markdown(
            "[relative](page.md) [unsafe](javascript:alert(1))",
            "Links",
            None,
        );
        assert_eq!(converted.typst, "= Links\n\nrelative unsafe\n");
        assert_eq!(converted.diagnostics.len(), 2);
    }

    #[test]
    fn converts_nested_structure_and_line_markup() {
        let converted = convert_markdown(
            "> Quoted **text**\n\n1. first\n2. second\n   - nested\n\n- [ ] waiting\n\n~~gone~~ and `a ` b`  \nnext\n\n---\n",
            "Structure",
            None,
        );
        assert!(converted.typst.contains("#quote(block: true)["));
        assert!(converted.typst.contains("+ first"));
        assert!(converted.typst.contains("  - nested"));
        assert!(converted.typst.contains("☐ waiting"));
        assert!(converted.typst.contains("#strike[gone]"));
        assert!(converted.typst.contains("next"));
        assert!(converted.typst.contains("#line(length: 100%)"));
    }

    #[test]
    fn images_become_resolved_links_and_unicode_is_preserved() {
        let converted = convert_markdown(
            "![схема](images/plan.png) and <https://typst.app> — café 中文",
            "Unicode",
            Some("https://example.com/articles/post"),
        );
        assert!(
            converted
                .typst
                .contains("#link(\"https://example.com/articles/images/plan.png\")[Image: схема]")
        );
        assert!(converted.typst.contains("café 中文"));
        assert!(
            converted
                .diagnostics
                .iter()
                .any(|item| item.code == "remote-image")
        );
    }

    #[test]
    fn raw_fences_expand_around_embedded_backticks() {
        let converted = convert_markdown(
            "````txt\nvalue ``` inside\n````\n\nInline ``a ` b``.",
            "Raw",
            None,
        );
        assert!(converted.typst.contains("````txt\nvalue ``` inside\n````"));
        assert!(converted.typst.contains("``a ` b``"));
    }

    #[test]
    fn separates_typst_functions_from_adjacent_delimiters() {
        let converted = convert_markdown(
            "[WikiPron](https://example.com)(CUNY-CL) and **bold**(detail)",
            "Boundaries",
            None,
        );
        assert!(converted.typst.contains("[WikiPron] (CUNY\\-CL)"));
        assert!(converted.typst.contains("#strong[bold] (detail)"));
    }
}
