with latest_completed_load as (
    select batches.load_id
    from {{ source('raw', 'ingestion_batches') }} batches
    where batches.status = 'completed'
      and exists (
          select 1
          from {{ source('raw', 'orders') }} rows
          where rows._load_id = batches.load_id
      )
    order by completed_at desc, started_at desc, load_id desc
    limit 1
),

normalized as (
    select
        _raw_id,
        nullif(trim(order_id), '') as order_id,
        nullif(trim(customer_id), '') as customer_id,
        nullif(trim(order_at), '')::timestamp as order_at,
        nullif(trim(distribution_center_id), '') as distribution_center_id,
        nullif(trim(destination_region), '') as destination_region,
        lower(nullif(trim(service_type), '')) as service_type,
        nullif(trim(quantity), '')::integer as quantity,
        nullif(trim(weight_kg), '')::numeric(12, 2) as weight_kg,
        nullif(trim(freight_amount), '')::numeric(12, 2) as freight_amount,
        source_batch_id,
        _ingested_at,
        _source_file,
        _source_file_hash,
        _source_row_number,
        _load_id
    from {{ source('raw', 'orders') }}
    where _load_id = (select load_id from latest_completed_load)
),

ranked as (
    select
        *,
        row_number() over (
            partition by coalesce(order_id, '__missing__' || _raw_id::text), source_batch_id
            order by _raw_id
        ) as duplicate_rank
    from normalized
)

select
    *,
    order_id is null as is_missing_order_id,
    quantity is null or quantity <= 0 as is_invalid_quantity,
    weight_kg is null or weight_kg <= 0 as is_invalid_weight,
    freight_amount is null or freight_amount < 0 as is_invalid_freight,
    distribution_center_id not in ('DC-SAO', 'DC-REC', 'DC-CWB') as is_unknown_distribution_center,
    destination_region not in ('Southeast', 'South', 'Northeast', 'Central-West') as is_unknown_region,
    service_type not in ('express', 'standard', 'economy') as is_unknown_service_type,
    not (
        order_id is null
        or quantity is null or quantity <= 0
        or weight_kg is null or weight_kg <= 0
        or freight_amount is null or freight_amount < 0
        or distribution_center_id not in ('DC-SAO', 'DC-REC', 'DC-CWB')
        or destination_region not in ('Southeast', 'South', 'Northeast', 'Central-West')
        or service_type not in ('express', 'standard', 'economy')
    ) as is_valid_order_record
from ranked
where duplicate_rank = 1
