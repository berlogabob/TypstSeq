# TyLog UI Fix Plan — traceable, measurable

**Source:** `tylog-ui-design-critique.md` (repo audit, 2026-08-18).
**Traceability model:** every audit finding has an ID (F-xx). Every work item (WP-xx) lists the findings it closes, the exact files it touches, a measurable acceptance criterion, and the command or test that proves it. A finding is *closed* only when its verification passes in `make verify`.

**Definition of done (whole plan):** all metrics in §4 hit target, all new tests pass in CI, and re-running the audit greps in §5 returns zero hits.

---

## 1. Finding register

| ID | Finding (from critique) | Severity | Evidence |
|----|--------------------------|----------|----------|
| F-01 | Task row tap toggles done in Library ▸ Tasks, opens note in Today | 🔴 | `work_surface.dart:232-234` vs `121-124` |
| F-02 | Article delete only via undiscoverable long-press | 🟡 | `work_surface.dart:797` |
| F-03 | Status-string confirmations mostly never render | 🟡 | `app_mobile.dart:731, 826, 843, 3609-3633` |
| F-04 | "Shit" rating silently routes to deletion; stars give no press feedback | 🟡 | `app_mobile.dart:2065-2067`, `reading_mode.dart:149-156` |
| F-05 | Seed color duplicated ×3; reading night theme hand-built | 🟡 | `app_mobile.dart:160,168`, `reading_mode.dart:224` |
| F-06 | Metadata dialog borderless vs New-entity dialog outlined fields | 🟡 | `app_mobile.dart:938-965` vs `2448-2481` |
| F-07 | Note icon: `Icons.notes` vs `Icons.description_outlined`; entity icon `alternate_email` vs `iconForKind` | 🟡 | `work_surface.dart:372-374,414`, `constants.dart:20` |
| F-08 | `Colors.amber` warning icon, 1.56:1 contrast | 🔴 (a11y) | `knowledge_screen.dart:522` |
| F-09 | Light-mode graph edges 2.56:1 / 2.33:1 (< 3:1 non-text minimum) | 🟡 | `graph.dart:1328-1332` |
| F-10 | `PropertySelectChip` ~26 px tall (< 48 dp), two per article row | 🔴 (a11y) | `property_select_chip.dart:92` |
| F-11 | `_VoronoiPainter` has no `semanticsBuilder` — view invisible to screen readers | 🔴 (a11y) | `voronoi_view.dart:315-460` |
| F-12 | Timeline "read" edges have no legend entry / toggle | 🟢 | `graph.dart:1326,1365-1392` |
| F-13 | Seven ad-hoc corner radii; no radius scale | 🟢 | audit sweep |
| F-14 | Highlight colors reachable only via long-press | 🟢 | `editor_widgets.dart:656-662` |
| F-15 | "Tasks" headline inside tab while sibling tabs have none | 🟢 | `work_surface.dart:200-203` |
| F-16 | "More" sheet mixes daily actions with maintenance | 🟢 | `app_mobile.dart:3138-3150` |
| F-17 | Today: agenda/reading region can squeeze editor to 40 % | 🟢 | `work_surface.dart:83-84` |

---

## 2. Work packages

### M1 — Behavior correctness (target: 1 evening)

**WP-01 · Unify task-row tap semantics** — closes **F-01**
Files: `lib/widgets/work_surface.dart`
Change: `_PrimaryTasksView` row `onTap` → `onOpenPath(task.notePath)`; status changes only via `TaskCheckbox`. Drop the now-redundant trailing `open_in_new` button (row tap does it) or keep it for parity with Today — pick one and apply to *both* lists.
**Acceptance (measurable):**
- Widget test `task_row_tap_opens_note_test.dart`: tapping the row body in both Today agenda and Library ▸ Tasks calls `onOpenPath` exactly once and `onSetStatus` zero times. Tapping the checkbox calls `onSetStatus` exactly once.
- Grep guard: `grep -n "onSetStatus" lib/widgets/work_surface.dart` shows it wired only to `TaskCheckbox.onChanged` (0 occurrences inside a `ListTile.onTap`).

**WP-02 · Visible article delete affordance** — closes **F-02**
Files: `lib/widgets/work_surface.dart`
Change: add a `PopupMenuButton` (⋮) to `_ArticlesShelf._row` trailing with "Delete article…" (error-styled); keep long-press as shortcut.
**Acceptance:**
- Widget test: overflow menu contains a delete item; selecting it invokes `onDeleteArticle` once.
- Manual check on device: delete reachable with zero long-presses.

**WP-03 · One feedback channel per message class** — closes **F-03**
Files: `lib/app_mobile.dart` (+ callers of `status =`)
Change: introduce `_notify(String msg)` → `showSnack`; convert user-facing confirmations (`Opened…`, `Created…`, `Deleted…`, `Task reminders enabled`, `Couldn't open…`) to `_notify`. Reserve the `status` field for open-failure banner + progress pill only.
**Acceptance:**
- Count metric: `grep -cE "status = '(Opened|Created|Deleted)" lib/app_mobile.dart` — baseline **5+**, target **0**.
- Widget test: after `_openNote`, a `SnackBar` with `Opened` appears (or, if you decide open needs no toast at all, the test asserts *no* orphaned status write — decide in the WP, then the test pins it).

**WP-04 · Honest rating sheet** — closes **F-04**
Files: `lib/widgets/reading_mode.dart`
Change: rename "Shit" row to `Discard article…` with `Icons.delete_outline` + error color, separated by a `Divider`; stars fill on selection (`Icons.star` for hovered/selected index) before popping.
**Acceptance:**
- Widget test: rating sheet shows exactly 5 star buttons + 1 discard action; discard action text contains "Discard" and uses `colorScheme.error`.
- Existing delete-confirm dialog still appears (test: choosing discard → `showConfirmDialog` invoked).

### M2 — Token layer & consistency (target: 1–2 evenings)

**WP-05 · Create the design-token layer** — closes **F-05, F-13**, enables F-06–F-09
Files: `lib/widgets/constants.dart` (grow into `lib/widgets/tokens.dart` if preferred), `lib/app_mobile.dart`, `lib/widgets/reading_mode.dart`
Change: add
```dart
const kSeedColor = Color(0xFF0B2F44);
ColorScheme lightScheme() / darkScheme();          // single builders
const kRadiusSmall = 6.0; kRadiusMedium = 12.0; kRadiusLarge = 20.0;
Color warningColor(ColorScheme s);                  // replaces Colors.amber
```
Reading night mode consumes `darkScheme()` instead of re-seeding.
**Acceptance:**
- `grep -rn "0xFF0B2F44" lib/ | wc -l` — baseline **3**, target **1** (tokens file only).
- `grep -rn "Colors\.amber" lib/ | wc -l` — baseline **1**, target **0**.
- Distinct `BorderRadius.circular(N)` literals in `lib/widgets/`: baseline **7**, target **≤3** (all referencing the k-constants). Verify: `grep -rhoE "circular\(([0-9.]+)\)" lib/widgets lib/app_mobile.dart | sort -u`.

**WP-06 · Dialog field style unification** — closes **F-06**
Files: `lib/app_mobile.dart`
Change: shared `Widget dialogTextField({...})` (outlined, spacing baked in) used by Edit-metadata, New-entity, New-page, Nextcloud, table-size dialogs.
**Acceptance:**
- Zero `TextField(` constructions inside `showDialog` builders in `app_mobile.dart` that don't go through the helper: `grep -c "dialogTextField(" lib/app_mobile.dart` ≥ **14** (current per-dialog field count) and raw `OutlineInputBorder()` literals in that file drop from **8+** to **0**.

**WP-07 · One icon per concept** — closes **F-07**
Files: `lib/widgets/work_surface.dart`, `lib/app_mobile.dart`, `lib/widgets/constants.dart`
Change: route Library lists, `_chooseNote`, `_chooseEntity` through `iconForKind`; reserve `alternate_email` for email only.
**Acceptance:**
- `grep -rn "Icons.notes\b" lib/ | wc -l` → **0**.
- `grep -rn "Icons.alternate_email" lib/` → hits only where the value is an email (target **≤2**: entity-header property row, mailto chip icon fn).

### M3 — Accessibility gate (target: 1–2 evenings)

**WP-08 · Warning + graph edge contrast** — closes **F-08, F-09**
Files: `lib/knowledge_screen.dart`, `lib/graph.dart`
Change: warning icon → `warningColor(scheme)` (pick a value ≥ 3:1 on both surfaces, e.g. `#8C6D00`-family); darken light-mode edge palette until every edge ≥ 3:1 against `#F8FAFC`.
**Acceptance (scripted):** add `test/contrast_test.dart` — pure-Dart WCAG ratio function asserting: warning color ≥ **3.0** on light & dark surfaces; all 4 light-mode edge colors ≥ **3.0** on light surface; dark-mode edges ≥ 3.0 on dark surface. Baseline failures: **3** → target **0**. Runs in `make test` forever after.

**WP-09 · 48 dp select chips** — closes **F-10**
Files: `lib/widgets/property_select_chip.dart`
Change: wrap chip in `ConstrainedBox(constraints: BoxConstraints(minWidth: 48, minHeight: 48))` with the visual pill centered (visual size unchanged, hit area grown), or `materialTapTargetSize` equivalent.
**Acceptance:**
- Widget test: `tester.getSize(find.byType(PropertySelectChip))` height ≥ **48** and width ≥ **48**.
- Manual: Android "Show taps" — both chips in an article row tappable without zoom.

**WP-10 · Voronoi semantics** — closes **F-11**
Files: `lib/voronoi_view.dart`
Change: implement `semanticsBuilder` on `_VoronoiPainter` mirroring `GraphPainter` (`graph.dart:1285-1301`): one node per *currently closed* visible cell, label `"$label, $count notes"` (or note title for leaf cells), `button: true`, `onTap` → open/zoom.
**Acceptance:**
- Widget test with `SemanticsTester`: for a 3-community fixture, ≥ 3 semantic nodes with labels exist; activating a leaf-cell node calls `onOpenPath`.
- Metric: custom painters lacking semantics in `lib/`: baseline **1** → target **0**.

**WP-11 · Timeline legend completeness** — closes **F-12**
Files: `lib/graph.dart`
Change: add a `Read` `_LegendEntry`, shown when the graph is a timeline graph (or always, disabled otherwise).
**Acceptance:** widget test: timeline `GraphView` renders **4** `FilterChip`s; toggling "Read" removes read-edges from `visibleEdgeKinds`.

**WP-12 · Highlight colors without long-press** — closes **F-14**
Files: `lib/app_mobile.dart` (magic menu), `lib/rich_editor/*`
Change: add the 4 highlight colors as options under the Magic ▸ highlight action (or a submenu on the `/highlight` command).
**Acceptance:** widget test: highlight colors reachable via a tap-only path (magic sheet → color choice → `setHighlight` called with the chosen fill).

### M4 — Polish (optional, batch when touching the files anyway)

**WP-13 · Drop "Tasks" headline** (F-15) — acceptance: no `headlineMedium` text inside Library tab bodies; visual parity across tabs.
**WP-14 · Section the More sheet** (F-16) — acceptance: sheet shows a "Maintenance" divider label before Rebuild/Relink (widget test asserts ordering).
**WP-15 · Today editor priority** (F-17) — decide product intent first (capture-first vs review-first). If capture-first: agenda collapses to a count chip when ≤ N items; acceptance: with 0 due tasks and 0 recents, editor gets ≥ **80 %** of viewport height in a widget test.

---

## 3. Sequencing & dependencies

```
M1: WP-01 → WP-02 → WP-04 → WP-03        (independent of tokens)
M2: WP-05 ⇒ (WP-06, WP-07, WP-08)        (tokens first)
M3: WP-08 → WP-09 → WP-10 → WP-11 → WP-12
M4: anytime, piggyback on file touches
```
Only hard dependency: **WP-05 before WP-06/07/08** (they consume the tokens).

---

## 4. Metrics dashboard (baseline → target)

| Metric | How measured | Baseline | Target | Closed by |
|--------|--------------|----------|--------|-----------|
| Task-list tap inconsistencies | widget tests (WP-01) | 1 | 0 | WP-01 |
| Destructive actions without visible affordance | manual sweep + tests | 2 (article long-press, "Shit") | 0 | WP-02, WP-04 |
| User-facing `status =` writes with no render path | grep (WP-03) | ≥5 | 0 | WP-03 |
| `0xFF0B2F44` occurrences | `grep -c` | 3 | 1 | WP-05 |
| `Colors.amber` / raw palette colors outside token+edge files | `grep -c` | 1 | 0 | WP-05/08 |
| Distinct radius literals in widgets | grep sort -u | 7 | ≤3 | WP-05 |
| Dialog text fields bypassing shared style | grep | 14+ | 0 | WP-06 |
| Icon-per-concept violations (notes/entity) | grep | 4+ | 0 | WP-07 |
| WCAG non-text contrast failures (<3:1) | `test/contrast_test.dart` | 3 | 0 | WP-08 |
| Interactive controls < 48 dp | widget size tests | ≥2/row | 0 | WP-09 |
| CustomPainters without semantics | code review + test | 1 | 0 | WP-10 |
| Edge kinds without legend entry | widget test | 1 | 0 | WP-11 |
| Features reachable only by long-press | sweep | 2 | 0 | WP-12 (+WP-02) |
| New regression tests added | CI count | 0 | ≥9 | all |

---

## 5. Keeping it fixed (guardrails in `make verify`)

1. **`test/contrast_test.dart`** (WP-08) — permanent WCAG gate for every color the UI hardcodes; add new colors to its table as they appear.
2. **`test/design_tokens_test.dart`** — pure-Dart test that reads `lib/` sources and asserts: no `0xFF0B2F44` outside tokens; no `Colors.` palette references outside the allowlist; radius literals ∈ {kRadiusSmall/Medium/Large usage}. (String-scan tests are crude but cheap and CI-visible — same spirit as the audit greps.)
3. **Touch-target sweep test** — one parameterized widget test instantiating each small custom control (`PropertySelectChip`, legend chips, task checkbox row) and asserting ≥ 48 dp hit size.
4. Track progress in this file: check the box per WP and paste the metric command output next to it, so the plan doubles as the audit trail.

### Checklist — all implemented 2026-08-18, **unverified until `make verify` passes**
- [x] WP-01  - [x] WP-02  - [x] WP-03  - [x] WP-04
- [x] WP-05  - [x] WP-06  - [x] WP-07
- [x] WP-08  - [x] WP-09  - [x] WP-10  - [x] WP-11  - [x] WP-12
- [x] WP-13 (as WP-15 in status doc)  - [x] WP-14 (as WP-16)  - [x] WP-15 (as WP-17)

Measured results and residual risks: `docs/ui-fix-status.md`.
Cumulative diff: 21 files, +1138 / -345 lines, 12 new regression tests.
