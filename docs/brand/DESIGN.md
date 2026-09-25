# Brainmerge design guide

Everything visible in Brainmerge derives from one file, `Packages/BrainmergeUI/Sources/BrainmergeUI/Design/Theme.swift`. Change a token there and the whole app follows. This page is the human-readable version of those tokens, for contributors and for anyone who wants to retheme the app.

## Principles

1. **A dark, quiet canvas.** Near-black with a faint purple cast at the top left. No halos, no decoration: nothing competes with the accounts.
2. **Cream text, three levels.** Full, muted (64%), faint (50%): every level reads at 4.5:1 or better on the canvas. Serif for titles (the system serif), sans for everything else.
3. **One accent.** The purple of the creature, and only it, for actions: switches, segmented controls, the selected item in the sidebar, progress dots. A sidebar row under the pointer gets a neutral cream fill, fainter than the selection, so the purple keeps meaning "selected". Primary buttons are filled with its deep shade (`Colors.button`), so their white label reads at 4.7:1. Secondary actions are glass buttons.
4. **Glass surfaces, native controls.** Cards, sidebar and chips use the system glass (`glassEffect`) with a thin rim; primary actions are the system's prominent glass button tinted with the accent, secondary actions plain glass. Corner radius 12 for cards, 14 for the sidebar, 10 for its rows, capsules for chips. A sidebar row is clickable across its whole width.
5. **Flat account colors.** Each account has a muted tint (or a photo) on a flat circle with its initial. No gloss, no glow.
6. **Motion with a purpose.** The aura appears only around an account that is opening, and around the creature when the memory was just saved. Reduce Motion freezes it. A sidebar row's fill changes color in 0.12 s under the pointer, instantly with Reduce Motion. The creature is a small companion in the sidebar, never a hero.

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
| `Colors.sage` | `#8FC7A6` | "open" dots, "saved" states |
| `Colors.creature` / `creatureEye` | `#A06BE0` / `#1E1430` | the creature |
| `Halo.opacity` / `radius` / `size` | 0 / 110 / 520 | background halos (off; set 0.14 to bring them back) |
| `Aura.softOpacity` / `fullOpacity` / `lineWidth` / `period` | 0.10 / 0.45 / 6 / 7 s | the spinning aura |
| `Creature.glowOpacity` | 0 | glow behind the creature (off) |
| `Layout.padding` / `cardRadius` | 20 / 12 | screen padding, card corners |
| `Layout.rowRadius` | 10 | sidebar rows: their selection, hover and press fills |
| `Layout.readingWidth` / `formWidth` | 880 / 720 | the widest a Memory or Usage card gets / the settings form |

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

Fork, edit `Theme.swift`, run `swift test --package-path Packages/BrainmergeUI` (the theme tests pin the accent and the sobriety thresholds; adjust them with your values), rebuild. The creature lives in a single file, `Design/CreatureView.swift`, and the app icon and brand assets are generated by `scripts/make-brand.swift` from the same tokens.
