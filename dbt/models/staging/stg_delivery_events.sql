with latest_completed_load as (
    select batches.load_id
    from {{ source('raw', 'ingestion_batches') }} batches
    where batches.status = 'completed'
      and exists (
          select 1
          from {{ source('raw', 'delivery_events') }} rows
          where rows._load_id = batches.load_id
      )
    order by completed_at desc, started_at desc, load_id desc
    limit 1
)

select
    _raw_id,
    nullif(trim(event_id), '') as event_id,
    nullif(trim(shipment_id), '') as shipment_id,
    lower(nullif(trim(event_type), '')) as event_type,
    nullif(trim(event_at), '')::timestamp as event_at,
    nullif(trim(failure_reason), '') as failure_reason,
    source_batch_id,
    _payload,
    _ingested_at,
    _source_file,
    _source_file_hash,
    _source_row_number,
    _load_id
from {{ source('raw', 'delivery_events') }}
where _load_id = (select load_id from latest_completed_load)
