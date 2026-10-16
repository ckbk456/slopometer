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
The normal app window is scaffolding; the background app and widget are planned.

## Intended flow

GitHub (public profile, or GraphQL and search with a token) → sync coordinator
→ source PR records / calendar cache → measurement engine → display snapshot →
menu bar, app window, and (via the App Group container) the widget.

One sync coordinator owns requests, pagination, reconciliation, and rate-limit
backoff. Provider clients return typed records; UI code does not make requests
or invent counts. Keep deduplication/day bucketing in the measurement layer.
Persist source timestamps and identities so metrics can be recomputed.

Use a small number of concrete Swift types and actors for actual concurrency
boundaries. Avoid a service framework, redundant repository abstractions, or a
GraphQL SDK before the real queries justify them. The current cache is a derived
daily-value foundation, not the future source PR-event schema.

SwiftUI owns rendering and settings. The app runs as a menu-bar accessory and
owns polling. The widget extension only decodes the latest snapshot; it never
fetches or reads credentials. All surfaces read the same calculated data.

SQLite/GRDB owns structured cached records and migrations. Preferences own
nonsecret settings; Keychain owns the optional token. There is no hosted
backend in v1.

## Risks to resolve early

The username-only calendar is an undocumented page and may break. Widget reloads
are budgeted by the system. Contribution totals do not provide merged-PR evidence. Test these boundaries before calling the
application a working slop meter.
