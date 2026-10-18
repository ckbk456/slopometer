# Architecture

## Implemented MVP

- `App/`: menu-bar accessory app (`LSUIElement`), `AppModel` (settings, polling,
  snapshot publishing), window with Activity, Widgets, and Settings tabs, Keychain token store (several tokens),
  and `Updater` (Sparkle 2; see [Updates](logic/updates.md)).
- `Widget/`: WidgetKit extension that only decodes the shared snapshot.
- `Shared/`: chart views and the widget content view, compiled into both the app and
  the widget so the Widgets tab previews exactly what the widget renders.
- `Sources/SlopometerCore/`: calendar days, PR measurement, quota, GitHub client,
  sync coordinator, GRDB cache, and snapshot builder. No UI code.
- `Tests/SlopometerCoreTests/`: deterministic tests with a fake HTTP transport.
- `project.yml`: app and widget targets depending on the local core package.

Settings › General › "Open at login" registers the app itself as a login item with
`SMAppService.mainApp` (no helper app); macOS owns the setting, so the toggle reads the
system status back, including "waiting for approval" in System Settings. It is off until
turned on. It does not send notifications.

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
