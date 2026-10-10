FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY pyproject.toml README.md ./

RUN python -m pip install --no-cache-dir \
    psycopg2-binary==2.9.13 \
    dbt-core==1.12.5 \
    dbt-postgres==1.11.0

COPY src ./src
RUN python -m pip install --no-cache-dir --no-deps .

COPY config ./config
COPY dbt ./dbt
COPY dbt_project.yml ./
COPY sample_data ./sample_data

CMD ["python", "-m", "src.operations_analytics.evidence", "--help"]
