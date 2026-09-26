# Contributing to Brainmerge

Thank you for looking at this. Brainmerge is small, native and opinionated; contributions that keep it that way are very welcome.

## The rules that cannot change

The project exists because it stays within Anthropic's terms. Every change must keep the six points of the README's "Why this stays within Anthropic's terms" true: no credential or token is ever read, stored or sent (the one allowed read of Claude Code's account entry, `ClaudeCodeAccount`, decodes its three display fields and nothing else, and the email is never stored); no account rotation, switching or pooling; no network call; Anthropic's binaries are never redistributed; the Claude app stays untouched by default; one account is one person. A pull request that crosses one of these lines will be closed, however good the code is.

## How to propose a change

1. Open an issue first for anything bigger than a typo, so we agree on the direction before you spend time.
2. Fork the repository and create a branch from `main`.
3. Write a test that fails, then the code that makes it pass. Core logic lives in `Packages/BrainmergeCore` (`swift test --package-path Packages/BrainmergeCore`), screens and models in `Packages/BrainmergeUI` (`swift test --package-path Packages/BrainmergeUI`). Tests never touch the real home folder: use `BRAINMERGE_HOME` and the fixtures in `BrainmergeTestSupport`. The website (`site/`) has its own tests, run with Node and no dependency: `node --test Tests/site/motion.test.cjs`. Its How it works diagram is generated: edit `scripts/site-flow/gen-flow.cjs`, then run `python3 scripts/site-flow/inject-flow.py`.
4. Build the app with `xcodegen generate` then `xcodebuild -project Brainmerge.xcodeproj -scheme Brainmerge build`, or open the generated project in Xcode 26.
5. Open a pull request against `main`. Describe what changes for a person using the app, not only for the code. The CI runs the three test suites.

## Style

- Swift 6, strict concurrency. Models are `@MainActor @Observable`; heavy work goes through `AppModel.perform`.
- Everything visible derives from `Theme.swift` (see `docs/brand/DESIGN.md`). No hard-coded colors in views.
- Copy is in plain English, sentence case, and says what happens ("Quit and open"), never how it is built.
- No em dashes in visible text.
- Commits: one change per commit, message in the imperative.

## Reporting a security issue

See `SECURITY.md`. Please do not open a public issue for a vulnerability.
