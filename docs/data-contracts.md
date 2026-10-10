# Initial Source Data Contracts

These contracts define the generated source boundary. Raw ingestion will preserve source values and append ingestion metadata without destructively correcting anomalies.

## `orders.csv`

Grain: one source row per order record. Intentional duplicates and missing IDs may violate the expected business key.

| Column | Type at source | Expected rule |
|---|---|---|
| `order_id` | string | Non-empty and unique for valid records |
| `customer_id` | string | Synthetic identifier; no PII |
| `order_at` | ISO-8601 timestamp | Within the configured generation period |
| `distribution_center_id` | string | Member of the documented DC domain |
| `destination_region` | string | Member of the documented region domain |
| `service_type` | string | `express`, `standard`, or `economy` |
| `quantity` | integer | Greater than zero for valid records |
| `weight_kg` | decimal | Greater than zero |
| `freight_amount` | decimal | Non-negative |
| `source_batch_id` | string | Stable identifier for the generated batch |

## `shipments.csv`

Grain: one source row per shipment. The baseline generator emits one regular shipment per order plus intentional orphan records.

| Column | Type at source | Expected rule |
|---|---|---|
| `shipment_id` | string | Non-empty and unique |
| `order_id` | string | References a valid order for clean records |
| `carrier_name` | string | Member of the carrier domain |
| `shipped_at` | ISO-8601 timestamp | Not before `order_at` |
| `promised_delivery_at` | ISO-8601 timestamp | After shipment |
| `delivered_at` | ISO-8601 timestamp or empty | Required when status is `delivered` |
| `delivery_status` | string | `in_transit` or `delivered` in the first version |
| `delivery_attempts` | integer | Zero for open shipments; at least one for delivered shipments |
| `source_batch_id` | string | Stable identifier for the generated batch |

## `delivery_events.jsonl`

Grain: one event emitted for a shipment at a specific timestamp.

| Field | JSON type | Expected rule |
|---|---|---|
| `event_id` | string | Non-empty and unique |
| `shipment_id` | string | References a shipment |
| `event_type` | string | `shipped`, `delivery_exception`, or `delivered` |
| `event_at` | string | ISO-8601 timestamp |
| `failure_reason` | string or null | Populated for delivery exceptions |
| `source_batch_id` | string | Stable identifier for the generated batch |

## Intentional anomaly catalog

- Duplicate order rows.
- Missing order identifiers.
- Negative ordered quantities.
- Unknown carriers.
- Delivery timestamps before shipment timestamps.
- Delivered statuses without delivery timestamps.
- Shipments referencing nonexistent orders.

Counts are configured in `config/generator.json` and recorded in `generation_manifest.json`.
