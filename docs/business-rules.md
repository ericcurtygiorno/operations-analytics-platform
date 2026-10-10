# Initial Business Rules

## Analytical grain

- `fact_deliveries` has one row per shipment.
- The initial synthetic scenario emits one regular shipment per order, but the model does not assume that this will remain true.
- Delivery events remain at event grain in staging and are summarized before joining to the shipment grain.

## SLA eligibility

A shipment is eligible for the initial on-time-delivery KPI only when:

- the shipment has a matching valid order;
- carrier, timestamps, promise, attempts, and identifiers pass the documented checks;
- status is `delivered`;
- both promised and actual delivery timestamps are available.

Invalid records remain in `fact_deliveries` with quality flags. They are not silently deleted and are excluded only from SLA denominators.

## On-time delivery

For an SLA-eligible shipment:

```text
is_on_time = delivered_at <= promised_delivery_at
```

The initial KPI is not labeled OTIF because the current sources do not yet prove item-level completeness. It is honestly labeled **On-Time Delivery Rate**.

## Deduplication

Exact source reprocessing is prevented by the raw unique key `(source_file_hash, source_row_number)`. In staging, duplicate non-empty `order_id` values within a source batch retain the earliest raw row and expose `duplicate_rank` for traceability. Rows with missing identifiers are not collapsed together.

## Time handling

The first synthetic source version emits naive local timestamps. All comparisons use the same assumed business timezone. Explicit timezone-aware source contracts are a planned refinement before production-like scheduling.
