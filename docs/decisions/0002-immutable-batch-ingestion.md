# ADR 0002: Immutable, idempotent batch ingestion

- Status: Accepted
- Date: 2026-10-06

## Context

The local pipeline must be safe to retry and must preserve enough lineage to explain every raw row.
The same logical files can also acquire different line endings across Windows and Linux containers.

## Decision

Identify a logical bundle from canonical content hashes, store immutable batch metadata, and enforce
raw uniqueness by source file hash and row number. Downstream staging reads the latest completed
batch and ignores incomplete or already-completed batches with no new rows.

## Consequences

Retries are idempotent, cross-platform line endings do not create false batches, and every raw row
retains file and load lineage. The current behavior is replacement-oriented; late-arriving merge
semantics are intentionally deferred.
