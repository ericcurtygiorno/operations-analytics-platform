# Metric Dictionary

All business metrics use `marts.fact_deliveries` at shipment grain. The active Power BI calendar
is promised delivery date unless a measure explicitly activates another date role.

## Governance rules shared by comparison cards

- With one selected year, that year is the current comparison period.
- With multiple or no selected years, the latest available year is current.
- Prior YTD uses the same selected months from the preceding year.
- Percentage-point change is used for rates where the business question is absolute service
  movement; relative percentage change is used for volumes, durations, and amounts.
- Blank or zero denominators return blank instead of a misleading zero.

## Service-level metrics

### On-Time Delivery Rate

```text
eligible shipments delivered on or before promise
-------------------------------------------------
             SLA-eligible shipments
```

- Eligibility: `is_valid_for_sla = true`.
- On-time rule: `delivered_at <= promised_delivery_at`.
- Excludes open shipments, missing/inconsistent timestamps, orphan orders, invalid orders, and
  unknown carriers.
- Not called OTIF because the source does not prove item-level completeness.

### SLA Eligible Shipments

Distinct shipments where `is_valid_for_sla = true`. This is the governed denominator for on-time
service measures.

### On-Time Deliveries / Late Deliveries

Distinct SLA-eligible shipments where `is_on_time` is true / false.

### Average Delay (Late)

Average positive `delivery_delay_days` among late, SLA-eligible shipments. Early and on-time rows
do not reduce the result.

### P90 Delivery Delay

90th percentile of positive `delivery_delay_days` among late, SLA-eligible shipments. It describes
tail severity rather than the typical late shipment.

### First-Attempt Success Rate

```text
delivered shipments with delivery_attempts = 1
-----------------------------------------------
              delivered shipments
```

This is an operational attempt metric rather than an SLA metric; the denominator follows delivered
status and remains separately auditable through the data-quality page.

## Volume and status metrics

### Total Shipments

Distinct `shipment_id` values in the selected business context, including quality-exception rows.

### Delivered Shipments

Distinct shipments whose normalized status is `delivered`.

### Open Shipments

Distinct shipments whose normalized status is `in_transit`.

### Total Units / Total Weight (kg)

Sum of valid order quantity / shipment weight in the selected context. Null order-derived values
remain excluded naturally by aggregation.

## Cycle-time metrics

### Average Order-to-Ship Hours

Average elapsed hours from `order_at` to `shipped_at` for rows with a matched, chronologically valid
order lifecycle.

### Average Ship-to-Delivery Days

Average `ship_to_delivery_hours / 24` for delivered rows with a valid shipment timeline.

## Exception metrics

### Shipments with Exceptions

Distinct shipments where aggregated `exception_count > 0`.

### Exception Rate

```text
shipments with one or more exception events
-------------------------------------------
              total shipments
```

### Total Delivery Attempts

Sum of `delivery_attempts` in the selected context.

## Freight metrics

### Total Freight Amount

Sum of synthetic `freight_amount` in BRL. It is descriptive only and does not represent a real
company expense.

### Average Freight per Shipment

```text
total freight amount
--------------------
 distinct shipments
```

## Data-quality metrics

### Excluded from SLA

Distinct shipments where `is_valid_for_sla = false`.

### SLA Exclusion Rate

```text
shipments excluded by governed quality rules
---------------------------------------------
               total shipments
```

### Orphan Shipments

Distinct shipments with `is_orphan_order = true`.

### Unknown Carrier Shipments

Distinct shipments assigned to the governed unknown-carrier member.

### Invalid Timeline Shipments

Distinct shipments where actual delivery occurs before dispatch.

### Delivered Without Timestamp

Distinct shipments marked delivered without an actual delivery timestamp.

### Shipments with Data Quality Issues

Distinct shipments with at least one governed quality flag. Individual rule counts may overlap and
must not be summed to calculate this metric.

## Time-comparison metrics

### Previous Month and Month-over-Month

Previous-month measures shift the active promised-delivery date context by one calendar month.
On-time MoM is expressed in percentage points; shipment MoM is a relative percentage change.

### Current YTD, Prior YTD, and YoY

YTD comparison measures align the same selected months between current and preceding years. This
prevents an incomplete current year from being compared with a complete previous year.

## Interpretation boundaries

- All values describe deterministic synthetic data.
- Metrics identify simulated operational patterns; they do not prove causal drivers.
- No savings, service improvement, or business impact is claimed without an intervention and a
  measured counterfactual.
