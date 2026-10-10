# Validation Evidence

## 2026-10-06 — PostgreSQL, dbt, and Power BI validation

Environment:

- PostgreSQL `17-alpine` in the project Compose service;
- dbt Core `1.12.5`;
- dbt PostgreSQL adapter `1.11.0`;
- Python `3.11.9`.

Verified results:

- 6 Python unit and contract tests passed;
- latest raw ingestion loaded 759 order rows, 756 shipment rows, and 1,812 event rows;
- immediate reprocessing returned `skipped` for the same deterministic `load_id`;
- staging models select the latest completed immutable raw batch, preventing duplicate business keys when a new deterministic dataset supersedes an earlier batch;
- staging deduplication produced 750 order records from 759 raw rows;
- dbt built 11 models and passed 40 generic and custom tests;
- dbt result: `PASS=51 WARN=0 ERROR=0 SKIP=0`;
- `marts.fact_deliveries` contains 756 shipment-grain rows spanning promised dates from 2024-01-08 through 2025-07-06;
- 667 shipments are eligible for the full-period SLA calculation;
- the reproducible full-period on-time delivery rate is 47.38%;
- the January–July comparison is 273 shipments and 49.2% on-time delivery for 2025 versus 274 shipments and 44.4% for 2024;
- the Power BI semantic model loaded 8 tables, 100 explicit measures, and 9 relationships;
- the Power BI model completed a full refresh without DAX or connection errors;
- all five report pages were captured successfully after refresh: 185 report components and 5 reset bookmarks. The components include the layered elements used to render 20 visually unified KPI cards, their calculation-help icons, and the reusable branded header;
- year, month, and service-type slicers are present on every page and suppress blank members; KPI comparisons use a single selected year when available and otherwise anchor to the latest year;
- all 20 KPI information icons have visual tooltips explicitly enabled, use the KPI-specific plain-language definition, and suppress the internal helper-measure label from the tooltip display;
- all 20 KPI card backgrounds use the same container-clipped fill and rounded border, preventing the background from protruding beyond the top corner outlines;
- Executive Overview is the active landing page; the other four pages are hidden from report tabs and remain available through in-report navigation;
- the Executive Overview uses accessible carrier and regional bar rankings, and the Carriers & Regions scorecard has a verified 20-pixel logical gap from the adjacent visuals.

Quality observations:

- 6 source shipments use an unknown carrier;
- 6 have a delivery timestamp before shipment;
- 6 are marked delivered without a delivery timestamp;
- 12 shipment rows have no matching staged order: 6 explicit orphan anomalies and 6 relationships broken by the intentional missing order identifiers.

Rendered evidence is stored in `dashboard/validation/final-polish`.

## 2026-10-09 — Stage 1.3 modeling, analysis, and quality evidence

Verified results:

- the complete vertical slice was rerun successfully against PostgreSQL `17-alpine`;
- deterministic ingestion returned `skipped` for the previously completed immutable load,
  confirming idempotent reprocessing;
- dbt executed 11 models and 40 generic/custom tests with
  `PASS=51 WARN=0 ERROR=0 SKIP=0`;
- 9 Python unit and contract tests passed, including the dbt evidence parser and the
  cross-platform manifest-hash regression test;
- fact-grain reconciliation returned 756 rows and 756 distinct shipment identifiers;
- no invalid quality row or invalid timeline leaked into the SLA denominator;
- 667 of 756 shipments are SLA eligible and the governed full-period exclusion rate is 11.77%;
- the reproducible full-period on-time delivery rate is 47.38%, with an average 2.15-day delay
  among late eligible shipments;
- BluePeak Logistics has the lowest eligible carrier on-time rate at 40.00%, versus 54.01% for
  Delta Parcel;
- Central-West has the lowest regional on-time rate at 43.42%, while Southeast has 53.33%;
- `capacity` is the largest recorded failure category at 101 affected shipments;
- `scripts/run_vertical_slice.ps1` now regenerates both human-readable evidence and the
  machine-readable `artifacts/evidence/stage-1-3-evidence.json` artifact after `dbt build`.

Evidence:

- operational findings: `docs/analysis.md`;
- quality and reconciliation report: `docs/quality-report.md`;
- full query output: `artifacts/evidence/stage-1-3-evidence.json`;
- reusable SQL query pack: `analysis/operational_analysis.sql`.

## 2026-10-09 — Stage 1.4 reproducible environment

Verified results:

- the Docker image installs pinned Python, PostgreSQL, dbt Core, and dbt PostgreSQL adapter
  dependencies without requiring a host Python environment;
- the Compose `pipeline` service runs generation, raw ingestion, `dbt build`, and evidence
  generation as one reproducible workflow;
- the containerized workflow completed successfully against the existing development database,
  reused the immutable load, built 11 models, and returned
  `PASS=51 WARN=0 ERROR=0 SKIP=0`;
- a second Compose project named `oap-clean-check` was created with a new empty PostgreSQL volume
  and isolated host port `55433` to simulate first-time setup;
- the clean run loaded 759 orders, 756 shipments, and 1,812 delivery events, built the 756-row
  delivery fact, passed all 51 dbt nodes, and generated evidence successfully;
- the disposable clean-test container, network, and volume were removed after verification; the
  regular development database was preserved;
- bootstrap, safe reset, and failure-recovery procedures are documented in `docs/setup.md` and
  `docs/troubleshooting.md`.

Regression found and corrected during clean-environment validation:

- Windows and Linux line endings initially produced different byte-level hashes for the same JSON
  manifest. That could create a completed ingestion batch with no source rows after cross-platform
  reprocessing;
- load identity now uses canonical JSON content, generated manifests explicitly use LF line endings,
  ingestion reuses only a completed batch that actually owns all expected raw rows, and staging plus
  evidence queries ignore empty completed batches;
- the regression is covered by `test_manifest_line_endings_do_not_change_load_id` and was verified
  in both the host and clean-container paths.

## 2026-10-09 — Stage 1.5 Airflow and CI

Airflow verification:

- the official Airflow `3.3.2` image was built with a separate Python virtual environment for dbt
  and pipeline dependencies;
- the DAG loaded with zero import errors and exposed the four expected tasks in a strict dependency
  chain: generation → ingestion → dbt build/tests → evidence publication;
- the DAG defines a daily 06:00 UTC schedule, `catchup=False`, one active run, two retries per task,
  two-minute retry delay, twenty-minute timeout, validated runtime parameters, and a failure callback;
- `airflow dags test operations_analytics_pipeline 2026-10-09` executed the real pipeline and ended
  in `success`;
- the run regenerated 759 orders, 756 shipments, and 1,812 events; reused the immutable completed
  batch; rebuilt the 756-row delivery fact; passed all 51 dbt nodes; and published evidence;
- command failures use `check=True`, retain the failed task state, emit actionable run/task context,
  and prevent downstream execution;
- the first validation exposed a non-root metadata-volume permission error. The final Compose design
  now includes an explicit `airflow-init` service, and the repeated full DAG run passed.

CI verification:

- `.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual dispatch;
- its integration job installs pinned tooling, lints Python, runs unit tests, generates deterministic
  sources, performs raw ingestion, executes `dbt build`, regenerates evidence, validates Compose,
  and uploads dbt/quality evidence even when a prior step fails;
- its Airflow job builds the same container, initializes the metadata volume, checks import errors,
  and lists the parsed DAG;
- the local equivalents of lint, 9 Python tests, Compose validation, the database/dbt integration,
  and the Airflow DAG contract were executed successfully. The hosted workflow itself remains to be
  observed after the repository is published to GitHub.
