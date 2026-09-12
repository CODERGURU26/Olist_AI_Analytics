# Olist E-commerce Analytics

An end-to-end data analytics project on the Brazilian **Olist e-commerce dataset** — covering data quality auditing, ELT pipeline design, dimensional data warehousing, and business intelligence dashboarding in Power BI.

**Keywords:** SQL, PostgreSQL, ETL/ELT, Data Warehousing, Dimensional Modeling, Star Schema, Data Quality, Power BI, Business Intelligence, E-commerce Analytics

---

## Project Overview

This project transforms raw, unstructured Olist e-commerce data into a governed, analysis-ready data platform. It follows an industry-standard four-layer architecture (**Raw → Staging → Warehouse → Marts**) built entirely in SQL, with validation checks embedded at every stage, and culminates in a set of Power BI dashboards covering sales, customers, sellers, delivery, and reviews.

The goal was to simulate a real-world analytics engineering workflow: audit the raw data, build a reliable pipeline, model it into a dimensional warehouse, and deliver trustworthy, business-ready reporting.

---

## Business Problem

Olist connects small and medium-sized businesses in Brazil to major marketplaces, handling orders, logistics, and customer relations. Raw operational data on its own is fragmented across orders, payments, products, sellers, and reviews — making it hard to answer core business questions such as:

- How is overall sales performance trending, and which categories/sellers drive it?
- Who are our customers, and how much of our revenue comes from repeat buyers?
- Are sellers meeting delivery expectations, and where are the delivery bottlenecks?
- How satisfied are customers, and what's driving review scores?

This project builds the data infrastructure and dashboards needed to answer these questions reliably and repeatably.

---

## Dataset

The public **Olist Brazilian E-commerce Dataset**, covering orders placed between 2016 and 2018 across multiple relational tables (orders, customers, order items, payments, reviews, products, sellers, and geolocation).

**Validated dataset scale:**

| Metric | Value |
|---|---|
| Total Orders | 99,441 |
| Unique Customers | 96,096 |
| Total Order Value | ₹15.84M |
| Repeat Customer Rate | 3.12% |
| Total Reviews | 99,224 |
| Total Sellers | 3,095 |

---

## Tech Stack

- **Database:** PostgreSQL
- **Data Modeling:** SQL (ELT), star-schema dimensional design
- **Visualization:** Power BI
- **Version Control:** Git/GitHub

---

## Data Pipeline

The pipeline is implemented as four sequential SQL scripts, each validated before the next layer is built:

1. **`01_data_quality_audit.sql`** — Audits the raw data: table inventory, row counts, missing values, duplicate keys, invalid review scores, negative monetary values, orphaned foreign keys, and invalid delivery dates.
2. **`02_staging_tables.sql`** — Cleans and standardizes raw tables into the `staging` schema; adds derived business-logic columns (order stage classification, delivery status flags, pending/late delivery flags).
3. **`03_warehouse.sql`** — Builds the dimensional `warehouse` schema: customer, product, category, seller, geography, and date dimensions, plus fact tables for order items, orders, payments, and reviews.
4. **`04_Data_Mart.sql`** — Builds the business-facing `marts` schema: sales, customer, seller performance, delivery, and reviews marts, ready for BI consumption.

Data quality is validated at every stage — not just once upfront — including referential-integrity checks, reconciliation of mart totals against the warehouse, and a final end-to-end platform audit covering table inventory, key integrity, and financial reconciliation.

---

## Data Warehouse / Data Model

The warehouse uses a **star schema** design:

**Dimensions**
- `dim_customer`, `dim_product`, `dim_category`, `dim_seller`, `dim_geography`, `dim_date`

**Facts**
- `fact_order_items` (grain: one row per order item), `fact_orders`, `fact_payments`, `fact_reviews`

**Data Marts** (built on top of the warehouse)
- `mart_sales`, `mart_customer`, `mart_seller_performance`, `mart_delivery`, `mart_reviews`

```
RAW (public)  →  STAGING  →  WAREHOUSE (star schema)  →  MARTS  →  Power BI
```

---

## Power BI Dashboard

Five dashboards were built directly on top of the data marts:

### Executive Sales Overview
Total sales, orders, items sold, and average order value, with sales trend over time, sales by category, top sellers, and freight cost trends.

![Executive Sales Overview](./screenshots/Executive%20Sales%20Overview.png)

### Customer Analysis
Customer-level behavior and value metrics, including repeat-purchase patterns.

![Customer Analysis](./screenshots/Customer%20Analysis.png)

### Seller Performance
Seller scorecards and performance comparisons across the marketplace.

![Seller Performance](./screenshots/Seller%20Performance.png)

### Delivery Performance
Delivery timeliness and logistics KPIs.

![Delivery Performance](./screenshots/Delivery%20Performance.png)

### Customer Reviews
Review score distribution and customer satisfaction analysis.

![Customer Reviews](./screenshots/Customer%20Reviews.png)

---

## Key Business Insights

- The platform processed **99,441 orders** from **96,096 unique customers**, totaling **₹15.84M** in order value.
- Only **3.12%** of customers are repeat buyers — the vast majority of orders come from first-time customers, highlighting an opportunity to improve retention.
- **3,095 sellers** are active on the marketplace, with sales heavily concentrated among a small set of top sellers.
- **99,224 customer reviews** provide broad coverage across nearly all delivered orders, enabling reliable satisfaction tracking.
- Sales are heavily concentrated in a handful of southeastern Brazilian states, consistent with regional population and seller density.

---

## Project Structure

```
olist_ai_analytics/
├── 01_data_quality_audit.sql     # Raw data audit & integrity checks
├── 02_staging_tables.sql         # Cleaned staging layer + business logic
├── 03_warehouse.sql              # Star-schema dimensional warehouse
├── 04_Data_Mart.sql              # Business-facing data marts
├── screenshots/
│   ├── Executive Sales Overview.png
│   ├── Customer Analysis.png
│   ├── Seller Performance.png
│   ├── Delivery Performance.png
│   └── Customer Reviews.png
└── README.md
```

---

## How to Run

1. Load the raw Olist CSV files into a PostgreSQL database, under the `public` schema.
2. Run the SQL scripts in order:
   ```
   01_data_quality_audit.sql
   02_staging_tables.sql
   03_warehouse.sql
   04_Data_Mart.sql
   ```
3. Connect Power BI (or another BI tool) to the `marts` schema to reproduce the dashboards.

---

## Future Improvements

- Automate the pipeline with an orchestration tool (e.g. Airflow, dbt) instead of running scripts manually.
- Add incremental/CDC loading instead of full rebuilds.
- Build a customer segmentation model (RFM analysis) to better target retention efforts.
- Add automated data-quality testing (e.g. dbt tests or Great Expectations) in place of manual SQL validation queries.
- Deploy the Power BI dashboards to a shared workspace with scheduled refresh.
