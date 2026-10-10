# ADR 0003: Lightweight local Airflow orchestration

- Status: Accepted
- Date: 2026-10-09

## Context

The project needs to prove real scheduling, dependencies, retries, parameters, logging, and failure
propagation without presenting a laptop-scale environment as a production cluster.

## Decision

Run Airflow 3.3 in a dedicated container using `airflow standalone` and `LocalExecutor`. Keep dbt and
pipeline dependencies in an isolated virtual environment inside the image. Orchestrate the same
commands used by the verified command-line workflow.

## Consequences

The DAG is executable and easy to reproduce locally. The topology is intentionally unsuitable for
high availability or distributed production workloads, and the documentation states that boundary.
