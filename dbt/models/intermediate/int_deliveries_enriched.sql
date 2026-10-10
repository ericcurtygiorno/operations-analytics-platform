with shipments as (
    select * from {{ ref('stg_shipments') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

event_summary as (
    select
        shipment_id,
        count(*) as event_count,
        count(*) filter (where event_type = 'delivery_exception') as exception_count,
        min(event_at) filter (where event_type = 'delivery_exception') as first_exception_at,
        max(failure_reason) filter (where event_type = 'delivery_exception') as failure_reason
    from {{ ref('stg_delivery_events') }}
    group by shipment_id
)

select
    shipments.shipment_id,
    shipments.order_id,
    orders.customer_id,
    orders.order_at,
    orders.distribution_center_id,
    orders.destination_region,
    orders.service_type,
    orders.quantity,
    orders.weight_kg,
    orders.freight_amount,
    shipments.carrier_name,
    shipments.shipped_at,
    shipments.promised_delivery_at,
    shipments.delivered_at,
    shipments.delivery_status,
    shipments.delivery_attempts,
    coalesce(event_summary.event_count, 0) as event_count,
    coalesce(event_summary.exception_count, 0) as exception_count,
    event_summary.first_exception_at,
    event_summary.failure_reason,
    orders.order_id is null as is_orphan_order,
    shipments.is_unknown_carrier,
    shipments.is_delivery_before_shipment,
    shipments.is_delivered_without_timestamp,
    coalesce(not orders.is_valid_order_record, true) as has_invalid_order,
    extract(epoch from (shipments.shipped_at - orders.order_at)) / 3600.0 as order_to_ship_hours,
    extract(epoch from (shipments.delivered_at - shipments.shipped_at)) / 3600.0 as ship_to_delivery_hours,
    extract(epoch from (shipments.delivered_at - shipments.promised_delivery_at)) / 86400.0 as delivery_delay_days,
    case
        when shipments.delivery_status = 'delivered'
            and shipments.delivered_at is not null
            and shipments.promised_delivery_at is not null
        then shipments.delivered_at <= shipments.promised_delivery_at
    end as is_on_time,
    shipments.is_valid_shipment_record
        and coalesce(orders.is_valid_order_record, false)
        and shipments.delivery_status = 'delivered'
        and shipments.delivered_at is not null
        and shipments.promised_delivery_at is not null
        as is_valid_for_sla,
    shipments.source_batch_id,
    shipments._load_id,
    shipments._ingested_at
from shipments
left join orders
    on shipments.order_id = orders.order_id
left join event_summary
    on shipments.shipment_id = event_summary.shipment_id
