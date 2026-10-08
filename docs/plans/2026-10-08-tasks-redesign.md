# Tasks redesign: a task is a line you type

## Outcome

All five phases shipped in 0.11.9 and 0.12.0. Doing runs the timer; the four
statuses remain Todo, Doing, Done and Cancelled. The task format did not change.

Quick add takes text literally and does not parse dates. The local Studio model
was dropped as implementer after failing both tasks it was given; Codex
implemented the redesign. Phone-keyboard verification is still open.

The original plan below is retained as written, including its proposed
implementation assignments and quick-add parsing.

## Context
Tasks feel bolted on. The storage is complete (`#tylog.task(...)` holds status, priority, scheduled, due, repeat, clocked sessions), but while writing you can only tick a box.

- **Creating** a task takes a menu, a text dialog and a date picker (`lib/app_mobile.dart:3395`). `/todo`, `TODO ` and `[ ]` do nothing.
- **Changing** doing/cancelled, priority, dates or repeat means editing Typst source by hand.
- **The editor line** shows only `☐ text`; all other fields are invisible.
- **Lists disagree:** Today and Tasks have a checkbox and timer; Journal, Calendar and Search rows are read-only.

Target: the file-based Logseq flow (`/todo`, `/doing`, `/done`, `/a`, typed date popup, Ctrl+Enter, clock runs while Doing) on the existing storage. No format change, no new window or sheet.

Decided with the user:
- Doing runs the timer; leaving Doing stops it.
- Statuses stay at four: todo, doing, done, cancelled.

## One primitive, three consumers
Everything below goes through the same two pieces, so the editor and every list behave identically.

- **`setTaskFields(source, id, {status, priority, scheduled, due, recurrence})`** in `packages/tylog_core/lib/src/scanner.dart`, extending the existing surgical writer (~1582–1878), which today only allows status/completed/text/properties.
- **`applyTaskStatus(source, id, next, now)`**, the single status transition:
  - records an occurrence for repeating tasks instead of ending them;
  - starts the clock on entering Doing (`startTaskClock`) and stops it on leaving (`stopTaskClock`);
  - keeps the one-running-clock-per-vault rule: the previously running task goes back to Todo.
- The editor checkbox (`lib/rich_editor/editing_controller.dart:759`) and the list handler (`lib/app_mobile.dart:1888`) both call it. This removes the two paths that disagree on repeats today.

## Phase 1: core
- The two functions above, with tests that compile the written Typst (`writer_compiles_test.dart` pattern).
- **Date words parser** `parseDateWords(text, now)` in `tylog_core`, a small table-driven parser, no new dependency:
  - today / tomorrow / weekday names / `+3d` / `in 2 weeks` / `15 oct` / `15.10` / ISO, with an optional `14:30`;
  - English, Russian and Portuguese word tables;
  - returns candidates for a suggestion list, not one guess.

## Phase 2: typing a task
In `lib/rich_editor/document_model.dart`, `editing_controller.dart`, `lib/editor_autocomplete.dart`:

- **Create without a dialog:** `TODO `, `[] ` or `[ ] ` at the start of a line, or `/todo` (alias `/task`), turns the current line into a task. The id comes from `vault.nextTaskId` after the fact. The text dialog and date picker are deleted from the single-task path; the multi-line convert stays.
- **Enter** on a task line starts the next task; Enter on an empty task line returns to a paragraph.
- **Backspace** at the checkbox still demotes, but as one undo step that restores the full original source, metadata included.
- **Commands on a task line**, through the existing `/` popup:
  - `/todo` `/doing` `/done` `/cancel`;
  - `/a` `/b` `/c` (high, normal, low) and `/urgent`;
  - `/due` and `/scheduled` (alias `/deadline`);
  - `/repeat` (daily, weekly, monthly, weekdays).
- **Date popup:** `/due` keeps the popup open as a date field. Typing `fri` or `завтра` lists parsed dates live; Enter picks. A calendar icon in the popup opens the grid picker as fallback.
- **Ctrl/Cmd+Enter** cycles todo → doing → done.
- **Checkbox:** tap toggles done; long-press opens a four-item status menu anchored to the line.

## Phase 3: the line shows its state
In `lib/rich_editor/editor_widgets.dart` (~1530):

- **Status glyph:** ☐ todo, ◐ doing, ☑ done, ☒ cancelled (cancelled text struck through).
- **Trailing strip:** priority, due/scheduled date, repeat mark and time spent are painted beside the block, outside the editable text, so the round-trip check is untouched. Tapping a chip opens the same inline popup as the matching command.
- Reload the block when only metadata changed; today the reload compares visible text only (`lib/app_mobile.dart:622`).

## Phase 4: one row everywhere
- **`TaskRow`** widget (new, in `lib/widgets/task_row.dart`), built from the row in `lib/widgets/work_surface.dart:109`: same glyph, long-press status menu, chips and time spent.
- Used by Today, Tasks tab, Journal (`journal_feed.dart:263`), Calendar (`calendar_tab.dart:89`), Search and saved queries (`knowledge_screen.dart:553`).
- The play/stop button is removed from rows; the floating running pill (`lib/widgets/task_clock.dart`) stays and its stop sets the task back to Todo.
- **Filters** (`lib/widgets/task_agenda.dart:88`): "All" shows everything, including cancelled and older done tasks.
- **Quick add** on Today and Tasks: one text field using the same parser, appending to today's journal page.

## Phase 5: cleanup
- The Typst-help Task chip inserts a fresh id instead of the fixed `task-id` (`lib/app_mobile.dart:2463`).
- Update `docs/research-tylog-features.md` and `CHANGELOG.md`.
- Not in this plan: converting imported `☐` checklists into tasks; a session-history view; Backlog / In review statuses.

## Execution
Claude tokens are spent only on dispatching and reading verdict lines.

- **Unsloth Studio writes all code.** Each phase is cut into single-file tasks and run through `~/.claude/skills/pi-delegate/scripts/pi-run.sh` with the Studio provider (`desktop-vdsrh2e:8888`, Qwen3-Coder-30B), `PI_VERIFY` set to the phase's targeted test and `PI_MAX_ITERS=3` so it retries on its own failures.
- **Codex CLI is the reviewer and fallback.** After each phase, one `codex exec` run reviews the diff against this plan, runs `flutter analyze` and the full suites, fixes what Studio got wrong, and prints a verdict of at most ten lines. If Studio fails a task three times, codex implements that task.
- **Claude** writes the task prompts once (graphify and ponytail rules included), launches the runs in the background, and reads only each verdict's tail. No diff reading by Claude unless codex reports a failure it cannot fix.
- **Order:** core functions first, since Studio is weakest on the surgical Typst writers; those get compile tests written by codex before Studio starts.
- Phases 1–2 ship as one release, 3–4 as the next, so the typing flow reaches the phone first.

## Verification
- `flutter analyze` clean (infos fail CI); `flutter test` and `packages/tylog_core` tests pass.
- New tests:
  - each trigger and command produces source that compiles and round-trips;
  - Doing starts and stops the clock, and a second Doing demotes the first;
  - a repeating task ticked in the editor records an occurrence;
  - Backspace-demote then undo restores the metadata;
  - parser table for three languages;
  - one `TaskRow` test covering every surface's callbacks.
- On the P30 with the real vault (`adb install -r`, never clearing data): type `TODO call bank`, `/due fri`, `/a`, Ctrl+Enter on a hardware keyboard, long-press the checkbox, and confirm the same task reads identically in Today, Journal and Calendar. Check typing with the phone keyboard specifically, since late keyboard updates have reverted edits before.
