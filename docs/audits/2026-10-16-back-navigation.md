# Back navigation audit — 2026-10-16

“Android back today” records the **pre-fix** behavior found in source and, for regressions, reproduced with widget tests. Verdict describes this patch. Top-level destinations use shell state; More is a sheet, and Search is a pushed route. A shell `PopScope` now unwinds transient views before returning non-Today destinations to Today. Today itself still bubbles back to the platform. Desktop rail destinations do not get top-level back arrows.

| Screen | How it is opened | Route or in-place state | Android back today | Visible back control | Verdict |
| --- | --- | --- | --- | --- | --- |
| Today | Bottom destination 0 / desktop rail | `primaryDestination = 0`, `mode = normal` | Leaves app at root | None at root | Keep root behavior |
| Journal | Bottom destination 1 / rail | `mode = journal` | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Notes | Bottom destination 2 / rail | `mode = library`, tab 0 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Articles | Library tab | Same shell, tab 1 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Screenshots | Library tab | Same shell, tab 2 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Tasks | Library tab / Today agenda “All tasks” | Same shell, tab 3 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Calendar | Library tab | Same shell, tab 4 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Library — Audio | Library tab | Same shell, tab 5 | Bubbles out of app | None → mobile arrow | Fixed: returns to Today |
| Search / knowledge search | Bottom destination 3 / rail | `MaterialPageRoute`, with loading Scaffold then `KnowledgeScreen` | Pops to the previous destination, possibly Library/Journal | Automatic AppBar arrow | Fixed: closing Search returns to Today |
| More | Bottom destination 4 / rail | Modal bottom sheet; does not select destination 4 | Dismisses sheet to its origin | Scrim / drag | Already correct |
| Vaults | More → Vaults; Settings → Vaults | Modal bottom sheet (`VaultsSheet`) | Dismisses sheet | Scrim / drag | Already correct |
| Vault add / switch / forget / delete confirmations | Vaults actions | Platform picker and dialogs | Dialog/picker closes; switch replaces vault | Cancel / dialog actions | Already correct; reset shell history on vault open |
| Settings | More → Settings | Modal bottom sheet (`SettingsSheet`) | Dismisses sheet | Scrim / drag | Already correct |
| Theme and PDF paper | Settings → General | Inline controls in Settings sheet | Dismisses containing sheet | Sheet scrim / drag | No full-screen state switch |
| Calendars settings | Settings → Calendars | AlertDialog | Dismisses dialog to Settings | Cancel / Save | Already correct |
| Task reminders | Settings → Task reminders | Permission request / action; no app screen | Platform permission dismissal | Platform controls | No trapped app screen |
| Audio processing / AI connections | Settings → AI and processing | Inline settings; AI connection editor is a modal sheet | Dismisses top sheet | Scrim / drag | Already correct |
| Screenshot processing settings | Settings → AI and processing | Inline settings / time picker | Closes picker or Settings sheet | Picker Cancel / sheet scrim | Already correct |
| Sync setup | Settings → Sync → configure; cloud dashboard configure | `NextcloudConnectDialog` | Dismisses dialog | Cancel | Already correct |
| Problems / knowledge | Settings → Problems | Pushed `KnowledgeScreen(initialView: problems)` | Pops to origin | Automatic AppBar arrow | Already correct; keeps origin behavior |
| Knowledge sections / result filters | Search/Problems menu and filters | State inside the same routed screen | Pops the containing route | AppBar arrow | Not a separate full-screen view |
| Missing-target triage | Problems → repair | Pushed `TriageMissingPagesScreen` | Pops route | Automatic AppBar arrow | Already correct |
| Duplicate owners / graph-cluster note list | Problems or graph selection | Dialog for owners / pushed list for graph cluster | Closes dialog / pops route | Dialog dismissal / automatic AppBar arrow | Already correct |
| Rebuild index / relink / migrate / clean / import | Settings → Tools | Actions, confirmation/progress/result dialogs; platform file picker | Dismisses ordinary dialogs/pickers; operations continue as implemented | Cancel / Close where applicable | No separate state-switched screen |
| Modules / packs | Settings → Modules; empty list opens pack picker | Module sheet, file picker, install/update/uninstall confirmations and date picker | Dismisses sheet / picker / confirmation | Scrim, Cancel, date-picker controls | Already correct for interactive surfaces |
| Module mutation progress | Install / update / reschedule / uninstall pack | Non-dismissible dialog with `PopScope(canPop: false)` | Blocked while operation runs; closes in `finally` | Progress only | Intentional operation lock; retained (see limitations) |
| Moving vault progress | Vaults → move to app storage | Non-dismissible dialog with `PopScope(canPop: false)` | Blocked during copy; closes after operation | Progress only | Intentional operation lock; retained (see limitations) |
| Semantic model management | Settings → Semantic search | Modal sheet plus download-confirmation dialog | Dismisses top dialog / sheet | Cancel download / scrim | Already correct |
| Typst help / update prompts | Settings → About; compile errors | Dialogs, update progress dialog | Ordinary dialogs dismiss; existing updater progress policy unchanged | Close / Cancel / update actions | No state-switched full-screen screen |
| New page | More → New page; Library create | Title/template dialogs, then existing editor state | Dialogs close; created editor has no return path | Cancel in dialogs; editor none → arrow | Fixed editor origin restoration |
| New entity | More → New entity; Library create | Metadata dialog, then existing editor state | Dialog closes; created editor has no return path | Cancel in dialog; editor none → arrow | Fixed editor origin restoration |
| Context | More → Context | `showDialog` + `Dialog.fullscreen` + Scaffold | Dismisses dialog | Automatic AppBar arrow | Already correct; system-back safeguard added |
| Share as PDF | More → Share as PDF | Full-screen dialog for PDF selection, then platform share | Closes selection dialog / platform share | Explicit close control in dialog | Already correct; dialog exception applies |
| Graph | More → Graph | `mode = graph`, no route | Bubbles out of app | None → explicit arrow | Fixed: PopScope restores exact shell origin |
| Graph local/global mode and focus | Graph toolbar / node selection | Graph data/view options inside Graph | Still bubbles out before fix | Graph exit none → arrow | Graph exit restored; options are not new screens |
| Note editor from Today lists | Today references / task / idea links | `_openPath` → `_openNote`, `mode = normal` | Bubbles out of app | None → arrow | Fixed: returns to Today |
| Note editor from Journal | Journal row / day | Same shell editor state | Bubbles out of app | None → arrow | Fixed: returns to Journal, then Today |
| Note editor from Library lists | Notes, Articles, Screenshots, Tasks, Calendar | Same shell editor state | Bubbles out of app | None → arrow | Fixed: returns to Library with selected tab, then Today |
| Note editor from Search | Search result | Changes underlying shell while Search route remains above it | Pops Search; opening result is hidden behind Search | Search arrow only | Fixed: close Search to display editor; editor back reopens Search |
| AudioNoteScreen | Audio shelf, recording completion, inline audio/asset | Pushed `MaterialPageRoute` | Pops route | Automatic AppBar arrow | Already correct; system-back regression coverage added |
| Sync dashboard | Cloud icon / Settings → Sync | Pushed `MaterialPageRoute` | Pops route | Automatic AppBar arrow | Already correct; system-back regression coverage added |
| Read from editor | View mode → Read | Early `ReadingMode` return, its own PopScope | Returns to editor | Floating arrow → AppBar arrow | Existing back retained, integrated with origin history |
| Read from shelf / resume | Articles/Screenshots/continue-reading card | `_readPath`, `mode = read` | Returns to editor, losing shelf as immediate origin | Floating arrow → AppBar arrow | Fixed: returns directly to origin, preserving Library tab |
| Preview | Editor View mode → Preview | `mode = preview` | Bubbles out of app | None → arrow | Fixed: PopScope restores previous view |
| Source | Editor View mode → Source; Typst snippet insertion | `mode = source` | Bubbles out of app | None → arrow | Fixed: restores previous view and transfers edited source back to rich controller |
| Split view | Editor View mode → Split (`_ShellAction.split`); not currently a More tile | `mode = split` | Bubbles out of app | None → arrow | Fixed: PopScope restores previous view; preserves source edits |
| PDF reader | PDF attachment / citation | Pushed `PdfReaderScreen` | Pops route | Automatic AppBar arrow | Already correct |
| Image crop | Editor image toolbar | Pushed `ImageCropPage`, PopScope blocks only while busy | Pops unless encoding/saving | Text Cancel → arrow + Cancel | Visible arrow added; busy guard retained |

## Evidence and scope

Reviewed `lib/app_mobile.dart`, every `lib/app_mobile/*.dart` part, widget navigation surfaces under `lib/widgets/`, `lib/knowledge_screen.dart`, PDF/crop route implementations, and all `PopScope`, `WillPopScope`, `canPop`, `onPopInvoked*`, `BackButtonListener`, explicit leading suppression, and push sites under `lib/`. Existing graphify navigation query used for initial scoping. No WillPopScope or BackButtonListener implementation was found.

The shell keeps transient origin records (mode, destination, Library tab, and knowledge view when applicable). Destination selection and vault open/close clear stale history. Library reports tab selection for both taps and swipes. Source/Split back reloads the rich controller without discarding the shared source controller. Search reopening restores its screen/section, not the previous query text or scroll offset.

## Validation

- `flutter test test/mobile_navigation_creation_test.dart --no-pub` was attempted before the fix. The ordinary Flutter runner cannot create its localhost socket in this sandbox (`Operation not permitted`).
- A temporary runner outside the repository uses the installed test API, real `testWidgets` binding, compiled kernel, and `flutter_tester --disable-vm-service --flutter-assets-dir=build/unit_test_assets`. It executes the actual test file without a network socket.
- Against original HEAD source, independently selected regression tests fail for Journal/Library/Search → Today, Graph, Preview, Source, Split, Today/Journal/Library editors, shelf reading, and Search-result editor navigation. Context, Read-from-editor, Audio, Sync, More dismissal, and desktop coverage are safeguards for existing behavior, not claimed pre-fix failures.
- Final analyze/test results are recorded with the change report. No full test suite or device session is claimed.

## Limitations

Module mutation and vault-copy progress deliberately prevent dismissal until their operation finishes. Making these operations cancellable is separate from navigation and could interrupt storage writes; this patch preserves those existing guards. Crop similarly disables exit only during its bounded save operation. Real Android predictive-back gestures and macOS rail interactions still need device verification; widget tests simulate system back and the macOS target platform.
