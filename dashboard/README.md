# Power BI Dashboard

The Power BI project is available at [`operations-analytics-platform.pbip`](operations-analytics-platform.pbip). It connects to the governed dimensional layer in PostgreSQL and provides a five-page operational control tower.

## Report pages

1. **Executive Overview** — YTD and YoY KPI comparisons, a two-year monthly SLA trend, and accessible carrier and regional on-time delivery rankings with volume, delay, exception, and freight context in the tooltip.
2. **Operational Performance** — YTD and YoY throughput and cycle-time comparisons, a two-year monthly volume trend, and distribution-center and service-type diagnostics.
3. **Carriers & Regions** — carrier scorecard, delivered volume by carrier and year, freight efficiency, and regional exception exposure without repeating the Overview visuals.
4. **Exceptions & Causes** — YTD and YoY exception KPIs, a two-year exception-rate trend, failure categories, and shipment-level root-cause detail.
5. **Data Quality** — YTD and YoY governed exclusions, record-level quality flags, carrier exposure, and a two-year exclusion-rate trend.

Each page includes a product-style Northstar Commerce Analytics header, shared year, month, and service-type slicers, page navigation, and a page-specific reset bookmark. Blank slicer members are suppressed. Every KPI is presented as one consolidated card: the current YTD value is dominant, while prior YTD and YoY appear as secondary context inside the same container. The card backgrounds use container-level rounded clipping so the fill remains inside the border at every corner. A visible information icon exposes a plain-language calculation definition on hover; tooltips are explicitly enabled on every icon and the internal helper-measure name is hidden from the reader. Executive Overview is the landing page; the four detail pages are hidden from report tabs but remain reachable through the in-report navigation.

When one year is selected, it becomes the current period; when multiple years are selected, the latest available year is current. Prior YTD uses the same selected months from the preceding year.

## Semantic model

- Eight business-facing tables: `_Measures`, `Carriers`, `Customers`, `Dates`, `Distribution Centers`, `Locations`, `Service Types`, and `Deliveries`.
- One hundred explicit DAX measures organized into nine top-level display folders, including formatted current-YTD, prior-YTD, YoY, definition measures, and the reusable KPI information glyph.
- Nine relationships, including an active promised-delivery date relationship and inactive order, shipped, and delivered date relationships for time intelligence.
- Hidden technical keys, documented business fields, a marked date table, and implicit measures disabled.

`_Measures` is the technical table name because `Measures` is reserved by Power BI Desktop. The leading underscore keeps the measure table at the top of the Fields pane.

## Local connection

- Connector: PostgreSQL database
- Server: `localhost:55432`
- Database: `operations_analytics`
- Data connectivity mode: Import
- Source layer: `marts`

Use the local credentials from `.env`. Never publish or screenshot the password.

## Rebuild and validation

The deterministic report generator is [`build_dashboard.ps1`](build_dashboard.ps1). It recreates the five PBIR pages, visuals, bookmarks, navigation, filters, and theme.

The publication-ready static gallery is stored in [`screenshots`](screenshots). Each image is
cropped to the report canvas, without Power BI Desktop panes or external canvas glow. Internal
rendered validation captures are kept out of the public repository. An interactive Power BI
Service version is intentionally deferred to the final portfolio release, when the walkthrough
videos and public links will be validated together. Validation completed with:

- PBIR structural validation: 0 errors; after Desktop saved the report with schema 2.13.0, the offline validator reported one schema-endpoint reachability warning only;
- semantic model validation: 8 tables, 100 measures, and 9 relationships;
- DAX and refresh validation: all 100 measures loaded and the model completed a full refresh without errors;
- rendered review: all five pages captured successfully after the full data refresh, with 185 report components and 5 reset bookmarks. The component count includes the layered elements that form 20 visually unified KPI cards, their information icons, and the reusable branded header.

The verified sample spans January 2024 through July 2025 and contains 756 shipments. The comparable January–July cards show 273 shipments and a 49.2% on-time delivery rate for 2025 versus 274 shipments and 44.4% for 2024.
