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
- Username-only tier: account contribution calendar from the public profile.
- Optional token tier: official contribution calendar, PRs opened, authored PRs
  merged, PR evidence, and optional repository filters. The app states which
  features need a token.
- Grid, column, and line views; 30/90/365-day ranges; 7/30-day simple averages.
- Palette presets, custom colors, density, and saved configurations.
- One daily PR goal (token tier) with target, metric, scope, timezone, and
  inspectable PR evidence.
- Local cache, pagination, delayed-event reconciliation, rate-limit handling,
  offline/stale indicators, shared widget snapshot, and token storage in Keychain.
- Optional launch at login and opt-in quota-completion notification.

## Deferred

Custom desktop-level panel window; selecting other authors or bot accounts;
OAuth or GitHub App sign-in; multiple simultaneous accounts; team features;
GitLab/Bitbucket; commit/review-specific metrics; EMA and other trend models;
custom formulas; export; account sync; commercial billing; public updater.

## Explicit exclusions

Slopometer does not generate code, manage agents, open or merge PRs, modify
repositories, detect AI writing, grade code, or compare employee productivity.
There is no LLM/API-key requirement, hosted application backend, cloud database,
root helper, or Windows/Linux target in this scope.

## Delivery decisions still open

- Durability of the unofficial public-profile source and its fallback behavior.
- Widget reload frequency achievable within system budgets.
- License, release identity (bundle ID, App Group, signing team), notarization,
  and public distribution channel.
- Additional metrics or providers require a scope decision.

The agreed stack is Swift, SwiftUI/AppKit, WidgetKit, Swift Charts, and
SQLite/GRDB. Changes to this scope require explicit human authorization.
Roadmap notes cannot expand it.
