# Business Context

## Fictional company

Northstar Commerce is a fictional Brazilian e-commerce company operating through three distribution centers and multiple parcel carriers. All entities and records in this project are synthetic and are not modeled after a specific employer or client.

## Operational problem

Operations leadership receives fragmented order, shipment, and delivery-event extracts. Definitions vary across teams, invalid records contaminate KPIs, and carrier or regional problems are discovered too late.

The project will deliver an analytical control tower that supports decisions about:

- delivery SLA performance;
- carrier and service-type allocation;
- regional and distribution-center bottlenecks;
- delivery exceptions and first-attempt success;
- freight cost and operational lead time;
- data-quality risk affecting management reporting.

## Initial decision questions

1. What percentage of eligible delivered shipments met the promised delivery timestamp?
2. Which carriers, regions, distribution centers, and service types drive late deliveries?
3. Where is cycle time accumulating between order, shipment, and delivery?
4. Which exception reasons are most associated with delays or repeated attempts?
5. How much reported performance changes when invalid and suspicious records are excluded?

## Integrity constraints

- The company, names, data, and findings are fictional.
- Published findings must be recalculated from a tagged dataset and code version.
- The project will not claim measured real-world savings or operational improvements.
- Personally identifiable information is deliberately excluded from the initial sources.
