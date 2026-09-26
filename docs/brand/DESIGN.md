# Brainmerge design guide

Everything visible in Brainmerge derives from one file, `Packages/BrainmergeUI/Sources/BrainmergeUI/Design/Theme.swift`. Change a token there and the whole app follows. This page is the human-readable version of those tokens, for contributors and for anyone who wants to retheme the app.

## Principles

1. **A dark, quiet canvas.** Near-black with a faint purple cast at the top left. No halos, no decoration: nothing competes with the accounts.
2. **Cream text, three levels.** Full, muted (64%), faint (50%): every level reads at 4.5:1 or better on the canvas. Serif for titles (the system serif), sans for everything else.
3. **One accent.** The purple of the creature, and only it, for actions: switches, segmented controls, the selected item in the sidebar, progress dots. A sidebar row under the pointer gets a neutral cream fill, fainter than the selection, so the purple keeps meaning "selected". Primary buttons are filled with its deep shade (`Colors.button`), so their white label reads at 4.7:1. Secondary actions are glass buttons.
4. **Glass surfaces, native controls.** Cards, sidebar and chips use the system glass (`glassEffect`) with a thin rim; primary actions are the system's prominent glass button tinted with the accent, secondary actions plain glass. Corner radius 12 for cards, 14 for the sidebar, 10 for its rows, capsules for chips. A sidebar row is clickable across its whole width.
5. **Flat account colors.** Each account has a muted tint (or a photo) on a flat circle with its initial. No gloss, no glow.
6. **Motion with a purpose.** The creature is a pixel sprite and moves like one: at rest it is exactly its grid, and its eyes, arms, legs and breath change in whole cells or whole pixels. In the sidebar it only blinks and glances, walks while an account opens, waves when it is open, hops with a few sparkles when the memory saves a note, and startles at an error; these reactions play even while the window is in the background, where its idle holds still. At launch its pixels gather into one, then it leaps into the sidebar while the window appears, along a path that never crosses words or rows: when the rows reach low it rises straight up before it swings home, and caught in the middle of its hop with no clear way from the air it lands first. The splash never keeps a ready app waiting past 0.48 s, and the screens come in under the leap; only a window too full for any clear path keeps them back until the creature is home. On a first run it lands on the welcome creature and the words come in after it. At the end of the setup it waits beside Open Brainmerge and leaps home from there, higher for the longer way, while the main window, built under the last page, comes in. How it works shows three account windows and one folder on this Mac: a note saved by one reaches the others. An opening account gets a stroke in its own color, and its dot pops sage with one ring once it is open; the cards never move or swap places. Words that change give way before the new ones come in, and a page of the setup fades where it is before the next one slides in: two texts are never printed over each other. What changes on its own never pops: data and results rise into place, a new row drops in and keeps the selection color for a moment, a problem said twice shakes, work that runs shows a small spinner, and the memory graph blooms from its projects on its first read, fades what a hover leaves out and glides when zoomed. Keyboard paths and the sidebar's hover and press stay instant or take 0.12 s. With Reduce Motion nothing moves: colors and opacity change in 0.15 s, and every scene shows its still. Captures show the same stills. The menu bar icon never moves.

## Tokens

| Token | Value | Used for |
| --- | --- | --- |
| `Colors.background` | `#1A1918` | window canvas |
| `Colors.backgroundTop` | `#2B2633` | top-left of the radial gradient |
| `Colors.backgroundBottom` | `#151417` | bottom of the gradient |
| `Colors.text` | `#F4EFE6` | text, 100% |
| `Colors.textMuted` | text at 64% | secondary text |
| `Colors.textFaint` | text at 50% | labels, hints |
| `Colors.surfaceLine` | white at 12% | dividers |
| `Colors.field` | white at 7% | text fields on glass |
| `Colors.accent` | `#A06BE0` | the one accent |
| `Colors.accentLight` / `accentDeep` | `#B487EA` / `#8657C9` | inline notices (and the "Only here" mark of an account's MCP servers, the small mark before a failed save's line on a card and the Memory screen, the dot of a Health finding that is an error; a warning's dot is `textFaint`) / the fill of prominent buttons |
| `Colors.button` | `accentDeep` | prominent buttons (4.7:1 with `onAccent`) |
| `Colors.selection` | accent at 18% | the selected sidebar row, the flat shadow under the creature (launch, How it works), a new timeline row for 1.6 s |
| `Colors.rowHover` | text at 6% | a sidebar row under the pointer (neutral, fainter than `selection`) |
| `Colors.rowPressed` | text at 10% | a sidebar row while it is pressed |
| `Colors.accentSoft` | accent at 35% | the older bars of the usage chart |
| `Colors.onAccent` | `#FBF7FF` | text on the accent |
| `Colors.meter` | text at 42% | the RAM bars of the Usage screen that are not an account's (the Mac, terminal sessions, other apps); an account's bar takes its tint (its share of RAM, and each limit "Check limits" shows), every bar sits on a `field` track |
| `Colors.sage` | `#8FC7A6` | "open" dots, "saved" states, Health's "Everything is in place." |
| `Colors.vaultBackground` | `#262626` | an Obsidian vault's graph, flat like Obsidian's canvas (Minimal theme, dark) |
| `Colors.vaultNode` / `vaultLine` / `vaultText` | `#999999` / `#3F3F3F` / `#D1D1D1` | a vault's nodes without a color group, its lines (one pixel, opaque), its labels |
| `Colors.vaultHighlight` / `vaultFocused` | `#750F0F` / `#8C1212` | the hovered node and its lines / the ring around it (the two shades Minimal draws from the accent `#8B1212`) |
| `Colors.vaultAttachment` / `vaultUnresolved` | `#E0DE71` / `#666666` | attachments and links to no file, when the vault shows them |
| `Theme.color(group:)` | the vault's own | a vault's color groups, from the rgb integers of its `graph.json` |
| `Colors.creature` / `creatureEye` | `#A06BE0` / `#1E1430` | the creature |
| `Diagram.windowGlass` / `windowLight` | white at 5.5% / 16% | How it works: an account window's pane over the canvas, its three title-bar lights |
| `Diagram.pageFold` / `pageLine` / `noteLine` / `folderEdge` | black at 25% / white at 75% / black at 18% / white at 14% | How it works: a note page's folded corner and written lines, the lines on the notes in the folder, the light along the folder's front |
| `Motion.out(d)` / `inOut(d)` | `cubic-bezier(0.23, 1, 0.32, 1)` / `cubic-bezier(0.77, 0, 0.175, 1)` | entering, exiting and feedback / moving on screen (the site's `--ease-out` and `--ease-move`) |
| `Motion.hover` / `quick` / `base` / `page` / `ring` | 0.12 / 0.15 / 0.22 / 0.32 / 1.2 s | hover and press / small changes / most changes / a page / a ring |
| `Motion.pop` / `settle` / `hop` | springs 0.35, 0.6 / 0.4, 0.88 / 0.28, 0.55 | a dot or swatch that pops / layout that settles / a hop |
| `Motion.reduced` / `unlessReduced(_:_:)` | 0.15 s linear | every change with Reduce Motion: opacity and color only (`unlessReduced` picks it in place of an animation of a color or an opacity) |
| `Motion.layout(_:_:)` / `.fade(_:)` | none with Reduce Motion | what moves or resizes the layout (a grid, a sheet's height, a spinner before a sentence): with Reduce Motion the layout changes at once and what appears fades in place in 0.15 s (`.fade` carries its own animation) |
| `Motion.isCapture` / `slow` | `BRAINMERGE_CAPTURE` / `BRAINMERGE_SLOW_MOTION` (debug builds) | captures show each scene's still / every token and scene slowed down to feel-check it |
| `Launch.unit` / `lift` | 7 / 20 | one pixel of the creature on the launch splash, in points / how far its body's middle sits above the window's middle |
| `Launch.frameDuration` | 0.12 s | one frame of the four-frame walk while a slow launch loads |
| `Launch.minimumVisible` | 0.48 s | the earliest hand-off, the load's own time included: the app never waits longer for the splash |
| `Launch.fade` / `reducedFade` | 0.30 s / 0.15 s | the screens fading in under the leap (from 0.04 s before it takes off: 0.04 s into the hand-off, later when a click cut the gather short) / the dissolve that replaces the whole launch with Reduce Motion |
| `Launch.slowCaptionAfter` | 2.0 s | when "Waking up…" appears on a slow launch |
| `Launch.leap` / `leapApex` / `anticipation` | 0.50 s / 12 pt / 0.08 s | the leap into the sidebar (and out of the guided setup): takeoff to touchdown / its apex above the higher end / the crouch before it. The guide's long way home rises a fifth of the way across (less a quarter of its fall, 12 pt at least) and takes 0.6 s past 250 pt |
| `Launch.gatherSpread` / `heroTime` | 2.4 / 1.46 s | how far from the body's center the exploded pixels start / the still for the README header, the site and store images |
| `Layout.padding` / `cardRadius` | 20 / 12 | screen padding, card corners |
| `Layout.rowRadius` | 10 | sidebar rows: their selection, hover and press fills |
| `Layout.readingWidth` / `formWidth` | 880 / 720 | the widest a Memory or Usage card gets / the settings form |
| `Layout.meterRadius` | 3 | the thin RAM and limit bars of the Usage screen |
| `Layout.panelRadius` | 16 | the quick opener's glass panel |

The menu bar icon (`Design/MenuBarIcon.swift`) is the creature drawn from the same grid as a template image: macOS paints it in the menu bar's own color, so it carries no token. Cells are 1.5 pt on a Retina display (1 pt at 1x, to stay on whole pixels) in a 24 by 18 pt canvas, so the creature is 16.5 pt tall; its eyes are cut out, open while an account is open or opening, a thin line one row lower otherwise. No badge, no count, no animation. The accounts in its menu carry a 10 pt dot in their tint (`Theme.color(for:)`).

Account tints (`Theme.hex(for:)`): orange `#D97757`, blue `#6FA3D8`, green `#7FA37A`, purple `#A87BC9`, pink `#D97A8E`, yellow `#E0A526`, gray `#7D8A99`. Red maps to pink and is not offered in pickers. Gray also marks what no account wrote: your own edits ("You") and authors outside Brainmerge, in the timeline and the graph.

State changes (`Design/StateMotion.swift`, each a pure function of the time since it happened, so a screen opened later draws its end and a capture its still):

| Change | Values |
| --- | --- |
| An account opening (`OpeningStroke`) | a 2.5 pt arc in its tint around the card, inside its glass, a third of the way round lit, one turn per 1.6 s, with the same stroke blurred 4 pt at 60%; in 0.18 s, out 0.25 s. Captures and Reduce Motion: still at 35 degrees, 60% with Reduce Motion |
| Words that change (`SwapText`) | the old words lift 3 pt away in 0.10 s, the new ones settle in over 0.16 s from 0.06 s: never two above a quarter. The card's button keeps one width for all its words |
| Opened (`PopIn`, `RingPulse.opened`) | the dot from 0.4 of its size on `Motion.pop`, one sage ring 6 to 18 pt in 0.5 s; a card added rings its orb (40 to 52 pt) in its tint |
| Arriving (`Arrival`) | data and results rise 8 pt in 0.24 s (Usage cards 50 ms apart, chart bars from a 2 pt baseline, 15 ms apart); lines and problems drop 4 pt in 0.18 s; timeline rows drop 6 pt in 0.24 s |
| A problem said again (`Shake`) | x 0, -4, 4, -3, 0 over 0.3 s; with Reduce Motion an opacity blink 1, 0.4, 1 |
| Busy (`WorkingLine`) | a small spinner before the sentence, in and out in 0.15 s, never inside a disabled button |
| The memory graph (`GraphBloom`, `CameraTween`, `GraphPulse`) | first read: notes out of their hub in 0.65 s, 30 ms per link away (240 ms at most); hover: a quarter of the way per frame, to 28%; zoom 0.2 s, Fit 0.35 s; a pulse rings r+3 to r+20 in 1.2 s (twice and a pop when an account saved it), its halo 2.6 s |

## Type

| Role | Font |
| --- | --- |
| Screen title | system serif, 26, medium |
| Onboarding title | system serif, 30, medium |
| Sheet title | system serif, 22, medium |
| Card name | system sans, 13, semibold |
| Figure (usage numbers) | system sans, 22, semibold |
| Body | system sans, 14 |
| Secondary | system sans, 12.5 |
| Section label | system sans, 11.5, semibold, uppercase |
| Caption | system sans, 11 |
| Quick opener field | system sans, 18 |

Every screen starts with `ScreenHeader`: the serif title, an optional subtitle capped at 560 points, and the screen's actions on the right, aligned with the title line. The default font of the window is `Fonts.body`, so an unstyled text never falls back to the system size.

The Memory screen switches between three tabs with one segmented control: Graph, Timeline and Tidy, whose name carries its count ("Tidy (4)", no number when there is nothing to tidy). Tidy's rows sit in glass cards under section labels, one per group: a sentence, a quiet second line (`textMuted`), and at most one glass button (File under…, Hide, Compare or Open).

The quick opener is a 560 point panel over whatever app is in front, dark whatever that app is: regular glass tinted with `background` at 55%, `panelRadius` corners, no shadow of its own and no animation beyond the system's panel appearance (none with Reduce Motion). A search field in `Fonts.search`, a `surfaceLine` divider, then rows of 44 points: a 28 point orb (the photo or the tint), the name in `cardName`, the note in `secondary` `textMuted`, and the sidebar's word in `caption` on the right (`textFaint` when it does nothing). The picked row takes `selection` with `rowRadius` corners. A `caption` line at the bottom names the keys. No button at all: the keys and a click on a row are the actions.

## Retheming

Fork, edit `Theme.swift`, run `swift test --package-path Packages/BrainmergeUI` (the theme tests pin the accent and the sobriety thresholds; adjust them with your values), rebuild. The creature lives in a single file, `Design/CreatureView.swift` (its walk is computed from its grid, so a new grid walks too), and the app icon and brand assets are generated by `scripts/make-brand.swift` from the same tokens.
