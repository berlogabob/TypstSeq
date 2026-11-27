# TyLog design system

One page for anyone adding or changing UI. Tokens live in
`lib/widgets/constants.dart`, icons in `lib/widgets/app_icons.dart`, components
in `lib/widgets/ds/`. Import everything with `widgets/ds/ds.dart`.

`test/design_tokens_test.dart` scans every file under `lib/` and fails when a
rule below is broken: spacing, radii, icon sizes, type sizes, motion, palette
colours, `AppIcons` glyphs, sheets, snackbars, dialog buttons, surface messages,
spinners, and that every component here is exported and documented.
`test/contrast_test.dart` checks colour contrast: 4.5:1 for every text colour
(including the error red) on the app, dialog and sheet surfaces, and 3:1 for
graphics. `test/ds_components_test.dart`
covers the components and their states.

Decisions behind these rules: `docs/plans/2026-10-14-design-system-and-menus.md`.

## Tokens

| Scale | Tokens | Rule |
|---|---|---|
| Colour | `tyLogColorScheme(brightness)`, `warningColor(scheme)`, `kOnImage`, `kImageGradientScrim`, `kImageControlScrim`, `kSearchRevealFill` | Use `ColorScheme` roles. No `Colors.*` except `transparent`, `black`, `white` for compositing. Data palettes (graph edges, highlights) stay next to their data. |
| Type | Material `textTheme` | No `fontSize:` literals. Body text `bodyLarge`, rows `bodyMedium`, secondary `bodySmall`, pills `labelMedium`, section headers `titleSmall`, sheet titles `titleLarge`. |
| Spacing | `kSpace4`, `kSpace8`, `kSpace12`, `kSpace16`, `kSpace24`, `kEditorInset` (18) | A padding, gap or `spacing:` equal to a token value must use the token. Other values are allowed only for optical or structural offsets (an indent that lines up with an icon, canvas margins). |
| Radius | `kRadiusSmall` (6), `kRadiusMedium` (12), `kRadiusLarge` (20), `kRadiusListTile` | Chips and cells small; rows, cards, buttons, inputs medium; dialogs and sheets large. |
| Icon size | `kIconInline` (16), `kIconDense` (18), `kIconSmall` (20), `kIcon` (24), `kIconLarge` (48) | Inline in chips and badges; dense rows; compact controls; standard tiles; the focal icon of an empty or error state. |
| Target | `kMinTapTarget` (48) | Anything tappable hits at least 48dp, even if it draws smaller. |
| Motion | `kMotionDock` (150ms), `kMotionStatus` (200ms), `kMotionGraphZoom` (260ms) | Animation only. Debounce, autosave and network timeouts are behaviour and are named where they are used. |

Naming: every token starts with `k`. Scales picked by value are named by value
(`kSpace16`); scales picked by role are named by role (`kRadiusSmall`).

## Icons

One glyph per meaning, through `AppIcons` (`AppIcons.close`, `.delete`, `.edit`,
`.settings`, `.overflow`, `.warning`, `.sync`, ...). Note kinds become icons only
through `iconForKind(kind)`. A glyph `AppIcons` owns must not be used as
`Icons.*` anywhere else.

## Components

### `AppTile`
Row for settings pages, the More drawer and other padded containers.

| Property | Type | Default | Meaning |
|---|---|---|---|
| `icon` | `IconData` | required | Leading icon at `kIcon`. |
| `title` | `String` | required | |
| `subtitle` | `String?` | null | Up to two lines. |
| `trailing` | `Widget?` | null | Switch, chevron, menu. |
| `onTap` | `VoidCallback?` | null | Null makes it a read-only info row. |
| `enabled` | `bool` | true | False dims the row and ignores taps. |
| `selected` | `bool` | false | Marks the current choice. |
| `singleLineSubtitle` | `bool` | false | One ellipsised line, for paths. |

Use `AppTile` inside a container that supplies the 16dp gutter; it adds 8dp of
its own. Use a plain `ListTile` for edge-to-edge lists; the theme gives it the
16dp inset. Both end up on the same text column.

Accessibility: it is a `ListTile`, so it is announced as a button when tappable
and reports disabled and selected states.

### `AppSection`
Titled group of tiles. `title`, `children`, `divider` (default true; pass false
for the first section). The title is announced as a heading.

### `AppSheet` and `showAppSheet`
Every bottom sheet opens with `showAppSheet` and returns an `AppSheet`.

| Property | Type | Meaning |
|---|---|---|
| `title` | `String` | `titleLarge`, announced as a heading. |
| `subtitle` | `String?` | Context under the title, two lines at most. |
| `trailing` | `Widget?` | Action on the title row, such as Skip. |
| `children` | `List<Widget>` | Default constructor; scrolls when tall. |
| `AppSheet.body(child:)` | `Widget` | A child that scrolls or flexes itself. |

`showAppSheet` options: `isScrollControlled` (text fields, tall sheets),
`isDismissible`, `enableDrag`, `constraints`, and `bare` for the one sheet that
paints its own draggable surface (Incoming).

The sheet supplies the 16dp gutter and gives `ListTile`s inside it no inset of
their own, so row text lines up with the title. Content inside a sheet adds no
horizontal padding.

Do not call `showModalBottomSheet` directly, and do not open a sheet without a
title.

### `AppEmptyState`
For a tab, page or pane with nothing to show: `icon`, `title`, `hint`, optional
`primaryAction` and `secondaryAction`, and `loading` while the index builds.
The icon is `kIconLarge`, so the block has a focal point; the loading spinner
sits in a box of the same height, so the title does not move when it ends.

`AppEmptyState.error(title:, hint:, details:, primaryAction:)` is the same
surface when loading failed: warning icon in the error colour, a hint in plain
words that says what to try, and a Retry action where one exists. Put the raw
exception in `details`: it shows behind a "Details" button as selectable text,
never as the hint. The title is a live region, so screen readers announce it.

| State | Use |
|---|---|
| Empty | Nothing to list yet, or no match for the filter. |
| Loading | `loading: true` while the index builds; hint and actions hide. |
| Error | `AppEmptyState.error` when reading failed. |

An empty section inside a longer list (a kanban column, a group in a list)
stays a one-line row, so the list does not jump when the section fills. A
`Center(child: Text(...))` is never used for either.

Write the title as what is missing ("No recordings yet") and the hint as what
fills it ("Record or import audio to get started.").

### `AppSearchField`
The one search field: outlined, dense, a search icon in front and a clear
button once there is text. Used by `LibraryToolbar`, the Search tab, Settings
and every search inside a sheet.

| Property | Type | Default | Meaning |
|---|---|---|---|
| `hintText` | `String` | required | What can be searched ("Filter notes"). |
| `onChanged` | `ValueChanged<String>` | required | Also called with `''` when cleared. |
| `controller` | `TextEditingController?` | null | Pass it when the caller sets or reads the text. |
| `fieldKey` | `Key?` | null | Keys the inner `TextField` for tests. |
| `autofocus` | `bool` | false | |

It adds no padding; inside an `AppSheet` it lines up with the title.

### `LibraryToolbar` and `LibraryFilterChip`
`AppSearchField`, optional trailing sort and group buttons, and one scrolling
chip row. Same on every Library tab.

### Choice lists in sheets
A sheet that picks one of several options ("Which text?") marks the current one:
`selected: true` and a trailing `Icons.check`. Row labels do not repeat what the
sheet title already says (`#travel` · "Add to this day", not "Add tag "travel"
to this day"). Recently used items go under a `titleSmall` label in the primary
colour ("Recent").

### `showSnack`
`showSnack(context, message, action:, duration:)` is the only way to show a
snackbar. Pass `duration` only when the user must act elsewhere before it goes.

### `showConfirmDialog`
Every yes/no question. Dismiss is "Cancel" on the left; the primary is a filled
button named after the action. `destructive: true` colours it as an error.
`confirmKey` keys the primary button for tests.

Dialogs that collect input (a name field, a picker) build their own
`AlertDialog` and follow the same rules:

| Rule | Example |
|---|---|
| "Cancel" is the first action | `Cancel` · `Save` |
| The primary is a `FilledButton` named after what it does | `Rename`, `Add`, `Select replacement` |
| At most two actions; a third choice goes in the body as a text button | Installed module: `Uninstall` (red, in the body) · `Cancel` · `Update` |
| A destructive secondary is a `TextButton` in the error colour | Timer: `Discard` · `Stop and keep` |
| An informational dialog has one `Close` button; the end of a multi-step flow may say `Done` | |
| Never "OK", "Yes" or "No"; labels say what happens | `Stop and keep`, not `Stop now` |

The one dialog with three actions is the article merge (`Keep existing` ·
`Use imported` · `Save manual merge`): a three-way decision in a full-width
dialog. The guard allows it by name.

"Later" and "Back to setup" are kept where the meaning is not cancel.

### `LoadingIndicator`
The only spinner. `size: kIconSmall` and `strokeWidth: 2` in rows and buttons;
no size when it fills a pane.

## Adding something new

1. Look for an existing component first.
2. Build it from tokens; add a token only for a value used in three or more
   places.
3. Put it in `lib/widgets/ds/`, export it from `ds.dart`, give it a doc comment
   that says when to use it and when not to, and add a test.
4. Add a section here.
