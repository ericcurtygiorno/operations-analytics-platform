# Limitations and Next Steps

This document makes the project's boundaries explicit so that the repository does not imply more
than it proves.

## Current limitations

- All companies, people, transactions, and operational results are synthetic.
- The source uses a replacement-oriented immutable batch, not a streaming or change-data-capture
  feed.
- The current scenario is effectively one shipment per order and has no item-level fulfilment fact.
- Dimensions are Type 1 because the source does not contain meaningful attribute history.
- Airflow uses `standalone` and `LocalExecutor`; it demonstrates orchestration behavior but is not a
  production deployment topology.
- Power BI refresh is local and depends on the PostgreSQL service at `localhost:55432`.
- The interactive Power BI Service report is publicly available and contains synthetic data only;
  the static screenshot gallery remains the stable fallback and repository-native evidence.
- Findings describe associations in generated data. They do not prove causality, savings, or a
  measured intervention effect.

## Deliberate tradeoffs

- Invalid rows remain visible in the analytical fact with quality flags. Silently dropping them
  would hide the size and nature of data-quality risk.
- A single shipment fact avoids a decorative second fact that would duplicate order information.
- The project keeps raw JSON delivery events but aggregates them before the mart because the current
  dashboard does not require scan-level sequence analysis.
- Docker and PowerShell optimize for the stated Windows portfolio environment; the Python and dbt
  components remain portable.

## Credible next steps

1. Add split shipments and line-level fulfilment before introducing `fact_orders` or
   `fact_order_lines`.
2. Implement incremental late-arriving merges and effective-dated dimensions when the source can
   represent those behaviors honestly.
3. Add service-level alerting only after a notification channel and operational ownership model are
   defined.
4. Record the 60–90 second walkthrough during the final cross-portfolio release batch.
