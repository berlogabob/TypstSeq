# macOS verify P1 (2026-11-03, release build, scratch vault via CFFIXED_USER_HOME)

Works: entity page (Project label, Board button, Part of / Contains), kanban columns, drag todo->done writes `status: "done"` surgically, Library kind chips, List/Tree toggle, tree UE > IADE > Game Lab, UE > UNIDCOM.

Findings:
1. **@fixit issue card missing on the TyLog board.** `_index/index.json` (gzip) contains the issue (`projectId: tylog, marker: fixit`), but the board shows only tasks. The index reaching the UI loses `issues` somewhere (worker isolate -> app transfer, paged/partial index, VaultIndex copy/merge that drops the field, or EntityBoard reading another index). Unit tests build VaultIndex by hand, so they miss it. Add a test through the real path (scan -> publish -> controller.index.issues).
2. **Empty kanban column only accepts drops on a 16 px strip** under the header (`board-<col>-0`). A drop anywhere in the column must work (whole column = DragTarget; position = end).
3. **Entity page body shows 1 of 2 tasks:** notes/TyLog.typ has t1 todo + t2 doing (separated by a blank line); only "Kanban board" rendered. Check whether doing tasks are hidden or the second task call is dropped (pre-existing or P1?). Compare with base build behaviour by reasoning; fix if a bug.
4. **Part of / Contains section is centered**; must be left-aligned like the rest of the entity page.
5. **Kanban card subtitle "normal"** (default priority) is noise; show priority only when not normal, plus due date if any.

## Round 2 (rebuild after fixes)
Confirmed fixed: #1 issue card shows (bug icon chip), #2 drop into empty column area works (status metadata written surgically), #4 left-aligned, #5 no "normal".

New / still open:
6. **Issue card shows raw Typst source** (`- 14:50 #tylog.ref-note("tylog")[TyLog] #tylog.ref-note("fixit")[fixit] search jumps to today`). Show readable text: drop list marker and leading time, ref-note -> its title (or drop project + marker refs since they are implied), drop the status metadata. Reuse the existing plain-text/excerpt helper used by linked references if one exists.
7. **Rich editor renders the status metadata as a link chip "tylog-issue-status"** in the daily note. Render `#metadata(("tylog-issue-status": X))` as a small non-link status chip (todo/doing/done icon) or hide it; editing the line must round-trip byte-exact (see memory: toSource round-trip revert).
8. **Linked references excerpt shows raw `#metadata(("tylog-issue-status": "done"))`**: strip it in excerpts.
9. **#3 still: entity page body hides the doing task** (notes/TyLog.typ: t1 + t2 status doing, blank line between). The board shows t2 in DOING, so the index has it; the page body/editor does not render it. Look at rich editor / task rendering for `status: "doing"` (running clock UI?) and fix.
10. **Test `worker publishes newly scanned issues to the controller` times out** (`_waitUntil` condition never met) although the real app now shows issues. Fix the test (or the publish path if the test reveals a real gap, e.g. only the cold path publishes).

## Round 3
Confirmed fixed: #6 (not rechecked visually on board), #7 metadata no longer shown in daily line, #8 excerpt clean.
- **#9 root cause found by Claude on device:** the note body on an entity page is a fixed-height inner scroll area with no visible scrollbar; the 2nd task is scrolled out of view (scrolling inside the body reveals "Part of chips"). Not a parser/status problem. Fix: on entity pages the body must size to its content inside the page's single scroll (no nested scrollable), or at minimum show a scrollbar. Check whether this predates P1 (Part of/Contains sections added below the body in Task D).
- **#10 still fails in the full suite** (`worker publishes newly scanned issues to the controller`, `_waitUntil` timeout) though it passed for codex in isolation: likely order-dependent (shared static state such as kindRegistry, a leaked controller/worker, or timing). Make it deterministic.
