select distinct
    md5(distribution_center_id) as distribution_center_key,
    distribution_center_id
from {{ ref('stg_orders') }}
where distribution_center_id is not null
