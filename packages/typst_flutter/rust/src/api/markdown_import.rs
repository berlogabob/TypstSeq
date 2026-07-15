#[derive(Debug, Clone)]
pub struct MarkdownImportDiagnostic {
    pub code: String,
    pub message: String,
    pub line: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct MarkdownTypstResult {
    pub typst: String,
    pub diagnostics: Vec<MarkdownImportDiagnostic>,
}

pub fn convert_markdown(
    markdown: String,
    title: String,
    base_url: Option<String>,
) -> MarkdownTypstResult {
    let converted = tylog_import_core::convert_markdown(
        &markdown,
        &title,
        base_url.as_deref(),
    );
    MarkdownTypstResult {
        typst: converted.typst,
        diagnostics: converted
            .diagnostics
            .into_iter()
            .map(|item| MarkdownImportDiagnostic {
                code: item.code,
                message: item.message,
                line: item.line,
            })
            .collect(),
    }
}
