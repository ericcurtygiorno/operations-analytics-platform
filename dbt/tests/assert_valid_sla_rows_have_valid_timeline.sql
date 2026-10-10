select *
from {{ ref('fact_deliveries') }}
where is_valid_for_sla
  and (
      delivered_at is null
      or promised_delivery_at is null
      or shipped_at is null
      or order_at is null
      or delivered_at < shipped_at
      or shipped_at < order_at
  )
