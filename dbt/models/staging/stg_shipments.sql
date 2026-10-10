with latest_completed_load as (
    select batches.load_id
    from {{ source('raw', 'ingestion_batches') }} batches
    where batches.status = 'completed'
      and exists (
          select 1
          from {{ source('raw', 'shipments') }} rows
          where rows._load_id = batches.load_id
      )
    order by completed_at desc, started_at desc, load_id desc
    limit 1
),

normalized as (
    select
        _raw_id,
        nullif(trim(shipment_id), '') as shipment_id,
        nullif(trim(order_id), '') as order_id,
        nullif(trim(carrier_name), '') as carrier_name,
        nullif(trim(shipped_at), '')::timestamp as shipped_at,
        nullif(trim(promised_delivery_at), '')::timestamp as promised_delivery_at,
        nullif(trim(delivered_at), '')::timestamp as delivered_at,
        lower(nullif(trim(delivery_status), '')) as delivery_status,
        nullif(trim(delivery_attempts), '')::integer as delivery_attempts,
        source_batch_id,
        _ingested_at,
        _source_file,
        _source_file_hash,
        _source_row_number,
        _load_id
    from {{ source('raw', 'shipments') }}
    where _load_id = (select load_id from latest_completed_load)
),

flagged as (
    select
        *,
        shipment_id is null as is_missing_shipment_id,
        carrier_name not in (
            'Aurora Express', 'BluePeak Logistics', 'Cedar Freight', 'Delta Parcel'
        ) as is_unknown_carrier,
        delivered_at is not null and delivered_at < shipped_at as is_delivery_before_shipment,
        delivery_status = 'delivered' and delivered_at is null as is_delivered_without_timestamp,
        promised_delivery_at <= shipped_at as is_invalid_promise,
        delivery_attempts is null or delivery_attempts < 0 as is_invalid_attempt_count
    from normalized
)

select
    *,
    not (
        is_missing_shipment_id
        or is_unknown_carrier
        or is_delivery_before_shipment
        or is_delivered_without_timestamp
        or is_invalid_promise
        or is_invalid_attempt_count
    ) as is_valid_shipment_record
from flagged
