# Security

Brainmerge runs only on your Mac. This page says what it touches, what it never does, how those promises are enforced, and how to report a problem.

## What it touches

| Where | What Brainmerge does there |
| --- | --- |
| `~/Library/Application Support/Brainmerge` | Its own state (the list of accounts and memories), icons, usage cache. No secrets. |
| `~/Applications/Brainmerge/<Name>.app` | One small launcher app per account (ad hoc signed), or a local tinted copy of Claude when you ask for a distinct Dock icon. |
| `~/.claude-<slug>` and `~/.claude` | Claude Code profiles. Brainmerge adds one hook (`brainmerge sync`) to `settings.json`, one marked block to `CLAUDE.md`, and links `projects/<slug>/memory` into the memory. Everything else in them is yours and untouched. |
| `~/Library/Application Support/Claude-<slug>` | Claude's own data folder for each account, created empty; Claude fills it when you log in. Brainmerge only checks whether Claude's storage files exist there, never what is inside. |
| Your memories (`~/Brain` by default) | Markdown notes and a git repository. The hook commits under the account's name. |
| `~/.local/bin/brainmerge` | A symbolic link to the command line inside the app. |

## What it never does

- **No network.** No call to Anthropic, to us, or to anyone: no server, no telemetry, no crash reports, no update check that connects. "Check for updates" opens the releases page in your browser.
- **No credentials.** It never reads, stores or transmits a login, a session cookie, a token or a keychain item. "Connected" is decided from the names of files in Claude's data folder, never from their contents.
- **No account tricks.** No rotation, no switching when a limit is reached, no pooled usage, no automation of the login. Each account logs in by itself, in the official Claude app.
- **No modified Claude by default.** Accounts start the installed Claude through a launcher that only sets two folders. The optional distinct icon copies Claude on your own Mac, after checking that its signature is intact, and is never distributed.
- **No shell.** Programs (git, codesign, cp, iconutil, open) are started with argument lists, never through a shell, so an account name can never become a command.

## How the promises are enforced

- `SecurityGuardTests` scan the whole source tree at every test run: no networking API, no shell interpreter, a single place that starts processes, Claude's storage files named only in one file that may not read contents, no analytics library.
- `NameRules` keep every name to one line without control characters, so names are safe in file names, plists, git authors and Claude's instructions.
- The launcher refuses any configuration that would start something other than a Claude binary inside an app bundle, or use relative folders.
- Dependencies are pinned in `Package.resolved` and watched by Dependabot; CI runs with read-only permissions.
- The app is built with the hardened runtime. Releases are signed ad hoc until a Developer ID is available, which is why macOS asks you to confirm the first opening.

## What to keep in mind

- What you put in a memory, Claude reads at the start of every session, in every account attached to it. Share a memory folder only with people you trust, and never write secrets in it.
- A memory of its own for a work or client account keeps what it learns apart from the shared memory.
- Removing Brainmerge (Settings, or `brainmerge uninstall`) undoes all of the above and deletes none of your data.

## Reporting a vulnerability

If you find a way in which Brainmerge could leak data, run something it should not, or break one of the rules above, please report it privately rather than in a public issue: use "Report a vulnerability" on the Security tab of the repository. You will get an answer within a week, and a fix before any public disclosure.
