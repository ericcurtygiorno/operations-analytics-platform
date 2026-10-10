select distinct
    md5(coalesce(carrier_name, '__missing__')) as carrier_key,
    carrier_name,
    is_unknown_carrier
from {{ ref('int_deliveries_enriched') }}
