<p align="center">
  <img src="docs/brand/readme-header.png" alt="Brainmerge" width="800">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-a06be0" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-1a1918" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Swift-6-1a1918" alt="Swift 6">
  <a href="https://github.com/ruben4reall/brainmerge/actions/workflows/ci.yml"><img src="https://github.com/ruben4reall/brainmerge/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

# Brainmerge

**Every Claude account you own, side by side, each with its own window, and one memory between them (or one each).**

[Website](https://brainmerge.vercel.app) · [Download for Mac](https://github.com/ruben4reall/brainmerge/releases/latest/download/Brainmerge.dmg) · [Changelog](CHANGELOG.md)

## The problem

The Claude app knows one account at a time. If you have two, a personal one and one for work, a client's or a team's, you spend the day logging out and back in. Nothing you learned in one account exists in the other. People end up with home-made scripts, duplicated folders and a terminal window they would rather not have.

## What Brainmerge does

Brainmerge is a native macOS app that turns each of your Claude accounts into a real app on your Mac: its own window, its own name, color or photo, its own icon in the Dock if you want. Open it from the Dock or from Brainmerge, log in once, and it stays logged in. All your accounts share one memory of your projects, a folder of plain notes, unless you give an account a memory of its own (work things stay at work). Claude itself stays exactly as it is: the official app, the official Claude Code, your own logins. No terminal, ever: everything is a button.

![Your accounts, side by side](docs/design/captures/03-comptes.png)

## Safe for your accounts, by design

Brainmerge is built so that there is nothing in it Anthropic's terms could object to. Of Anthropic's software, it only starts the official Claude app and the official Claude Code, each account logs in by itself, and it never looks for, stores or sends a password, a token or a cookie (the arguments of running programs, where a command can hold one, pass through it once as `ps` lists them and are dropped as they are read, and the secret guard reads the lines a save adds to your notes only to keep a key out of the memory). To tell your accounts apart, it only shows the email Claude Code records for each one, and stores it nowhere. It has no account switching, no rotation, no pooled usage, and it makes no network call of its own. Those are not just words: tests scan the source tree at every run to keep them true, and `SECURITY.md` lists exactly what the app touches on your Mac. One account is one person; Brainmerge keeps several of yours tidy, nothing more.

## What you get

- **One app per account.** A personal account and a business one, a client's, a team's: up to fifty. Each has a name, a color or a photo, a note, and an app of its own in `~/Applications/Brainmerge` that you can drag to the Dock. Open, quit, edit, remove, from buttons.
- **One memory, or one each.** What Claude Code learns about a project in one account, the others know too, through a shared folder of Markdown notes (`~/Brain` by default, or a folder you already have: an Obsidian vault works well). Give an account its own memory in one click, for work or a client: what it learns then stays there. Every account writes to exactly one memory; nothing is ever moved or deleted behind your back.
- **A timeline of what was remembered.** Who saved what, about which project, and when, in plain sentences, for each memory.
- **Each account signs only what it wrote.** A save commits exactly the notes that account wrote, under its name; your own edits are saved as You, once nothing changed for ten minutes and no session runs.
- **No key in your memory.** A note with a line that looks like a key, a token or a long random password is held back from the save, and the value is never shown, logged or copied.
- **Your git setup stays yours.** Saves ignore your global git config, hooks and signing, never ask for a passphrase, and wait while a merge of yours is not finished.
- **Notes Claude will actually load.** The Memory screen's Tidy tab lists the notes no session will load (a project with notes and no index, an index past the 200 lines Claude Code reads, notes left in a quick session's folder) and files them where the next session looks, one click and one commit at a time.
- **Your Obsidian vault as a graph.** The Memory screen can also draw an Obsidian vault the way Obsidian does, with its filters, colors and zoom, and only ever reads it.
- **Connected, or not yet.** Each card says whether the account has logged in, and the guided setup turns to "Connected" on its own once you have. Brainmerge only looks at the names of Claude's own storage files, never inside them.
- **Which account is which.** Each card shows the email Claude Code uses for that account, the search finds it, and two accounts on the same Claude account are pointed out. When the names ended up on each other's account, the edit sheet offers to swap them, once you confirm. Claude Code's display name can become the name, never without a click.
- **Alive.** When Claude updates itself, the accounts that keep a copy of it (the ones with their own Dock icon) are rebuilt for the new version, on their own or with one click. Claude's version is checked every few minutes and whenever the window comes to the front. The other accounts' windows opened before the update say so on their card and in the sidebar, with a Restart button (or Restart When Idle, once their Claude Code sessions end, which you can cancel from the same menu). If Claude's own restart brings it back on the first account's folders, Brainmerge says so and offers to reopen the right account. Nothing is quit without a click.
- **Health at a glance.** Settings opens on Health: "Everything is in place." or one plain line per thing to fix, with its button, and a card says when its last save failed, and why.
- **Usage per account.** What each account spent, read from Claude Code's own transcripts on your Mac (Brainmerge reads the recent ones whole and keeps only dates, projects, models and token counts): today, seven days, thirty days, by project and by model. Informative only: Brainmerge never switches accounts for you. Reading eight gigabytes of transcripts takes under twenty seconds and a few dozen megabytes; the next read takes under a second.
- **Limits, when you ask.** Brainmerge never reads limits by itself: "Check limits" on an account's card asks that account's official Claude Code, the same as typing /usage, and shows the limits it prints, the current session and week, as bars.
- **RAM and disk per account.** At the top of the Usage screen: your Mac's RAM counted like Activity Monitor, how much of it each account's Claude uses (with everything it runs), Claude Code sessions in a terminal as one row, the other apps, and the disk space each account's folders and app take. A quiet warning shows when your Mac runs low on RAM.
- **In the menu bar.** The creature sits in the menu bar: open or show any account from there, see your Mac's RAM, open Brainmerge or its settings. With it, closing the window keeps Brainmerge running there; turn it off in Settings and closing the window quits, unless the quick opener is on.
- **Accounts menu and links.** The Accounts menu opens or shows any account (Cmd-Option-1 to Cmd-Option-9 for the first nine), and `brainmerge://` links do the same from Raycast, a Stream Deck or a note, never more than open or show.
- **From any app.** Turn on the quick opener in Settings and pick a shortcut (Control-Option-Space is suggested): a small glass panel lists your accounts over whatever app you are in. Type a few letters, then Return opens or shows the account, Cmd-Return opens its memory in your notes app, Cmd-U shows its usage. It needs no special permission.
- **Connections per account.** Pair each account with a Chrome, Arc, Brave or Edge profile, open its claude.ai connectors there, and see its MCP servers by name.
- **Claude Code in a terminal, per account.** `brainmerge code work`, or `claude-work` once you turn it on in Settings, starts Claude Code on that account with its memory.
- **A setup that never dead-ends.** On a Mac without git, the guided setup offers Apple's free tools and moves on by itself once they are installed.
- **A creature with a life.** At launch it gathers itself and leaps into the sidebar; there it walks while an account opens, waves when it is open and hops when the memory saves a note. With Reduce Motion, it holds still.
- **Nothing leaves your Mac.** No server, no account of ours, no network call from Brainmerge. "Check limits" asks your own Claude Code, which talks to Anthropic as it always does, and the Connections buttons open your browser, which loads the page. Everything is local files and git.
- **Leaves cleanly.** Remove Brainmerge from Settings: its hooks, account apps, terminal commands, link and settings go, every project keeps a copy of its notes, your memories and logins stay.

## How it works

### First launch: a guided setup

![First launch](docs/design/captures/02-premier-lancement.png)

![How it works](docs/design/captures/02b-how-it-works.png)

1. A welcome that says what Brainmerge is for.
2. How it works: three account windows and one folder on this Mac, the memory. A note one account saves drops into it, and the other two can read it.
3. Where the memory lives: a new folder, or one you already have. Notes can be written in English or in French. Pick what opens it: the folder, a notes app found on your Mac (Obsidian, Logseq, iA Writer, Typora, VS Code, Cursor, Zed, with their icons), or any other app; free apps are suggested when none is installed.
4. Your current Claude becomes your first account, with every project it already remembers.
5. A second account, optional: name, color, note, and whether it shares the memory or gets its own. It is created on the spot, the screen guides the login (Claude must not be open elsewhere, the login link would land there) and says "Connected" once you are.
6. All set: a live checklist (Claude, memory, accounts, git, Claude Code, command line), what happens next, and three tips to go further.

On a Mac without git, a step before the memory's place offers Apple's free Command Line Tools, and the setup moves on by itself once they are installed.

### Accounts

![Add an account](docs/design/captures/04-ajout.png)

Give it a name and a color (or a photo), optionally a note, and pick its memory: shared, another one, or its own. Claude opens in a new window and asks you to log in, like always; when other Claude windows are open, the "Log in" sheet comes first (see Install). The card then shows whether it is open, logged in, and which memory it writes to. Every card has a menu: edit, memory, show its app in Finder, rebuild, quit, remove. In the sidebar and on the cards, each account says what a click does: "Open", or "Show" when its window already runs. Cmd-1 to Cmd-4 switch screens (see the View menu).

![Edit an account](docs/design/captures/08-edit.png)

Editing an account changes everything in one place: name, color or photo, note, memory, and the "Own icon in the Dock" option. With it, the Dock shows this account's icon and name while it runs (a local copy of Claude with its icon and program swapped, re-signed ad hoc on your Mac, rebuilt after each Claude update); without it, a small launcher starts the real Claude with the right folders. Your first account is the Claude app itself: its name, color, photo and note change while Claude stays open (only a new memory waits for Claude to quit). Brainmerge never changes Claude, so the Dock shows Claude's icon while it runs; the "Own app with this color" switch adds a small app with the account's color or photo that opens Claude, to keep in the Dock in its place. Its Connections section pairs the account with a browser profile (Chrome, Arc, Brave or Edge): "Open Chrome (Work)" starts that profile. Log that profile's Claude extension into this account once, and each account then has its own browser, with no logging out. "Manage connectors" opens the account's connectors page on claude.ai there (or in your default browser when no profile is picked): Gmail, Calendar and Drive belong to each Claude account. It also lists the account's MCP servers by name, marking the ones only this account has. To list the profiles, Brainmerge reads each browser's `Local State` file for the profile ids and names only; it starts the browser you picked, in that profile, only when you click. It reads profile and server names only, never an address or a server's settings. A new account starts with a copy of five of your first account's Claude Code settings (language, model, theme, effort level and plugins; never its hooks, permissions or `env`) and uses the same skills folder, through a link. Advanced options when adding: share the conversation history with your first account, or reuse folders you already had for that account.

### The memory

![Memory](docs/design/captures/05-memoire.png)

Every account writes its notes into its memory, one subfolder per project. The Memory screen shows it as a live graph, like Obsidian's: every note is a bubble in the color of the account that saved it, links are threads, each project is a larger bubble with its notes around it. A note pulses while Claude Code writes it, and again when the account saves it. Hover a bubble to light its neighbors, click it to read it, double-click it to open it in your notes app. The Timeline tab tells the same story in sentences.

The Tidy tab, "Tidy (4)", lists what Claude Code will not load and what else wants a look, in groups: notes Claude will not load (a project with notes and no index, "trailbook has 2 notes and no index, so no session loads them."; an index past the first 200 lines, which is all Claude Code loads; notes missing from their project's `MEMORY.md`), notes in one-off folders (a quick session's folder, which no later session reads), copies left when an account's notes were linked (`deploy.work.md` beside `deploy.md`), index lines that point nowhere, and changes not saved for more than a day. Nothing happens without a click. File under… suggests the projects the notes' names mention (`trailbook-pricing.md` goes to trailbook), says what it will do ("Move 2 notes from scratch-2026-09-23-5050ce to brainmerge, with their index lines."), then Move makes one commit, "You filed 2 notes under brainmerge". Compare shows both copies side by side, and Keep this one moves the other to the project's `_archive/` folder. Hide takes empty quick session folders off the tab; folders are never deleted, since accounts link to them. A note written in the last two minutes ("This note is being written. Try again in a moment."), or with changes no save committed yet, is never moved. `brainmerge brain health [--json]` says the same in a terminal.

The graph can also show an Obsidian vault, the way Obsidian shows it. Next to the Graph and Timeline switch, pick one of the vaults Obsidian knows, or choose a vault's folder; Brainmerge remembers what you picked. Brainmerge then follows the vault's own graph settings: its search filter and Excluded files, its color groups, orphans, attachments and unresolved links, its forces, sizes and saved zoom, all read again when you change them in Obsidian. Labels fade in as you zoom, hovering a note lights its links and fades the rest, one click opens the note in Obsidian, and a secondary click shows it here. The vault is only read, on your Mac: Brainmerge never writes to it. A vault in Documents, iCloud Drive or another place macOS guards is only read once you pick it, so macOS may ask you then, once, to let Brainmerge read that folder; opening the Memory screen never asks.

A memory is a git repository: each account signs its own saves, and only what it wrote itself, so Brainmerge can tell you who remembered what (`git log` reads "Work remembered 2 things about acme"). Your own edits, made outside Claude, are saved as You, in gray, once nothing changed for ten minutes and no Claude Code session runs (Settings, Memories, "Save my own edits to the memory's history"); an Obsidian vault's settings or daily notes next to the notes are never committed. Two limits: when two accounts edit the same `MEMORY.md` before either saves, the first save signs both edits; and only Claude's edit tools (Write, Edit, MultiEdit) mark a note as an account's, so a note Claude writes or moves another way (a Bash `mv`, NotebookEdit, an MCP tool) is saved later as You. A note with a line that looks like a key (a private key, a provider's API key or token, a long random password) is not saved: the Memory screen says "1 note was not saved: it looks like it holds a key." and where ("acme-api/deploy.md, line 12, looks like a GitHub token."), never the value, with Open, "It's not a secret" and "Save anyway"; the rest of the save goes through, and `brainmerge doctor` lists held notes too. When an account's save fails, its card and the Memory screen say so quietly, with when and why: "Last save failed 3 hours ago: the memory was locked by another program." A memory folder can't sit inside another git repository: choose that repository's top folder, or a folder outside it. The graph only reads the folder, never writes to it. Open it in Finder, Obsidian or any app; with several memories, a picker at the top switches between them. Settings lists every memory, the accounts that write to it, and lets you add one, rename one, or forget one you no longer use (its folder stays on disk).

### Settings

![Settings](docs/design/captures/06-reglages.png)

Health comes first: each time Settings opens, Brainmerge checks what it set up (the same check as `brainmerge doctor`) and says "Everything is in place." or one plain line per thing to fix, each with its one button: Repair links, Rebuild, Install command line, Choose memory folder, Repair hooks or Install Apple's tools. After a macOS or Claude update the check runs once on its own and says one line, such as "Checked after the Claude update: all good." Then where Claude is, whether Brainmerge shows in the menu bar, the quick opener's shortcut, whether tinted copies are rebuilt after a Claude update, your memories, the notes app, the language of new notes, the optional command line, a "Star on GitHub" link, and the two exits: check for updates (opens the releases page, no connection from the app) and remove Brainmerge.

### Quick opener

Settings, Quick opener, is off until you turn it on. Its shortcut (Control-Option-Space unless you click it and type another) brings up a small glass panel over the app you are in, without switching to Brainmerge: a search field, then your accounts with their photo or color, their note and the sidebar's word (Open, Show, Opening…). Letters match the start of a name first, then the start of a word in a name, then the note. Return opens or shows the account, exactly like the Accounts menu (an account that still has to log in goes through the Log in sheet), Cmd-Return opens the memory it writes to in your notes app, Cmd-U shows its card on the Usage screen, and Esc or a click elsewhere closes the panel. It works with the window closed. A shortcut another app already holds is said, and the previous one stays; Cmd with a letter is refused, since it is every app's own command. The shortcut belongs to this Mac: it is kept in Brainmerge's preferences, not with your accounts.

### Usage

![Usage](docs/design/captures/21-usage.png)

The screen opens on RAM and disk. First your Mac: the RAM in use (apps, wired and compressed, the way Activity Monitor counts it), out of how much, and the pressure word when macOS says it is short. Then one row per account: the RAM its Claude uses with everything it runs (its windows, its Code tab, the tools they start), as a share of the Mac, and the disk space of its Claude data folder, its Claude Code profile and its app (hover for the parts). A closed account shows its disk only. Claude Code sessions started in a terminal are one row for all accounts together: which account a session uses is only in its environment, which Brainmerge never reads. Disk sizes are added up from file metadata, never file contents, off the main thread, when the screen opens and at most every five minutes ("Measure again" to redo it now); a shared history is counted once, with your first account.

Below, what each account spent: each card is one account, or two accounts that share their history (they write the same transcripts, so their usage is one number). Numbers are output tokens (what Claude wrote) and context (what it read, cache included), from the transcripts Claude Code keeps locally.

Each account with Claude Code has a "Check limits" button on its card, Claude Code only accounts included. Brainmerge never reads limits by itself: on your click, and only then, it runs that account's official Claude Code (`claude -p "/usage"`, the same as typing /usage) and shows each limit it prints as a thin bar with its percentage and reset time, and when it asked. The answer stays in memory until Brainmerge quits; Claude Code itself handles the run like any session it starts, and may keep its own record of it, as when you type /usage. "See limits in Claude" opens Claude's own usage page in your browser.

### Under the hood

- Each account is the official Claude app launched with its own data folder (a standard setting of the app) and Claude Code launched with its own `CLAUDE_CONFIG_DIR` (a variable documented by Anthropic).
- Brainmerge links each project's memory folder into the account's memory, and installs three small Claude Code hooks: one notes each file an edit writes in a memory, one saves exactly those notes to git at the end of each session, under the account's name, and one links a project's memory as soon as a session starts in it, so a project opened while Brainmerge is closed already writes its first note into the memory. They run only if Brainmerge is still there and always end with success, so a Brainmerge moved or trashed never blocks a session, and each launch points them at the app again and brings hooks written by an older Brainmerge up to date. Settings, Command line, says whether every account's hooks are current, with "Repair hooks"; `brainmerge doctor` says it too.
- The Dock icon of a second account is a small launcher app that starts the real Claude with the right folders. By default nothing else is created. The "own icon" option makes a local copy of Claude on your own Mac, never shared.
- The first account's own app, when you switch it on, is the same small app with its color or photo. It asks macOS to open Claude itself, and only Claude: the one it was built for, signed by Anthropic. Claude opens on its usual folders, or comes to the front if it already runs.
- An app you made yourself for an account, such as a copy of Claude whose executable is a launch script with the account's folders, is recognized by reading its `Info.plist` and that script, never by running it. The edit sheet says which account it opens, and warns, like `brainmerge doctor`, when it runs an older Claude than the one installed, which can damage the account's data. Brainmerge never opens, changes or trashes that app: you retire it yourself once the account is closed.
- The quick opener's shortcut is registered with macOS through `RegisterEventHotKey`, which tells Brainmerge when that shortcut is pressed and nothing else: no Accessibility or Input Monitoring permission, no event tap, no global key monitor. The panel only reads what you type into it.
- "Connected" comes from the presence of Claude's own storage files in the account's data folder. Their contents are never read.
- RAM figures come from the kernel: the Mac's statistics, and one number per Claude process (the footprint Activity Monitor shows), never another process's memory, environment or open files. Disk sizes come from the sizes the file system reports while listing each folder, without following links or opening a file.
- "Check limits" finds Claude Code at absolute paths (`~/.local/bin/claude`, then Homebrew's two), checks with the Security framework that Anthropic signed it and that it is 2.1.275 or later, and runs it with only `HOME`, a minimal `PATH` and the account's `CLAUDE_CONFIG_DIR`, stopped after 20 seconds. Brainmerge reads only the text it prints.
- The email on a card comes from Claude Code's own `.claude.json`, where it records the account it last used for display: only the email, the display name and the organization name are decoded, never the rest. It is shown in the window and written nowhere (not in Brainmerge's state, a memory, a commit or the command line's output).

## Install

1. Download the disk image from the releases page, open it and drag Brainmerge to Applications. If you open the app from somewhere else, it offers to move itself there.
2. Open Brainmerge and follow the guided setup. That is all: no terminal, no configuration file.
3. Add a second account whenever you like, then click "Log in" on its card: Brainmerge closes your other Claude windows while you log in, and reopens them when you click.

Brainmerge needs macOS 26, the Claude app and git, Apple's free Command Line Tools, which the setup offers. The first time a new account opens, macOS asks once to allow "Claude Safe Storage" in the keychain: click Always Allow. It may also ask whether the new account may access your Documents folder: click Allow. Both prompts come from the Claude app doing exactly what it does on first launch, under the new account's name.

Releases are signed with a Developer ID and notarized by Apple: the first time, macOS only asks you to confirm opening an app downloaded from the internet. If you build an unsigned copy yourself, macOS stops its first opening: open System Settings, then Privacy & Security, and click Open Anyway (since macOS 15, right-click and Open no longer does it).

## Why this stays within Anthropic's terms

Anthropic's Consumer Terms forbid sharing or lending accounts, rotating accounts to get around usage limits, and using a subscription token outside Claude Code and the Claude apps. Brainmerge is built to stay on the right side of every one of those rules:

1. Of Anthropic's software, it only launches the official Claude app and the official Claude Code that are already installed. Beyond that, and only on your click, it can start Apple's own installer for its Command Line Tools, or your browser (in the profile you picked for an account, if any). Each account logs in by itself, inside Claude.
2. It never looks for, stores or transmits a password, a credential or a token. Some things it reads whole can hold one, and it keeps, logs and sends nothing of them: every running program's arguments as `ps` lists them (it keeps only whether a line is Claude and, for a Claude window, its program and its data folder, never the line), a Claude Code `settings.json` it rewrites to add its hooks (only `hooks` changes; a key under `env` passes through), the text of each edit Claude Code hands its PostToolUse hook (only the file's path is decoded), and the transcripts the Usage screen reads (only dates, projects, models and token counts are decoded). The secret guard reads only the lines a save adds to your notes, to hold back one that looks like a key, and keeps nothing of the line. `SECURITY.md` lists each one. Even "Connected" is decided from file names alone, and the account a card shows is the email and name Claude Code writes down for display, not a credential.
3. It separates accounts with `CLAUDE_CONFIG_DIR`, a variable documented by Anthropic, and with a data folder per instance, a standard setting of the app.
4. The memory is a folder of local files. Brainmerge itself makes no network call, to Anthropic or to anyone else. "Check limits" runs the account's own Claude Code, which does what typing /usage does.
5. It has no account rotation, no switching when a limit is reached, no pooled usage, and never will.
6. It does not redistribute Anthropic's binaries, and the installed Claude app is never touched. The optional "own icon" is the one exception to "unmodified": it makes a local copy on your own Mac, never shared, swaps that copy's program for Brainmerge's launcher, changes its icon and `Info.plist`, and re-signs the copy ad hoc on your Mac, so the copy no longer carries Anthropic's signature. Without that option, every account runs the installed Claude, unmodified.

One account is one person. Brainmerge helps people who legitimately hold several accounts, for instance a personal one and one for a business, keep them tidy. It does not promise anything about bans: how you use your accounts is up to you.

## Disclaimer and terms of use

Brainmerge is free and open-source software, published under the MIT license. It is provided "as is", without warranty of any kind. By using it you accept that:

- You are responsible for the Claude accounts you use with it, and for complying with Anthropic's terms of service. Brainmerge does not create, share, rotate or pool accounts, and must not be used to.
- The author is not liable for any suspension of an account, loss of data, or damage arising from the use or misuse of this software. Back up your memory folders; they are git repositories, so you can also push them wherever you like.
- Brainmerge is an independent project. It is not affiliated with, endorsed by, or supported by Anthropic. Claude is a trademark of Anthropic.

If any of this is not acceptable to you, do not use the software.

## Other assistants

The idea is generic: one folder per account, one memory (or several), a hook that saves it. Today the code speaks to the Claude app and Claude Code, because that is what the author uses every day. Codex and other assistants with a desktop app have similar levers (Codex CLI honors `CODEX_HOME`, reads `AGENTS.md`, and can run a command on events), but not the same automatic memory, so support is on the roadmap rather than promised. If you want to bring your assistant, open an issue: the account and memory models are designed to take a second provider.

## Command line

For people who like one. The app links `brainmerge` into `~/.local/bin` at the end of the first launch (Settings, Command line, to reinstall). Everything the app does is available there:

```
brainmerge brain init [path] [--lang en|fr]     create the default memory
brainmerge brain list | add --name NAME [path] | forget ID | rename ID --name NAME
brainmerge brain relocate ID PATH               a memory whose folder is gone: where it is now, or an empty folder
brainmerge brain status | wire | timeline [--brain ID]
brainmerge brain health [--json] [--brain ID]   notes Claude will not load, and what to tidy (read only)
brainmerge adopt-primary [--name NAME]          your current Claude becomes the first account
brainmerge identity list [--json]
brainmerge identity add --name NAME [--tint COLOR] [--logo FILE] [--note TEXT]
                        [--brain ID | --own-brain] [--no-desktop] [--tinted-icon]
                        [--shared-history] [--adopt-cli DIR] [--adopt-desktop DIR]
brainmerge identity edit SLUG [--name] [--tint] [--logo] [--note] [--brain ID] [--icon distinct|launcher] [--own-app on|off]
brainmerge identity remove SLUG [--delete-data]
brainmerge identity launch | quit | rebuild SLUG
brainmerge usage [--identity SLUG] [--json] [--timing]
brainmerge sync --identity SLUG                 save what the account wrote in the memory (called by a Claude Code hook)
brainmerge touched --identity SLUG              note a file the account wrote (called by a Claude Code hook)
brainmerge wire --identity SLUG [--hook]        link the current folder's memory (--hook: the session's, called by a Claude Code hook)
brainmerge code SLUG [args...]                  start Claude Code on that account, with its memory
brainmerge env SLUG                             print the export line for that account (eval "$(brainmerge env work)")
brainmerge doctor [--json]                      check that everything is in place
brainmerge uninstall [--yes]                    undo everything, keep every note and login
```

With Settings, Command line, "A terminal command per account" on, `claude-work`, `claude-personal` and so on sit next to `brainmerge` in `~/.local/bin` and do the same as `brainmerge code work`. The terminal tab's title becomes "Claude: Work". Each card's menu has Copy Terminal Command.

## Links

Brainmerge answers `brainmerge://` links, so a launcher, a button or a note can open an account or a screen. A link can only open or show: it never adds, edits, removes or quits anything, and an account that still has to log in goes through the Log in sheet.

```
brainmerge://open/work          open the account whose short name is "work" (or show it when it runs)
brainmerge://show/work          bring its Claude window forward
brainmerge://memory             the Memory screen (brainmerge://memory/<id> for one memory)
brainmerge://usage              the Usage screen
brainmerge://settings           Settings
```

- Raycast: a Quicklink with `brainmerge://open/work` as its link.
- Stream Deck: the Website action with `brainmerge://open/client`.
- Obsidian: a note with `[Open Work](brainmerge://open/work)`.

The Accounts menu in the menu bar lists every account with Cmd-Option-1 to Cmd-Option-9 for the first nine, Add Account… and Quit All Accounts….

## Contributing

Issues and pull requests are welcome: see `CONTRIBUTING.md` for the workflow and the rules, `docs/brand/DESIGN.md` for the design tokens. The code is Swift: `Packages/BrainmergeCore` (engine and command line), `Packages/BrainmergeUI` (SwiftUI screens and models), and an Xcode project generated with `xcodegen generate`. Please keep the six points above true.

## License

MIT. See `LICENSE`.

Works with Claude. Not made by Anthropic.
