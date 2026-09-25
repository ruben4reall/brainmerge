# Brainmerge design guide

Everything visible in Brainmerge derives from one file, `Packages/BrainmergeUI/Sources/BrainmergeUI/Design/Theme.swift`. Change a token there and the whole app follows. This page is the human-readable version of those tokens, for contributors and for anyone who wants to retheme the app.

## Principles

1. **A dark, quiet canvas.** Near-black with a faint purple cast at the top left. No halos, no decoration: nothing competes with the accounts.
2. **Cream text, three levels.** Full, muted (64%), faint (50%): every level reads at 4.5:1 or better on the canvas. Serif for titles (the system serif), sans for everything else.
3. **One accent.** The purple of the creature, and only it, for actions: switches, segmented controls, the selected item in the sidebar, progress dots. A sidebar row under the pointer gets a neutral cream fill, fainter than the selection, so the purple keeps meaning "selected". Primary buttons are filled with its deep shade (`Colors.button`), so their white label reads at 4.7:1. Secondary actions are glass buttons.
4. **Glass surfaces, native controls.** Cards, sidebar and chips use the system glass (`glassEffect`) with a thin rim; primary actions are the system's prominent glass button tinted with the accent, secondary actions plain glass. Corner radius 12 for cards, 14 for the sidebar, 10 for its rows, capsules for chips. A sidebar row is clickable across its whole width.
5. **Flat account colors.** Each account has a muted tint (or a photo) on a flat circle with its initial. No gloss, no glow.
6. **Motion with a purpose.** The aura appears only around an account that is opening. Reduce Motion freezes it. The creature is a pixel sprite and moves like one: at rest it is exactly its grid, and its eyes, arms, legs and breath change in whole cells or whole pixels. In the sidebar it only blinks and glances, walks while an account opens, waves when it is open, hops with a few sparkles when the memory saves a note (then glows for 4 s), and startles at an error; its timeline wakes only when its picture changes, and asleep it holds still after a minute. With Reduce Motion it never moves: its cues fade in and out in 0.15 s. A sidebar row's fill changes color in 0.12 s under the pointer, instantly with Reduce Motion. The creature is a small companion in the sidebar; it takes the stage once, at launch, and only while the app really loads: it walks in place on the window's background (four frames of 0.12 s, a flat shadow under its feet, no aura), for at least 0.48 s counting the load itself, then the window crossfades to its screen in 0.25 s. "Waking up…" appears under it only when the load takes more than 1.5 s. With Reduce Motion it stands still and the crossfade is a 0.15 s dissolve. Captures and demos never show the splash, and reopening the window never shows it again.

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
| `Colors.accentLight` / `accentDeep` | `#B487EA` / `#8657C9` | inline notices / the fill of prominent buttons |
| `Colors.button` | `accentDeep` | prominent buttons (4.7:1 with `onAccent`) |
| `Colors.selection` | accent at 18% | the selected sidebar row, the memory box of the diagram |
| `Colors.rowHover` | text at 6% | a sidebar row under the pointer (neutral, fainter than `selection`) |
| `Colors.rowPressed` | text at 10% | a sidebar row while it is pressed |
| `Colors.accentSoft` | accent at 35% | the older bars of the usage chart |
| `Colors.onAccent` | `#FBF7FF` | text on the accent |
| `Colors.meter` | text at 42% | the RAM bars of the Usage screen that are not an account's (the Mac, terminal sessions, other apps); an account's bar takes its tint, every bar sits on a `field` track |
| `Colors.sage` | `#8FC7A6` | "open" dots, "saved" states |
| `Colors.vaultBackground` | `#262626` | an Obsidian vault's graph, flat like Obsidian's canvas (Minimal theme, dark) |
| `Colors.vaultNode` / `vaultLine` / `vaultText` | `#999999` / `#3F3F3F` / `#D1D1D1` | a vault's nodes without a color group, its lines (one pixel, opaque), its labels |
| `Colors.vaultHighlight` / `vaultFocused` | `#750F0F` / `#8C1212` | the hovered node and its lines / the ring around it (the two shades Minimal draws from the accent `#8B1212`) |
| `Colors.vaultAttachment` / `vaultUnresolved` | `#E0DE71` / `#666666` | attachments and links to no file, when the vault shows them |
| `Theme.color(group:)` | the vault's own | a vault's color groups, from the rgb integers of its `graph.json` |
| `Colors.creature` / `creatureEye` | `#A06BE0` / `#1E1430` | the creature |
| `Halo.opacity` / `radius` / `size` | 0 / 110 / 520 | background halos (off; set 0.14 to bring them back) |
| `Aura.softOpacity` / `fullOpacity` / `lineWidth` / `period` | 0.10 / 0.45 / 6 / 7 s | the spinning aura |
| `Motion.out(d)` / `inOut(d)` | `cubic-bezier(0.23, 1, 0.32, 1)` / `cubic-bezier(0.77, 0, 0.175, 1)` | entering, exiting and feedback / moving on screen (the site's `--ease-out` and `--ease-move`) |
| `Motion.hover` / `quick` / `base` / `page` / `ring` | 0.12 / 0.15 / 0.22 / 0.32 / 1.2 s | hover and press / small changes / most changes / a page / a ring |
| `Motion.pop` / `settle` / `hop` | springs 0.35, 0.6 / 0.4, 0.88 / 0.28, 0.55 | a dot or swatch that pops / layout that settles / a hop |
| `Motion.reduced` | 0.15 s linear | every change with Reduce Motion: opacity and color only |
| `Motion.isCapture` / `slow` | `BRAINMERGE_CAPTURE` / `BRAINMERGE_SLOW_MOTION` (debug builds) | captures show each scene's still / every token and scene slowed down to feel-check it |
| `Launch.unit` / `lift` | 7 / 20 | one pixel of the walking creature on the launch splash, in points / how far above the center it stands |
| `Launch.frameDuration` | 0.12 s | one frame of the four-frame walk |
| `Launch.minimumVisible` | 0.48 s | the shortest the splash stays, the load's own time included |
| `Launch.fade` / `reducedFade` | 0.25 s / 0.15 s | the crossfade to the first screen / its dissolve with Reduce Motion |
| `Launch.slowCaptionAfter` | 1.5 s | when "Waking up…" appears on a slow launch |
| `Layout.padding` / `cardRadius` | 20 / 12 | screen padding, card corners |
| `Layout.rowRadius` | 10 | sidebar rows: their selection, hover and press fills |
| `Layout.readingWidth` / `formWidth` | 880 / 720 | the widest a Memory or Usage card gets / the settings form |
| `Layout.meterRadius` | 3 | the thin RAM bars of the Usage screen |

The menu bar icon (`Design/MenuBarIcon.swift`) is the creature drawn from the same grid as a template image: macOS paints it in the menu bar's own color, so it carries no token. Cells are 1.5 pt on a Retina display (1 pt at 1x, to stay on whole pixels) in a 24 by 18 pt canvas, so the creature is 16.5 pt tall; its eyes are cut out, open while an account is open or opening, a thin line one row lower otherwise. No badge, no count, no animation. The accounts in its menu carry a 10 pt dot in their tint (`Theme.color(for:)`).

Account tints (`Theme.hex(for:)`): orange `#D97757`, blue `#6FA3D8`, green `#7FA37A`, purple `#A87BC9`, pink `#D97A8E`, yellow `#E0A526`, gray `#7D8A99`. Red maps to pink and is not offered in pickers.

Aura colors, in order: `#A06BE0`, `#C58FD9`, `#7FB5E8`, `#8FC7A6`, `#E9A45C`, `#B487EA`.

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

Every screen starts with `ScreenHeader`: the serif title, an optional subtitle capped at 560 points, and the screen's actions on the right, aligned with the title line. The default font of the window is `Fonts.body`, so an unstyled text never falls back to the system size.

## Retheming

Fork, edit `Theme.swift`, run `swift test --package-path Packages/BrainmergeUI` (the theme tests pin the accent and the sobriety thresholds; adjust them with your values), rebuild. The creature lives in a single file, `Design/CreatureView.swift` (its walk is computed from its grid, so a new grid walks too), and the app icon and brand assets are generated by `scripts/make-brand.swift` from the same tokens.
