# Slopometer scope

## Current bootstrap

- Native macOS 14+ target and checked-in Xcode project generated from `project.yml`.
- Swift 6 package, pinned GRDB dependency, and native chart preview with fixture data.
- A small SQLite cache and trailing-average foundation with deterministic tests.
- Command registry, structural validation, CI configuration, product documents,
  and consolidated manual-testing guides.

Bootstrap completion is a buildable development environment. It is not a
connected GitHub dashboard, a working widget, or a signed release.

## First usable release

- Background menu-bar app, desktop widget, and an app window for inspection and settings.
- One GitHub account by username; account-level measurement by default.
- Username-only tier: account contribution calendar and contribution daily goals from the public profile.
- Optional token tier (one or more tokens, for example one per organization):
  official contribution calendar, PRs opened, authored PRs merged, PR evidence,
  and optional repository filters. Classic tokens only by explicit opt-in. The app states which
  features need a token.
- Grid, column, and line views; 30/90/180/365-day ranges; 7/30-day simple averages.
- Palette presets, custom colors, density, and saved configurations.
- One daily goal: account-wide contributions in either tier, or PRs opened/authored
  PRs merged with a token, repository scope, timezone, and inspectable PR evidence.
  Achievements stay specific to their metric and confirmed source.
- Local cache, pagination, delayed-event reconciliation, rate-limit handling,
  offline/stale indicators, shared widget snapshot, and token storage in Keychain.
- Remove All Data before uninstalling, with a prompt to revoke the deleted tokens on GitHub.
- Optional launch at login and opt-in quota-completion notification.
- Direct download, signed with Developer ID and notarized, with an in-app updater
  (Sparkle 2) that reads a signed static feed at `updates.infinitex.vn`. Release
  builds check on a schedule that can be turned off; updates install only when the
  person accepts them.

## Deferred

Custom desktop-level panel window; selecting other authors or bot accounts;
OAuth or GitHub App sign-in; multiple simultaneous accounts; team features;
GitLab/Bitbucket; commit/review-specific metrics; EMA and other trend models;
custom formulas; export; account sync; commercial billing; Mac App Store
distribution.

## Explicit exclusions

Slopometer does not generate code, manage agents, open or merge PRs, modify
repositories, detect AI writing, grade code, or compare employee productivity.
There is no LLM/API-key requirement, hosted application backend (the update feed
and archives are static files), cloud database, root helper, or Windows/Linux
target in this scope.

## Delivery decisions still open

- Durability of the unofficial public-profile source and its fallback behavior.
- Widget reload frequency achievable within system budgets.
- Additional metrics or providers require a scope decision.

Release identity, decided 2026-10-18: app `vn.infinitex.slopometer`, widget
`vn.infinitex.slopometer.widget`, App Group `5U4584QFCQ.vn.infinitex.slopometer`,
Developer ID team `5U4584QFCQ`, and updates from
`https://updates.infinitex.vn/slopometer/appcast.xml` (Cloudflare R2). These cannot
change after public release without losing installed data and widgets.

License, decided 2026-10-18: free of charge, under the MIT License (`LICENSE`).

The agreed stack is Swift, SwiftUI/AppKit, WidgetKit, Swift Charts, and
SQLite/GRDB. Changes to this scope require explicit human authorization.
Roadmap notes cannot expand it.
