# Visual design

Tefteri ("notebook" in Greek) should feel like a well-kept paper planner, not
like default Material. This page is the design brief. All styling lives in
`frontend/lib/theme/`; change the look there, not in screens.

## Direction

- **Mood:** calm, warm, focused.
- **Reference:** a ruled notebook with a bookmark ribbon, set with editorial
  type; the density of a good calendar app.
- **Signature elements:** serif headings, the red margin line and ruled lines
  on task rows, a tinted block with a strong colored left edge for each
  calendar item, the notebook-and-ribbon mark, and a tab-like navigation rail.

## Palette

Written by hand in `theme/palette.dart` (not grown from a seed color).

| Role | Light ("paper") | Dark ("midnight ink") |
| --- | --- | --- |
| Background | warm cream | deep blue-black |
| Primary, events | ink blue | pale ink blue |
| Tasks | terracotta | soft terracotta |
| Done | sage | pale sage |
| Now marker | vermilion | coral |

Colors without a Material role (rules, margin line, event and task tints,
weekend and today tint, the now marker) are in the `TefteriColors` theme
extension; read them with `context.tefteri`. The app follows the system
light or dark setting.

## Type

- **Instrument Serif** for titles and section headings (single weight, so
  never ask for bold).
- **IBM Plex Sans** for everything else, with tabular figures so times and
  counts line up.

Both are bundled in `frontend/assets/fonts/` (SIL Open Font License, texts
next to the fonts), so the app and the documentation screenshots look the
same on every machine.

## Shape and motion

- Small, crisp radii (`Corner`), hairline outlines instead of shadows, flat
  surfaces. Pills only for chips.
- Spacing scale `Space` (4, 8, 12, 16, 24, 32).
- Motion is short (150 to 240 ms) and is skipped when the user asks for
  reduced motion (`Motion.of`). Pages fade in with a small rise.

## Work categories

The three work categories have one style each, in `features/statistics/category_style.dart`
(`CategoryStyle`, `categoryStyle`). Each style uses theme colors only. The style never relies on
color alone, so a greyscale picture still tells the three apart.

| Category | Look | Mark |
| --- | --- | --- |
| Goal-aligned | A filled block in the primary color | Check |
| Maintenance | A muted fill with a diagonal hatch | Repeat |
| Off-plan | An open block with a 2 px outline in the task color | Compass |

Each count tile, bar segment and badge uses the same style, and prints the name and the number.
The hidden line is a quiet outlined line with a crossed eye.

## Navigation

From 960 dp wide the views are a permanent left rail: icons with labels
below, or from 1180 dp icons, labels and shortcut keys. Narrower windows use a
drawer behind a menu button, as before. The current view is marked with a
filled background and a bar on its left edge.

## Rules for new screens

1. Take colors from `Theme.of(context).colorScheme` or `context.tefteri`,
   sizes from `Space` and `Corner`, text from `Theme.of(context).textTheme`.
   A test (`test/theme/design_rules_test.dart`) fails on `Color(0x...)`,
   `Colors.*` (except `transparent`) and font names in `lib/features` and
   `lib/core`.
2. Use `EmptyState` and `Loading` for empty and loading states.
3. Do not bring back seeded color schemes, the default font, stock `AppBar`
   or elevated cards.
4. Run `just docs::screenshots`, look at the images in light and at least one
   narrow size, and fix anything that looks generic or cramped.
