# ADR 0001: Shipment-grain star schema

- Status: Accepted
- Date: 2026-10-06

## Context

The decision questions focus on SLA performance, delivery lifecycle, carriers, regions, exceptions,
freight, and data quality. The source currently represents one regular shipment per order and has no
order-line grain.

## Decision

Use `fact_deliveries` at one row per shipment with conformed date, customer, carrier,
distribution-center, location, and service-type dimensions. Keep natural shipment and order IDs in
the fact for traceability. Use promised delivery date as the active analytical calendar.

## Consequences

The model is simple for Power BI, metrics share a clear denominator, and quality exceptions remain
auditable. A separate order fact is deferred until split shipments, partial fulfilment, cancellation,
or order-line analysis creates a distinct business grain.
