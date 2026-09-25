# Changelog

## 0.5.0 (unreleased)

- Sidebar: every row is clickable across its whole width, not only on its text or icon, and lights up softly under the pointer (a neutral fill; the purple still marks the current screen). Cmd-1 to Cmd-4 switch screens, and VoiceOver says which screen is selected.
- Sidebar accounts say what a click does: "Open", "Show" when the window already runs, "Opening…" until it appears, "Updating…" while its app is being rebuilt (the row waits instead of opening a half-built app), "Rebuild" when its app is missing. A tooltip says more: which Claude an outdated copy was built for, or, for an account that still has to log in while other Claude windows are open, to quit them first.
- Several accounts can be opening at once, and each one stops showing "Opening…" as soon as its window runs.
- An account without a Claude window (Claude Code only) explains itself when opened, instead of ending in "Something went wrong".
- A launch animation that shows real work: the window appears sooner and the creature walks in place while Brainmerge loads, then the window fades to your accounts. A fast launch shows it for about half a second; "Waking up…" appears only when loading takes longer than a second and a half. With Reduce Motion the creature stands still. It shows once per launch, never when the window is reopened, and never in captures or demos. The process list and the memory's history load off the main thread, so the walk never stutters.

## 0.4.0

- The memory as a live graph, like Obsidian's graph view. Every note is a bubble in the color of the account that saved it last, links between notes are threads, and each project is a larger bubble that is also its index (`MEMORY.md`). A note pulses while Claude Code writes it, and again, in the account's color, when that account saves it. Hover a bubble to light it and its neighbors, click it to read it (who saved it, when, its first lines, updated live), double-click it to open it in your notes app. Drag to move around or to pull a bubble, pinch or scroll to zoom. The legend counts each account's notes; click an account to keep its notes lit. The timeline of sentences stays one click away.
- The graph reads links the way Obsidian does: `[[wikilinks]]` with aliases and headings, notes with dots in their names, Markdown links relative to the note or to the memory, links with spaces or titles; code and embedded files are left out. Names with accents keep their author.
- Light on the Mac: only notes that changed are read again, the history is read again only after a save, a fifty-thousand-file vault is walked in about a quarter of a second, a hidden window stops reading, and only the drawing redraws while the graph moves. Up to 2,000 notes are drawn, the most recent. Symlinks are never followed, and a memory kept behind a symlink (Dropbox, iCloud) is read where it really is.
- Keyboard and VoiceOver: with keyboard navigation on, arrow keys go from note to note, Return opens, Escape closes; VoiceOver lists the notes with who saved them. With Reduce Motion, the graph settles out of sight and pulses do not ripple.
- Opening a note whose name holds "&", "+" or "=" in Obsidian now opens that note.
- Releases can be signed with a Developer ID and notarized by Apple (`scripts/release.sh` with a team and a notary key); screenshots are only ever taken on a demo home.

## 0.3.0

- Several memories: one shared by default, and any account can get a memory of its own (from its card's menu, the edit sheet, the add sheet or the guided setup). Every account writes to exactly one memory; switching relinks its projects and moves no note. The Memory screen has a picker, Settings lists the memories (add, rename, forget without deleting), and the command line follows (`brain list | add | forget | rename`, `identity add --brain | --own-brain`, `identity edit --brain`). States written by 0.2 are migrated as they are.
- Connected state: each card says whether the account has logged in, the guided setup turns to "Connected" on its own, `doctor` and `identity list` report it. Decided from the names of Claude's own storage files, never their contents.
- Each account is a real app: an edit sheet (name, color or photo, note, memory, own icon in the Dock, show its app in Finder to drag it to the Dock), a visible menu on every card, and `identity edit --icon distinct|launcher`.
- Alive: when Claude updates itself, the accounts with their own Dock icon are flagged and updated with one click (or all at once, or on their own when the setting is on); the version is re-checked when the window comes to the front. "Check for updates" opens the releases page without any connection from the app.
- Usage reads eight gigabytes of transcripts in about seventeen seconds and seventy megabytes instead of forty-eight seconds and nine hundred (a byte walker instead of JSON decoding, one pool per file and per chunk); the next read takes under a second. Projects are named after their real folder. `brainmerge usage` prints the same numbers, with `--timing`.
- Remove Brainmerge from Settings or with `brainmerge uninstall`: hooks, blocks, account apps, command line link and settings go; each project keeps a copy of its notes; memories, Claude data and logins stay.
- Design finishing pass: one header component, AA contrasts, a left-aligned add sheet with Return and Escape, usage figures that fit at the minimum window size, a reading width for long screens, tokens for fields and selection, aligned notes app tiles, pinned progress dots.
- The README and the welcome step say what the app is for; the "All set" step gives three tips to go further.
- Security: guard tests that keep the source tree free of networking, shells and credential reads; names kept to one clean line everywhere they end up; a launcher that only ever starts Claude; a tinted copy refused when Claude's signature is broken; Dependabot and read-only CI permissions; a SECURITY.md that says what the app touches and what it never does.

## 0.2.0

- Usage per account: output and context tokens for today, seven days and thirty days, by project and by model, read from Claude Code's local transcripts. Accounts that share their history are shown as one. A button opens Claude's own usage page for limits and reset times. Brainmerge never switches accounts for you.
- Memory per account: the RAM of each open Claude window (with its helper processes) on its card and in the sidebar, and a quiet warning when the Mac runs low on memory.
- A calmer, more professional look: one purple accent, neutral dark canvas, flat avatars, native controls, compact cards, no halos, the aura only as feedback. Design tokens documented in `docs/brand/DESIGN.md` so anyone can retheme.
- Installer: a proper disk image (background, drag to Applications) and an offer to move the app to Applications when it runs from the image or from Downloads.
- Safer first login: a new account is not opened while another Claude window is running (the login link would land in it); Brainmerge asks to quit the others first.
- The command line link is created at the end of the first launch, never over a link you made, never from a disk image.
- Fifty accounts stay smooth: the interface only redraws what changed, photos are decoded once.
- Long operations (building an icon, removing an account) run in the background with a progress sentence.
- Missing memory folder: a dedicated screen, and every account is re-attached to the folder you choose.
- First launch: a guided setup in six steps, with an animated "How it works" diagram, a picker for the app that opens the memory (real icons of the notes apps found on the Mac, any other app, suggestions when none), an optional second account with login guidance, and a live checklist at the end.
- Brand assets generated from the design tokens: app icon, GitHub avatar, social banner, README header, SVG logos.
- Many small fixes from the v0.1 review: renaming validation, memory sentences, onboarding banner, delete options, notes language for the command line, graceful quit, CI.

## 0.1.0

First release, macOS 26.

- Accounts: your current Claude becomes the first account; add up to fifty more, each with a name, a color or a photo, and a note. Open, quit, rename, recolor, rebuild, remove.
- One memory: a folder of plain notes (`~/Brain` or a folder you already have), shared by every account, versioned with git, saved by a Claude Code hook after each session.
- Memory screen: who remembered what, and when, in plain sentences.
- Settings: Claude app detection, distinct icons rebuilt after Claude updates, memory folder, notes language, command line install.
- Command line `brainmerge` with the same features, plus `doctor`.
- Guided first launch in three screens. No terminal needed.
- Builds are signed ad hoc (no Developer ID yet): macOS asks to confirm the first opening.
