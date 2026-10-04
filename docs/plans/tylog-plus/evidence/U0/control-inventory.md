# U0 control inventory

Source audit of live Flutter controls under `lib/`, based on the U0 requirement in
`docs/plans/tylog-plus/plan.typ` (the requested `plan.md` is not present) and the
archived status in `docs/ui-fix-status.md`. Line numbers are source locations;
`pending` is intentional because no device run was requested.

2026-10-04: View-mode menu has four 48 dp items: Edit (`edit_outlined`),
Read (`chrome_reader_mode_outlined`), Preview (`preview_outlined`), Source
(`code`). Each has a leading icon; the current item has a trailing check.
The menu button shows the current mode's icon. PDF page size is inventoried
below; no new Mac/A24 verification is claimed.

| ID | Surface | Control label/icon | Source (path:line) | Action/outcome expected | Platforms | Long-press-only? | Existing test covering it | Mac result | A24 result |
|---|---|---|---|---|---|---|---|---|---|
| U0-TODAY-01 | Today/journal | Today navigation | lib/app_mobile.dart:4321 | Open Today surface | both | no | test/today_page_test.dart | pending | pending |
| U0-TODAY-02 | Today/journal | Previous day | lib/app_mobile.dart:4195 | Open previous calendar day | both | no | none | pending | pending |
| U0-TODAY-03 | Today/journal | Calendar date | lib/app_mobile.dart:4204 | Open calendar picker | both | no | none | pending | pending |
| U0-TODAY-04 | Today/journal | Next day | lib/app_mobile.dart:4226 | Open next calendar day | both | no | none | pending | pending |
| U0-TODAY-05 | Today/journal | Choose journal date | lib/app_mobile.dart:4243 | Open calendar picker | both | no | none | pending | pending |
| U0-TODAY-06 | Today/journal | Task row | lib/widgets/work_surface.dart:130 | Open task source note | both | no | test/agenda_filter_test.dart | pending | pending |
| U0-TODAY-07 | Today/journal | Open source note | lib/widgets/work_surface.dart:133 | Open task source note | both | no | none | pending | pending |
| U0-TODAY-08 | Today/journal | Task checkbox | lib/widgets/task_checkbox.dart:25 | Toggle persisted task completion/status | both | no | test/today_page_test.dart | pending | pending |
| U0-TODAY-09 | Today/journal | Journal day/note row | lib/widgets/journal_feed.dart:188 | Open journal note/day | both | no | test/journal_feed_test.dart | pending | pending |

| U0-NOTES-01 | Notes list | Journal navigation | lib/app_mobile.dart:4329 | Open Journal surface | both | no | none | pending | pending |
| U0-NOTES-02 | Notes list | Note row | lib/widgets/work_surface.dart:372 | Open note | both | no | none | pending | pending |
| U0-NOTES-03 | Notes list | New note | lib/widgets/work_surface.dart:337 | Create and open a note | both | no | test/widget_test.dart | pending | pending |
| U0-NOTES-04 | Notes list | New entity | lib/widgets/work_surface.dart:344 | Create and open an entity | both | no | test/entity_page_test.dart | pending | pending |
| U0-NOTES-05 | Notes list | New-page title Cancel | lib/app_mobile.dart:1068 | Close new-page dialog without writing | both | no | none | pending | pending |
| U0-NOTES-06 | Notes list | New-page title Create | lib/app_mobile.dart:1072 | Create page after title/template selection | both | no | none | pending | pending |
| U0-NOTES-07 | Notes list | Template Blank note | lib/app_mobile.dart:1042 | Create without a template | both | no | none | pending | pending |
| U0-NOTES-08 | Notes list | Template entry | lib/app_mobile.dart:1047 | Create from selected template | both | no | none | pending | pending |

| U0-EDITOR-01 | Editor | View-mode menu → Edit / edit_outlined | lib/app_mobile.dart:4484 | Select normal rich editor mode; check when current | both | no | test/widget_test.dart | pending | pending |
| U0-EDITOR-02 | Editor | View-mode menu → Read / chrome_reader_mode_outlined | lib/app_mobile.dart:4484 | Open reading mode; check when current | both | no | test/widget_test.dart | pending | pending |
| U0-EDITOR-03 | Editor | View-mode menu → Preview / preview_outlined | lib/app_mobile.dart:4484 | Open continuous screen-wide Typst preview; check when current | both | no | test/widget_test.dart | pending | pending |
| U0-EDITOR-04 | Editor | View-mode menu → Source / code | lib/app_mobile.dart:4484 | Open source editor; check when current | both | no | test/widget_test.dart | pending | pending |
| U0-EDITOR-05 | Editor | Undo | lib/rich_editor/editor_widgets.dart:637 | Undo latest edit | both | no | test/virtual_plain_editor_test.dart | pending | pending |
| U0-EDITOR-06 | Editor | Redo | lib/rich_editor/editor_widgets.dart:644 | Redo latest edit | both | no | test/virtual_plain_editor_test.dart | pending | pending |
| U0-EDITOR-07 | Editor | Heading 1 | lib/rich_editor/editor_widgets.dart:651 | Apply H1 | both | no | test/rich_editor_test.dart | pending | pending |
| U0-EDITOR-08 | Editor | Heading 2/3/4 menu | lib/rich_editor/editor_widgets.dart:492 | Apply selected heading level | both | no | none | pending | pending |
| U0-EDITOR-09 | Editor | Bold | lib/rich_editor/editor_widgets.dart:692 | Toggle bold | both | no | test/rich_editor_test.dart | pending | pending |
| U0-EDITOR-10 | Editor | Italic | lib/rich_editor/editor_widgets.dart:692 | Toggle italic | both | no | test/rich_editor_test.dart | pending | pending |
| U0-EDITOR-11 | Editor | Strikethrough | lib/rich_editor/editor_widgets.dart:692 | Toggle strike | both | no | none | pending | pending |
| U0-EDITOR-12 | Editor | Underline | lib/rich_editor/editor_widgets.dart:692 | Toggle underline | both | no | none | pending | pending |
| U0-EDITOR-13 | Editor | Monospace | lib/rich_editor/editor_widgets.dart:692 | Toggle monospace | both | no | none | pending | pending |
| U0-EDITOR-14 | Editor | Highlight | lib/rich_editor/editor_widgets.dart:697 | Toggle highlight | both | no | test/rich_editor_test.dart | pending | pending |
| U0-EDITOR-15 | Editor | Highlight colors menu | lib/rich_editor/editor_widgets.dart:508 | Select highlight fill (also reachable from Magic) | both | no | none | pending | pending |
| U0-EDITOR-16 | Editor | Bulleted list | lib/rich_editor/editor_widgets.dart:722 | Toggle bullets | both | no | none | pending | pending |
| U0-EDITOR-17 | Editor | Numbered list | lib/rich_editor/editor_widgets.dart:722 | Toggle numbering | both | no | none | pending | pending |
| U0-EDITOR-18 | Editor | Clear formatting | lib/rich_editor/editor_widgets.dart:722 | Remove inline/block formatting | both | no | none | pending | pending |
| U0-EDITOR-19 | Editor | Insert | lib/rich_editor/editor_widgets.dart:727 | Open insert/magic action flow | both | no | none | pending | pending |
| U0-EDITOR-20 | Editor | Magic | lib/app_mobile.dart:4310 | Open explicit magic actions | both | no | none | pending | pending |
| U0-EDITOR-21 | Editor | Magic action grid | lib/app_mobile.dart:3500 | Apply bold/italic/heading/strike/underline/mono/list/highlight/equation/table/date/citation/attachment/report | both | no | none | pending | pending |
| U0-EDITOR-22 | Editor | Heading keyboard menu | lib/rich_editor/editor_widgets.dart:655 | Long-press opens heading levels | both | no (tap route added 2026-09-26) | test/rich_editor_test.dart (heading level menu test, via tap) | pending | pending |
| U0-EDITOR-27 | Editor | More heading levels | lib/rich_editor/editor_widgets.dart:660 | Tap to open heading levels menu | both | no | test/rich_editor_test.dart | pending | pending |
| U0-EDITOR-23 | Editor | Editor key handler: arrows/Enter/Escape | lib/rich_editor/editor_widgets.dart:116 | Navigate/accept/dismiss autocomplete | both | no | test/editor_autocomplete_test.dart | pending | pending |
| U0-EDITOR-24 | Editor | Editor key handler: Z | lib/rich_editor/editor_widgets.dart:149 | Undo keyboard shortcut | both | no | none | pending | pending |
| U0-EDITOR-25 | Editor | Protected block Cancel | lib/app_mobile.dart:818 | Close protected-block editor | both | no | none | pending | pending |
| U0-EDITOR-26 | Editor | Protected block Apply | lib/app_mobile.dart:822 | Replace protected Typst block | both | no | none | pending | pending |

| U0-TASKS-01 | Tasks | Task row | lib/widgets/work_surface.dart:240 | Open task source note | both | no | test/agenda_filter_test.dart | pending | pending |
| U0-TASKS-02 | Tasks | Open source note | lib/widgets/work_surface.dart:243 | Open task source note | both | no | none | pending | pending |
| U0-TASKS-03 | Tasks | Task checkbox | lib/widgets/task_checkbox.dart:25 | Toggle task status in persisted note | both | no | test/today_page_test.dart | pending | pending |
| U0-TASKS-04 | Tasks | Task status/property control | lib/app_mobile.dart:1620 | Set task status and refresh rendered state | both | no | none | pending | pending |

| U0-LIBRARY-01 | Articles/library | Library navigation | lib/app_mobile.dart:4334 | Open Library surface | both | no | test/articles_shelf_test.dart | pending | pending |
| U0-LIBRARY-02 | Articles/library | Search articles | lib/widgets/work_surface.dart:578 | Filter article list by text/tag | both | no | none | pending | pending |
| U0-LIBRARY-03 | Articles/library | Clear search | lib/widgets/work_surface.dart:689 | Clear article query | both | no | none | pending | pending |
| U0-LIBRARY-04 | Articles/library | Sort menu | lib/widgets/work_surface.dart:701 | Sort by supported article sort option | both | no | none | pending | pending |
| U0-LIBRARY-05 | Articles/library | Grouping menu | lib/widgets/work_surface.dart:715 | Group by supported grouping option | both | no | none | pending | pending |
| U0-LIBRARY-06 | Articles/library | Status chips | lib/widgets/work_surface.dart:639 | Filter unread/reading/read/extracted/cited/all | both | no | none | pending | pending |
| U0-LIBRARY-07 | Articles/library | Relevance chips | lib/widgets/work_surface.dart:664 | Filter any/high/medium/low relevance | both | no | none | pending | pending |
| U0-LIBRARY-08 | Articles/library | Import Markdown articles | lib/widgets/work_surface.dart:785 | Import selected Markdown files | both | no | integration_test/markdown_import_native_test.dart | pending | pending |
| U0-LIBRARY-09 | Articles/library | Continue reading card | lib/widgets/work_surface.dart:795 | Reopen unfinished article | both | no | none | pending | pending |
| U0-LIBRARY-10 | Articles/library | Article row | lib/widgets/work_surface.dart:850 | Open article in reader | both | no | none | pending | pending |
| U0-LIBRARY-11 | Articles/library | Article delete gesture | lib/widgets/work_surface.dart:851 | Delete article after confirmation (also exposed by More) | both | no | none | pending | pending |
| U0-LIBRARY-12 | Articles/library | Article status chip | lib/widgets/work_surface.dart:880 | Persist article reading status | both | no | none | pending | pending |
| U0-LIBRARY-13 | Articles/library | Article relevance chip | lib/widgets/work_surface.dart:890 | Persist article relevance | both | no | none | pending | pending |
| U0-LIBRARY-14 | Articles/library | More → Delete article | lib/widgets/work_surface.dart:897 | Delete article after confirmation | both | no | none | pending | pending |

| U0-SEARCH-01 | Search + filters | Search navigation | lib/app_mobile.dart:4338 | Open search/knowledge surface | both | no | test/knowledge_screen_test.dart | pending | pending |
| U0-SEARCH-02 | Search + filters | Knowledge sections menu | lib/knowledge_screen.dart:272 | Switch Search/Problems | both | no | test/knowledge_screen_test.dart | pending | pending |
| U0-SEARCH-03 | Search + filters | Search field | lib/knowledge_screen.dart:300 | Search notes, tasks, attachments and citations | both | no | test/knowledge_screen_test.dart | pending | pending |
| U0-SEARCH-04 | Search + filters | Saved-search ChoiceChip | lib/knowledge_screen.dart:336 | Apply saved query/tag/status | both | no | test/saved_searches_test.dart | pending | pending |
| U0-SEARCH-05 | Search + filters | Saved-search delete | lib/knowledge_screen.dart:337 | Confirm and delete saved view (chip delete icon or long-press) | both | no (tap route added 2026-09-26) | test/widget_test.dart (saved search deletes from its chip without long-press) | pending | pending |
| U0-SEARCH-06 | Search + filters | Save search | lib/knowledge_screen.dart:404 | Persist current query and filters as a saved view | both | no | test/saved_searches_test.dart | pending | pending |
| U0-SEARCH-07 | Search + filters | Tag suggestion chip | lib/knowledge_screen.dart:473 | Apply tag filter | both | no | none | pending | pending |
| U0-SEARCH-08 | Search + filters | Selected-tag delete | lib/knowledge_screen.dart:490 | Clear tag filter and rerun search | both | no | none | pending | pending |
| U0-SEARCH-09 | Search + filters | Citation result | lib/knowledge_screen.dart:514 | Open cited PDF/note result | both | no | test/knowledge_screen_test.dart | pending | pending |
| U0-SEARCH-10 | Search + filters | Search result row | lib/knowledge_screen.dart:543 | Open note/task/project/article result | both | no | test/knowledge_screen_test.dart | pending | pending |

| U0-SAVED-01 | Saved views | Saved-search selection | lib/knowledge_screen.dart:375 | Activate/deselect saved query and filters | both | no | test/saved_searches_test.dart | pending | pending |
| U0-SAVED-02 | Saved views | Save-dialog Cancel | lib/knowledge_screen.dart:420 | Leave saved-view dialog unchanged | both | no | none | pending | pending |
| U0-SAVED-03 | Saved views | Save-dialog Save | lib/knowledge_screen.dart:424 | Create/update saved view | both | no | test/saved_searches_test.dart | pending | pending |
| U0-SAVED-04 | Saved views | Delete-dialog Cancel | lib/knowledge_screen.dart:345 | Preserve saved view | both | no | none | pending | pending |
| U0-SAVED-05 | Saved views | Delete-dialog Delete | lib/knowledge_screen.dart:350 | Delete saved view | both | no | none | pending | pending |

| U0-PDF-01 | PDF reader | Save highlight | lib/pdf/pdf_reader_screen.dart:283 | Persist selected PDF quote annotation | both | no | integration_test/pdf_reader_native_test.dart | pending | pending |
| U0-PDF-02 | PDF reader | Highlights drawer | lib/pdf/pdf_reader_screen.dart:294 | Open saved highlights | both | no | integration_test/pdf_reader_native_test.dart | pending | pending |
| U0-PDF-03 | PDF reader | Highlight row | lib/pdf/pdf_reader_screen.dart:332 | Navigate to exact highlight or review it | both | no | integration_test/pdf_reader_native_test.dart | pending | pending |
| U0-PDF-04 | PDF reader | Select replacement | lib/pdf/pdf_reader_screen.dart:261 | Reassign ambiguous/missing highlight | both | no | none | pending | pending |
| U0-PDF-05 | PDF reader | Review Close | lib/pdf/pdf_reader_screen.dart:270 | Dismiss highlight review | both | no | none | pending | pending |
| U0-PDF-06 | PDF reader | Reassignment Cancel | lib/pdf/pdf_reader_screen.dart:359 | Exit replacement-selection mode | both | no | none | pending | pending |

| U0-GRAPH-01 | Graph | Graph view menu | lib/app_mobile.dart:4250 | Open graph view selector | both | no | test/graph_test.dart | pending | pending |
| U0-GRAPH-02 | Graph | Concept map | lib/app_mobile.dart:4263 | Show concept map | both | no | test/graph_test.dart | pending | pending |
| U0-GRAPH-03 | Graph | Focused | lib/app_mobile.dart:4264 | Show focused graph | both | no | test/graph_test.dart | pending | pending |
| U0-GRAPH-04 | Graph | All files | lib/app_mobile.dart:4265 | Show whole-vault graph | both | no | test/graph_test.dart | pending | pending |
| U0-GRAPH-05 | Graph | Timeline | lib/app_mobile.dart:4266 | Show timeline graph | both | no | test/graph_test.dart | pending | pending |
| U0-GRAPH-06 | Graph | Voronoi | lib/app_mobile.dart:4267 | Show Voronoi graph | both | no | test/voronoi_view_test.dart | pending | pending |
| U0-GRAPH-07 | Graph | Graph node/cell tap | lib/voronoi_view.dart:291 | Open note/concept node | both | no | test/voronoi_view_test.dart | pending | pending |
| U0-GRAPH-08 | Graph | Fit map | lib/voronoi_view.dart:309 | Refit graph viewport | both | no | none | pending | pending |
| U0-GRAPH-09 | Graph | Export/share SVG | lib/app_mobile.dart:3310 | Generate and share graph SVG | both | no | integration_test/graph_share_native_test.dart | pending | pending |

| U0-MORE-01 | More/settings | More navigation | lib/app_mobile.dart:4342 | Open More sheet | both | no | none | pending | pending |
| U0-MORE-02 | More/settings | Vaults | lib/app_mobile.dart:3604 | Open vault manager | both | no | test/vault_registry_test.dart | pending | pending |
| U0-MORE-03 | More/settings | Settings | lib/app_mobile.dart:3604 | Open settings sheet | both | no | none | pending | pending |
| U0-MORE-04 | More/settings | New page | lib/app_mobile.dart:3604 | Start page creation | both | no | none | pending | pending |
| U0-MORE-05 | More/settings | Graph | lib/app_mobile.dart:3604 | Open graph | both | no | none | pending | pending |
| U0-MORE-06 | More/settings | Split editor | lib/app_mobile.dart:3604 | Open split editor | both | no | none | pending | pending |
| U0-MORE-07 | More/settings | Context | lib/app_mobile.dart:3604 | Open backlinks/context dialog | both | no | none | pending | pending |
| U0-MORE-08 | More/settings | Share as PDF | lib/app_mobile.dart:3604 | Render/share current note as PDF | both | no | integration_test/share_pdf_native_test.dart | pending | pending |
| U0-MORE-09 | More/settings | Problems | lib/app_mobile.dart:3604 | Open problems view | both | no | test/knowledge_screen_test.dart | pending | pending |
| U0-MORE-10 | More/settings | Rebuild index | lib/app_mobile.dart:3604 | Rebuild vault index | both | no | test/rebuild_twice_test.dart | pending | pending |
| U0-MORE-11 | More/settings | Relink vault | lib/app_mobile.dart:3604 | Relink vault references | both | no | test/relink_strip_test.dart | pending | pending |
| U0-MORE-12 | More/settings | Typst help | lib/app_mobile.dart:3604 | Show Typst help | both | no | none | pending | pending |
| U0-MORE-13 | More/settings | Appearance Auto/Light/Dark | lib/widgets/settings_sheet.dart:218 | Change theme mode | both | no | none | pending | pending |
| U0-MORE-14 | More/settings | Vaults settings tile | lib/widgets/settings_sheet.dart:77 | Open vault manager | both | no | none | pending | pending |
| U0-MORE-15 | More/settings | Sync settings tile | lib/widgets/settings_sheet.dart:83 | Configure sync | both | no | none | pending | pending |
| U0-MORE-16 | More/settings | Task reminders | lib/widgets/settings_sheet.dart:89 | Enable reminders | both | no | none | pending | pending |
| U0-MORE-17 | More/settings | Migrate entity types | lib/widgets/settings_sheet.dart:95 | Migrate older notes | both | no | none | pending | pending |
| U0-MORE-18 | More/settings | Clean up imported notes | lib/widgets/settings_sheet.dart:101 | Remove import noise | both | no | none | pending | pending |
| U0-MORE-19 | More/settings | Import Logseq/Obsidian vault | lib/widgets/settings_sheet.dart:107 | Import whole vault | both | no | integration_test/markdown_import_native_test.dart | pending | pending |
| U0-MORE-20 | More/settings | Check for updates | lib/widgets/settings_sheet.dart:117 | Check/download desktop update | mac | no | test/desktop_updater_test.dart | pending | pending |
| U0-MORE-21 | More/settings | PDF page size / picture_as_pdf_outlined | lib/widgets/settings_sheet.dart:80 | Persist A4 (default), Letter, A5 or Legal for note/report PDF export | both | no | test/preview_theme_test.dart | pending | pending |

| U0-VAULT-01 | Sync/vault dialogs | Add or create vault | lib/widgets/vaults_sheet.dart:79 | Add/select a vault | both | no | test/vault_registry_test.dart | pending | pending |
| U0-VAULT-02 | Sync/vault dialogs | Switch vault row | lib/widgets/vaults_sheet.dart:44 | Make vault active | both | no | none | pending | pending |
| U0-VAULT-03 | Sync/vault dialogs | Disconnect (keep files) | lib/widgets/vaults_sheet.dart:59 | Forget configured vault, retain files | both | no | none | pending | pending |
| U0-VAULT-04 | Sync/vault dialogs | Delete permanently | lib/widgets/vaults_sheet.dart:64 | Delete vault after confirmation | both | no | none | pending | pending |
| U0-SYNC-01 | Sync/vault dialogs | Sync status button | lib/app_mobile.dart:4292 | Open sync dashboard | both | no | test/sync_dashboard_test.dart | pending | pending |
| U0-SYNC-02 | Sync/vault dialogs | Configure Nextcloud | lib/widgets/sync_dashboard.dart:249 | Open Nextcloud configuration | both | no | test/nextcloud_sync_test.dart | pending | pending |
| U0-SYNC-03 | Sync/vault dialogs | Check folder | lib/app_mobile.dart:1729 | Validate remote folder and continue | both | no | integration_test/nextcloud_sync_native_test.dart | pending | pending |
| U0-SYNC-04 | Sync/vault dialogs | Sync conflict local/remote choice | lib/widgets/sync_dashboard.dart:185 | Choose conflict resolution source | both | no | test/conflict_choice_test.dart | pending | pending |
| U0-SYNC-05 | Sync/vault dialogs | Resolve conflict | lib/app_mobile.dart:2617 | Save selected/merged resolution | both | no | none | pending | pending |
| U0-SYNC-06 | Sync/vault dialogs | Cancel conflict | lib/app_mobile.dart:2516 | Leave conflict unchanged | both | no | none | pending | pending |
| U0-SYNC-07 | Sync/vault dialogs | Copy diagnostics | lib/widgets/sync_dashboard.dart:483 | Copy sync trace/status | both | no | test/sync_dashboard_test.dart | pending | pending |
| U0-SYNC-08 | Sync/vault dialogs | Explain error | lib/app_mobile.dart:3845 | Show sync error explanation | both | no | none | pending | pending |

| U0-EXPORT-01 | Export/report | Share current note as PDF | lib/app_mobile.dart:3604 | Export/render note PDF and share | both | no | integration_test/share_pdf_native_test.dart | pending | pending |
| U0-EXPORT-02 | Export/report | Create report via Magic | lib/app_mobile.dart:3500 | Create filtered Typst report and PDF, then share | both | no | test/report_test.dart | pending | pending |
| U0-EXPORT-03 | Export/report | Report title Apply | lib/app_mobile.dart:1070 | Accept report title | both | no | test/report_test.dart | pending | pending |
| U0-EXPORT-04 | Export/report | Report title Cancel | lib/app_mobile.dart:1066 | Cancel report creation | both | no | none | pending | pending |
| U0-EXPORT-05 | Export/report | Date-range picker | lib/app_mobile.dart:3153 | Choose optional report date range | both | no | none | pending | pending |
| U0-EXPORT-06 | Export/report | Table-size Cancel/Insert | lib/app_mobile.dart:3153 | Cancel or insert validated table | both | no | none | pending | pending |

## Counts

| Surface | Count |
|---|---:|
| Today/journal | 9 |
| Notes list | 8 |
| Editor | 27 |
| Tasks | 4 |
| Articles/library | 14 |
| Search + filters | 10 |
| Saved views | 5 |
| PDF reader | 6 |
| Graph | 9 |
| More/settings | 21 |
| Sync/vault dialogs | 12 |
| Export/report | 6 |
| **Total** | **131** |

## Long-press-only actions

None remain; U0-EDITOR-22 retains long-press as an additional route, and
U0-SEARCH-05 retains long-press as an additional route.

## Controls with no existing test

The controls with no existing test are:

`U0-TODAY-02`, `U0-TODAY-03`, `U0-TODAY-04`, `U0-TODAY-05`, `U0-TODAY-07`,
`U0-NOTES-02`, `U0-NOTES-05`, `U0-NOTES-06`, `U0-NOTES-07`, `U0-NOTES-08`,
`U0-EDITOR-08`, `U0-EDITOR-11`, `U0-EDITOR-12`, `U0-EDITOR-13`,
`U0-EDITOR-15`, `U0-EDITOR-16`, `U0-EDITOR-17`, `U0-EDITOR-18`,
`U0-EDITOR-19`, `U0-EDITOR-20`, `U0-EDITOR-21`,
`U0-EDITOR-24`, `U0-EDITOR-25`, `U0-EDITOR-26`, `U0-TASKS-02`, `U0-TASKS-04`,
`U0-LIBRARY-02`, `U0-LIBRARY-03`, `U0-LIBRARY-04`, `U0-LIBRARY-05`,
`U0-LIBRARY-06`, `U0-LIBRARY-07`, `U0-LIBRARY-09`, `U0-LIBRARY-10`,
`U0-LIBRARY-11`, `U0-LIBRARY-12`, `U0-LIBRARY-13`, `U0-LIBRARY-14`,
`U0-SEARCH-03`, `U0-SEARCH-07`, `U0-SEARCH-08`,
`U0-SAVED-02`, `U0-SAVED-04`, `U0-SAVED-05`, `U0-PDF-04`, `U0-PDF-05`,
`U0-PDF-06`, `U0-GRAPH-08`, `U0-MORE-01`, `U0-MORE-03`, `U0-MORE-04`,
`U0-MORE-05`, `U0-MORE-06`, `U0-MORE-07`, `U0-MORE-09`, `U0-MORE-12`,
`U0-MORE-13`, `U0-MORE-14`, `U0-MORE-15`, `U0-MORE-16`, `U0-MORE-17`,
`U0-MORE-18`, `U0-VAULT-02`, `U0-VAULT-03`, `U0-VAULT-04`, `U0-SYNC-05`,
`U0-SYNC-06`, `U0-SYNC-08`, `U0-EXPORT-04`, `U0-EXPORT-05`, `U0-EXPORT-06`.

No build or test command was run for this inventory; Mac and A24 columns
therefore remain `pending`.
