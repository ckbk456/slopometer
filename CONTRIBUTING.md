# Contributing to Slopometer

Start with [AGENTS](AGENTS.md), [SPEC](SPEC.md), [SCOPE](SCOPE.md), and the
[development guide](docs/DEVELOPMENT.md). Propose product-contract changes before
implementing them. A public source repository currently has no selected license;
external contribution terms must be settled before accepting contributions.

Use one task branch/worktree per concern, preserve others' work, and keep fixtures
obviously separate from provider data. Run `make validate` once the changes are
ready. Include relevant [manual-testing](testing/MANUAL%20TO-DO/README.md) status,
update the owning [logic guide](docs/README.md), and use the PR template when PR
publication is authorized. Do not include credentials, local databases, build
artifacts, or machine-specific configuration.
