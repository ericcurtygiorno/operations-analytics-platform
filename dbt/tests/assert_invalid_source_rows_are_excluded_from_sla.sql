select *
from {{ ref('fact_deliveries') }}
where is_valid_for_sla
  and (
      is_orphan_order
      or is_unknown_carrier
      or is_delivery_before_shipment
      or is_delivered_without_timestamp
      or has_invalid_order
  )
