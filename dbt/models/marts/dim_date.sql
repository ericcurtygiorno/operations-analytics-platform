with bounds as (
    select
        min(order_at)::date as min_date,
        max(coalesce(delivered_at, promised_delivery_at, shipped_at))::date as max_date
    from {{ ref('int_deliveries_enriched') }}
),

dates as (
    select generate_series(min_date, max_date, interval '1 day')::date as date_day
    from bounds
)

select
    to_char(date_day, 'YYYYMMDD')::integer as date_key,
    date_day,
    extract(year from date_day)::integer as year,
    extract(quarter from date_day)::integer as quarter,
    extract(month from date_day)::integer as month_number,
    to_char(date_day, 'Mon') as month_name,
    extract(isodow from date_day)::integer as iso_day_of_week,
    to_char(date_day, 'Dy') as day_name,
    extract(isodow from date_day) in (6, 7) as is_weekend
from dates
