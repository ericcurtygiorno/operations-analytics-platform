# ADR 0004: Power BI Project format

- Status: Accepted
- Date: 2026-10-07

## Context

A binary-only report would hide semantic-model and visual changes from code review and make the
portfolio harder to inspect without Power BI Desktop.

## Decision

Store the report in PBIP/PBIR/TMDL source format. Keep explicit DAX measures in a dedicated
`_Measures` table, organize them in display folders, disable implicit measures, and version the five
report pages, navigation, bookmarks, and theme.

## Consequences

The semantic model and report structure are diffable and auditable. Desktop remains necessary for a
full refresh and rendered interaction review, so a static screenshot gallery is also published.
