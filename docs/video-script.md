# Walkthrough Script (60–90 seconds)

Recording is intentionally deferred to the final cross-portfolio video batch. This script keeps the
Project 1 story ready and consistent.

## Suggested narration

“This is the Operations Analytics Platform, an end-to-end logistics case built with synthetic data.
The business problem is simple: operations needs to monitor delivery SLAs without mixing real
service failures with invalid data.

The pipeline generates deterministic CSV and JSON events, validates and ingests them idempotently
into PostgreSQL, then uses dbt to build a shipment-grain star schema with automated quality tests.
Airflow orchestrates the real workflow, Docker makes it reproducible, and GitHub Actions runs the
same validation contracts.

In Power BI, the Executive Overview compares current and prior YTD performance. The sample shows a
47.38 percent overall on-time rate, with Delta Parcel leading the named carriers and Central-West
showing the weakest regional result. The Exceptions and Data Quality pages explain why shipments
fail and which records are excluded from the SLA denominator.

The repository includes the PBIP source, explicit DAX measures, architecture decisions, test
catalog, machine-readable evidence, and one-command local execution. The data is entirely synthetic,
so the complete project is safe to inspect and reproduce.”

## Recording checklist

- Start on the repository README and architecture diagram.
- Show the Executive Overview, then one exception and one quality interaction.
- Briefly show the Airflow graph and passing evidence; do not scroll through code.
- Keep the pointer still while speaking and remain between 60 and 90 seconds.
- End on the repository links and author contact section.
