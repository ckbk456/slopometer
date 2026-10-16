# Research: GitHub data sources for account-level measurement

Probed 2026-10-16 against one real account with mostly private activity. Counts
are evidence for that account on that date, not guarantees. No credential values
were recorded. Informs the account-level, optional-token contract in [SPEC](../../SPEC.md).

| Source | Auth | Observed result | Limit observed |
| --- | --- | --- | --- |
| Public profile calendar (`github.com/users/<login>/contributions`, HTML) | None | 370 days; total equal to the GraphQL calendar, including private activity as anonymous counts | Undocumented page, no API contract |
| Public events API (`/users/<login>/events/public`) | None | 38 events reaching back only 13 days; public repositories only | 60 requests/hour; at most 90 days or 300 events |
| PR search (`author:<login> type:pr`) | None | 14 PRs, public repositories only | 10 requests/minute |
| PR search, same query | Token with private repository read | 890 PRs; 43 merged in the last week across 10 repositories | 30 requests/minute; 1,000 results per query |
| GraphQL `contributionsCollection` | Any token | Same calendar total; 2,359 of 2,389 contributions were restricted (private) | 5,000 points/hour |

## Conclusions

- Account-level contributions work without a token, but only through an
  undocumented page. Treat it as an unofficial source with a visible label.
- PR metrics without a token would cover about 1.5% of this account's PRs, so
  PR tracking, evidence, and quotas require a token.
- A user-pasted read-only token is sufficient. OAuth is not needed for a
  personal tool and is deferred.
- The profile page and GraphQL placed 8 of 370 days' activity on an adjacent day
  (pair sums matched), consistent with different day-boundary timezones. A
  series must not mix the two sources.
- The 1,000-result search cap is manageable by querying in date windows; a
  395-day backfill (365-day range plus 30-day warm-up) needs about 13 monthly
  windows per PR metric for this account.

## Not yet verified

- Which timezone each calendar source uses for day labels.
- Fine-grained token permissions needed for PR search across organization repositories.
- Behavior when the profile hides private contributions.
