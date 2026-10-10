select distinct
    md5(service_type) as service_type_key,
    service_type
from {{ ref('stg_orders') }}
where service_type is not null
