# Architecture

## Implemented bootstrap

- `App/`: SwiftUI app window, menu-bar commands using AppKit, fixed sample data,
  heatmap grid, and Swift Charts column/line previews.
- `Sources/SlopometerCore/`: UI-independent trailing averages and GRDB cache.
- `Tests/SlopometerCoreTests/`: calculation and cache contracts.
- `Package.swift`: core package and exact GRDB dependency.
- `project.yml`: app target depending on that local core package.

The preview reads fixtures in memory. It does not write a production cache,
request GitHub credentials, call GitHub, register login launch, or send notifications.
The normal app window is scaffolding; AppKit desktop-panel behavior is phase 1.

## Intended flow

GitHub API → sync coordinator → source PR records / calendar cache → measurement
engine → shared snapshots → desktop panel, inspector, and quota display.

One sync coordinator owns requests, pagination, reconciliation, and rate-limit
backoff. Provider clients return typed records; UI code does not make requests
or invent counts. Keep deduplication/day bucketing in the measurement layer.
Persist source timestamps and identities so metrics can be recomputed.

Use a small number of concrete Swift types and actors for actual concurrency
boundaries. Avoid a service framework, redundant repository abstractions, or a
GraphQL SDK before the real queries justify them. The current cache is a derived
daily-value foundation, not the future source PR-event schema.

SwiftUI owns rendering and settings. A small AppKit controller will own window
level, focus, Spaces, and monitor restoration. This boundary keeps platform
behavior separate from counts. Both app surfaces read the same calculated data.

SQLite/GRDB owns structured cached records and migrations. Preferences own
nonsecret appearance/placement settings; Keychain owns credentials. There is no
hosted backend in v1. Optional future WidgetKit reads a published snapshot; it
does not own the main sync loop.

## Risks to resolve early

Desktop-level windows may behave differently across Spaces/OS versions. Private
repository access needs a deliberate auth/permission design. Contribution totals
do not provide merged-PR evidence. Test these boundaries before calling the
application a working slop meter.
