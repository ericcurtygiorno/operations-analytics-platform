# Test Catalog

The project uses complementary tests at the source, ingestion, transformation, orchestration, and
repository levels. Each check protects a named failure mode.

## Python tests

Run with:

```powershell
python -m unittest discover -s tests -v
```

| Area | Protected behavior |
|---|---|
| Generator determinism | The same configuration produces the same logical source files and manifest |
| Generator contracts | Required columns, types, and anomaly counts remain stable |
| Ingestion idempotency | Retrying the same logical bundle does not duplicate raw rows |
| Cross-platform hashing | CRLF/LF differences do not create a new logical batch |
| Contract rejection | Invalid source structures fail before partial publication |
| Evidence publication | SQL result sets and dbt outcomes are serialized consistently |

The current suite contains ten passing tests across generator, ingestion, evidence, and
documentation-link coverage.

## dbt tests

`dbt build` currently executes 40 tests alongside 11 models.

### Generic tests

- unique and not-null business keys;
- accepted values for lifecycle status fields;
- relationships from `fact_deliveries` to each dimension;
- required fact fields and governed flags.

### Custom tests

| Test | Assertion |
|---|---|
| `assert_invalid_source_rows_are_excluded_from_sla` | Known invalid source rows never enter the SLA denominator |
| `assert_valid_sla_rows_have_valid_timeline` | Every SLA-eligible row has a chronologically valid lifecycle |

## Pipeline and orchestration checks

- The containerized pipeline regenerates sources, ingests raw data, executes `dbt build`, and
  publishes evidence against a clean database.
- The Airflow validation command first checks import errors, then executes a full test DAG run.
- The DAG contract verifies its four real tasks, schedule, dependency order, parameters, retries,
  timeout, and failure behavior.
- `docker compose config --quiet` validates the Compose contract before runtime.

## Executable evidence

[`stage-1-3-evidence.json`](../artifacts/evidence/stage-1-3-evidence.json) records the latest batch,
row counts, model-integrity assertions, quality flags, operational findings, and dbt results. The
verified artifact reports:

- 756 fact rows and 756 distinct shipment IDs;
- zero invalid rows leaking into the SLA denominator;
- zero invalid timelines leaking into the SLA denominator;
- 11 successful models and 40 passing dbt tests.

## CI mapping

| CI check | Failure caught |
|---|---|
| Python lint | Unsafe or inconsistent Python changes |
| Python tests | Generator, ingestion, or evidence regressions |
| dbt build | SQL compilation, model, relationship, and business-rule failures |
| Integration/evidence | Broken vertical flow or claims that no longer match the database |
| Compose validation | Invalid service configuration |
| Airflow import/contract | Broken DAG loading or orchestration structure |

Hosted CI observation remains a publication-stage check. The same commands have been executed
successfully locally.
