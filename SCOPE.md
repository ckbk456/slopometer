# Slopometer scope

## Current bootstrap

- Native macOS 14+ target and checked-in Xcode project generated from `project.yml`.
- Swift 6 package, pinned GRDB dependency, and native chart preview with fixture data.
- A small SQLite cache and trailing-average foundation with deterministic tests.
- Command registry, structural validation, CI configuration, product documents,
  and consolidated manual-testing guides.

Bootstrap completion is a buildable development environment. It is not a
connected GitHub dashboard, a proven desktop panel, or a signed release.

## First usable release

- macOS desktop panel, menu-bar controls, and an expanded inspector/settings window.
- One GitHub account, selected repositories and authors, with explicit bot selection.
- GitHub account contribution calendar plus PR-opened and authored-PR-merged metrics.
- Grid, column, and line views; 30/90/365-day ranges; 7/30-day simple averages.
- Palette presets, custom colors, opacity, density, and saved configurations.
- One daily PR goal with target, metric, scope, timezone, and inspectable PR evidence.
- Local cache, pagination, delayed-event reconciliation, rate-limit handling,
  offline/stale indicators, and credential storage in Keychain.
- Optional launch at login and opt-in quota-completion notification.

## Deferred

Native WidgetKit summary; multiple simultaneous panels/accounts; team features;
GitLab/Bitbucket; commit/review-specific metrics; EMA and other trend models;
custom formulas; export; account sync; commercial billing; public updater.

## Explicit exclusions

Slopometer does not generate code, manage agents, open or merge PRs, modify
repositories, detect AI writing, grade code, or compare employee productivity.
There is no LLM/API-key requirement, hosted application backend, cloud database,
root helper, or Windows/Linux target in this scope.

## Delivery decisions still open

- Dedicated GitHub sign-in design and private-repository permission model.
- Final desktop-level behavior supported across target macOS versions.
- License, release identity, signing/notarization, and public distribution channel.
- Additional metrics or providers require a scope decision.

The agreed stack is Swift, SwiftUI/AppKit, Swift Charts, and SQLite/GRDB. Changes
to this scope require explicit human authorization. Roadmap notes cannot expand it.
