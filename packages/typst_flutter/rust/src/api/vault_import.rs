#[derive(Debug, Clone)]
pub struct VaultNoteProperty {
    pub key: String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct VaultNoteResult {
    pub rel_path: String,
    pub typst: String,
    pub referenced_assets: Vec<String>,
    pub wikilink_targets: Vec<String>,
    pub diagnostics: Vec<String>,
    pub id: String,
    pub title: String,
    pub kind: String,
    pub date: Option<String>,
    pub tags: Vec<String>,
    pub aliases: Vec<String>,
    pub properties: Vec<VaultNoteProperty>,
    pub dropped_block_refs: u32,
    pub stripped_macros: u32,
}

pub fn convert_vault_note(
    dialect: String,
    source_rel_path: String,
    markdown: String,
) -> Option<VaultNoteResult> {
    let dialect = match dialect.as_str() {
        "obsidian" => tylog_import_core::vault_import::SourceDialect::Obsidian,
        _ => tylog_import_core::vault_import::SourceDialect::Logseq,
    };
    let note =
        tylog_import_core::vault_import::convert_vault_note(dialect, &source_rel_path, &markdown)?;

    Some(VaultNoteResult {
        rel_path: note.rel_path,
        typst: note.typst,
        referenced_assets: note.referenced_assets,
        wikilink_targets: note.wikilink_targets,
        diagnostics: note.diagnostics,
        id: note.meta.id,
        title: note.meta.title,
        kind: note.meta.kind,
        date: note.meta.date,
        tags: note.meta.tags,
        aliases: note.meta.aliases,
        properties: note
            .meta
            .properties
            .into_iter()
            .map(|(key, value)| VaultNoteProperty { key, value })
            .collect(),
        dropped_block_refs: note.dropped_block_refs as u32,
        stripped_macros: note.stripped_macros as u32,
    })
}
