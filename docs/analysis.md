# Reproducible Operational Analysis

This analysis is generated from `marts.fact_deliveries` by
`python -m src.operations_analytics.evidence`. All findings describe the deterministic
synthetic dataset; they do not claim measured impact in a real company.

## Scope

- Shipment grain: 756 rows.
- Promised-delivery period: 2024-01-08 through
  2025-07-06.
- SLA-eligible population: 667 shipments.
- Governed exclusions: 89 shipments
  (11.77%).

## Executive findings

1. **Service reliability is the main simulated risk.** The full-period on-time delivery
   rate is 47.38%, and late eligible shipments average
   2.15 days beyond promise.
2. **Carrier performance is materially uneven.** BluePeak Logistics has the
   lowest eligible on-time rate at 40.0%, versus
   54.01% for Delta Parcel.
   This is a 14.01 percentage-point spread.
3. **Central-West is the clearest regional hotspot.** Its on-time rate is
   43.42%, compared with
   53.33% in Southeast.
4. **Exceptions are frequent and operationally concentrated.**
   48.54% of shipments have at least one exception. The largest
   recorded reason is `capacity`, affecting
   101 shipments (27.52%
   of shipments with a recorded failure reason).
5. **First-attempt completion remains a useful counterbalance.**
   80.46% of delivered shipments complete on the first
   attempt, suggesting that the synthetic delays are not explained solely by repeat attempts.

These findings identify where a real operation would investigate capacity, carrier governance,
regional constraints, and promise-setting. No improvement or financial benefit is asserted.

## Carrier benchmark

| Carrier | Shipments | SLA eligible | On-time % | Avg late days | Exception % | Avg freight |
|---|---|---|---|---|---|---|
| BluePeak Logistics | 166 | 150 | 40.0 | 2.04 | 56.63 | 30.4 |
| Cedar Freight | 185 | 167 | 43.11 | 2.11 | 51.89 | 28.24 |
| Aurora Express | 190 | 163 | 50.92 | 2.26 | 42.11 | 29.47 |
| Delta Parcel | 209 | 187 | 54.01 | 2.22 | 43.54 | 29.1 |

## Regional benchmark

| Region | Shipments | SLA eligible | On-time % | Exception % |
|---|---|---|---|---|
| Central-West | 163 | 152 | 43.42 | 55.21 |
| South | 201 | 173 | 45.66 | 48.26 |
| Northeast | 186 | 162 | 46.3 | 49.46 |
| Southeast | 194 | 180 | 53.33 | 44.85 |

## Service-type diagnostic

| Service type | Shipments | On-time % | Order-to-ship hours | Ship-to-delivery days |
|---|---|---|---|---|
| express | 145 | 42.97 | 38.11 | 3.11 |
| economy | 160 | 45.77 | 43.13 | 8.13 |
| standard | 439 | 49.37 | 38.04 | 5.01 |

## Distribution-center diagnostic

| Distribution center | Shipments | On-time % | Order-to-ship hours |
|---|---|---|---|
| DC-SAO | 230 | 45.89 | 42.38 |
| DC-REC | 242 | 46.98 | 35.7 |
| DC-CWB | 272 | 48.98 | 39.49 |

## Recorded failure reasons

| Failure reason | Affected shipments | Share % |
|---|---|---|
| capacity | 101 | 27.52 |
| customer_unavailable | 97 | 26.43 |
| weather | 93 | 25.34 |
| address_issue | 76 | 20.71 |

## Interpretation boundaries

- The data is synthetic and deterministic.
- On-time delivery is not labeled OTIF because item-level completeness is not proven.
- Correlation in these descriptive cuts does not establish causality.
- Invalid rows remain visible in the fact table and are excluded from governed SLA metrics.
