select distinct
    md5(destination_region) as location_key,
    destination_region
from {{ ref('stg_orders') }}
where destination_region is not null
