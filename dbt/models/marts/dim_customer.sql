select distinct
    md5(customer_id) as customer_key,
    customer_id
from {{ ref('stg_orders') }}
where customer_id is not null
