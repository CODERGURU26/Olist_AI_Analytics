# Olist E-commerce Analytics

An end-to-end data analytics project built on the public **Olist Brazilian E-commerce Dataset**, covering data quality auditing, SQL-based ELT pipeline design, dimensional data warehousing, business data marts, and interactive Power BI reporting.

**Keywords:** SQL, PostgreSQL, ETL/ELT, Data Warehousing, Dimensional Modeling, Star Schema, Data Quality, Power BI, DAX, Business Intelligence, E-commerce Analytics

---

## Project Overview

This project transforms raw, fragmented Olist e-commerce data into a governed, analysis-ready analytics platform.

The workflow follows a layered architecture:

**Raw → Staging → Warehouse → Data Marts → Power BI**

The project was designed to simulate a real-world analytics workflow:

1. Audit raw data quality and integrity.
2. Clean and standardize operational data.
3. Build a dimensional warehouse using star-schema principles.
4. Create business-facing data marts.
5. Validate financial and referential integrity at each layer.
6. Build interactive Power BI reports for business analysis.

The final solution covers **sales, customers, sellers, delivery performance, and customer reviews**.

---

## Business Problem

Olist connects small and medium-sized businesses in Brazil with major marketplaces. Its operational data is distributed across multiple related datasets covering orders, customers, products, sellers, payments, reviews, and logistics.

Without a structured analytics layer, it is difficult to answer questions such as:

- How is sales performance changing over time?
- Which product categories and sellers contribute the most revenue?
- How many unique customers does the marketplace serve?
- What proportion of customers make repeat purchases?
- Which sellers have the strongest or weakest performance?
- Where are delivery delays concentrated?
- How satisfied are customers based on review scores?
- How does customer satisfaction and operational performance vary geographically?

This project addresses these questions by building a reusable analytics pipeline and business intelligence layer.

---

## Dataset

The project uses the public **Olist Brazilian E-commerce Dataset**, which contains relational data covering orders placed in Brazil between 2016 and 2018.

The dataset includes information on:

- Orders
- Customers
- Order items
- Payments
- Products
- Sellers
- Reviews
- Product categories
- Geolocation
- Category name translations

### Dataset Source

[Olist Brazilian E-commerce Dataset on Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

---

## Validated Dataset Scale

| Metric | Value |
|---|---:|
| Total Orders | 99,441 |
| Unique Customers | 96,096 |
| Total Order Value | R$15.84M |
| Repeat Customer Rate | 3.12% |
| Total Reviews | 99,224 |
| Total Sellers | 3,095 |

All major metrics were validated against the PostgreSQL warehouse and data marts before being used in Power BI.

---

## Tech Stack

### Database
- PostgreSQL

### Data Engineering / Modeling
- SQL
- ELT pipeline design
- Staging and warehouse layers
- Dimensional modeling
- Star schema
- Data quality validation
- Financial reconciliation

### Business Intelligence
- Microsoft Power BI
- DAX
- Interactive dashboards
- KPI reporting
- Trend and geographic analysis

### Version Control
- Git
- GitHub

---

## Architecture

```text
                 ┌────────────────────┐
                 │   Olist Raw Data   │
                 │   Public Dataset   │
                 └─────────┬──────────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │      STAGING       │
                 │ Cleaning & Business│
                 │      Logic         │
                 └─────────┬──────────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │     WAREHOUSE      │
                 │   Star Schema      │
                 │ Dimensions + Facts │
                 └─────────┬──────────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │       MARTS        │
                 │ Business-ready SQL │
                 │     Analytics      │
                 └─────────┬──────────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │      POWER BI      │
                 │ Interactive Report │
                 └────────────────────┘
