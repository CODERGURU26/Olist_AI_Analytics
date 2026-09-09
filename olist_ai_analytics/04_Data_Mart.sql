/*
===============================================================================
FILE: 04_data_marts.sql

PROJECT:
Olist AI Analytics & Decision Intelligence Platform

PURPOSE:
Create the business-focused data mart layer.

ARCHITECTURE:

RAW
 ↓
STAGING
 ↓
WAREHOUSE
 ↓
MARTS
 ↓
POWER BI / AI

===============================================================================
SECTION 1: CREATE MARTS SCHEMA
===============================================================================
*/

CREATE SCHEMA IF NOT EXISTS marts;

/*
===============================================================================
SECTION 2: VERIFY MARTS SCHEMA
===============================================================================
*/

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'marts';


/*
===============================================================================
SECTION 3: PREVIEW SALES MART
===============================================================================

PURPOSE:
--------
Preview a business-friendly sales dataset built from the warehouse.

GRAIN:
------
1 row = 1 order item.
===============================================================================
*/

SELECT
    foi.order_id,
    foi.order_item_id,

    dd.full_date AS order_date,

    dp.product_id,

    dc.category_name,
    dc.category_name_english,

    ds.seller_id,
    ds.seller_city,
    ds.seller_state,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    foi.price,
    foi.freight_value,
    foi.item_total

FROM warehouse.fact_order_items foi

INNER JOIN warehouse.dim_date dd
    ON foi.order_date_key = dd.date_key

INNER JOIN warehouse.dim_product dp
    ON foi.product_key = dp.product_key

LEFT JOIN warehouse.dim_category dc
    ON dp.category_key = dc.category_key

INNER JOIN warehouse.dim_seller ds
    ON foi.seller_key = ds.seller_key

INNER JOIN warehouse.dim_customer dcu
    ON foi.customer_key = dcu.customer_key

ORDER BY dd.full_date, foi.order_id, foi.order_item_id

LIMIT 10;

/*
===============================================================================
SECTION 4: CREATE SALES MART
===============================================================================

PURPOSE:
--------
Create a business-friendly sales mart for Power BI and analytical reporting.

GRAIN:
------
1 row = 1 order item.

SOURCE:
-------
warehouse.fact_order_items
joined with relevant warehouse dimensions.

DESIGN:
-------
The mart exposes business-friendly attributes instead of requiring BI users
to understand the warehouse's surrogate-key structure.
===============================================================================
*/

CREATE TABLE marts.mart_sales (

    order_id VARCHAR(50) NOT NULL,

    order_item_id INTEGER NOT NULL,

    order_date DATE NOT NULL,

    product_id VARCHAR(50) NOT NULL,

    category_name VARCHAR(100),

    category_name_english VARCHAR(100),

    seller_id VARCHAR(50) NOT NULL,

    seller_city VARCHAR(100),

    seller_state VARCHAR(10),

    customer_id VARCHAR(50) NOT NULL,

    customer_city VARCHAR(100),

    customer_state VARCHAR(10),

    price NUMERIC NOT NULL,

    freight_value NUMERIC NOT NULL,

    item_total NUMERIC NOT NULL
);


/*
===============================================================================
SECTION 5: VERIFY SALES MART STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that marts.mart_sales contains the business-friendly sales columns
we designed.

GRAIN:
------
1 row = 1 order item.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'marts'
  AND table_name = 'mart_sales'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 6: LOAD SALES MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_sales from the warehouse fact and dimension tables.

GRAIN:
------
1 row = 1 order item.

The warehouse surrogate keys are used internally for joining, but the mart
stores business-friendly IDs and descriptive attributes for BI users.
===============================================================================
*/

INSERT INTO marts.mart_sales (
    order_id,
    order_item_id,
    order_date,
    product_id,
    category_name,
    category_name_english,
    seller_id,
    seller_city,
    seller_state,
    customer_id,
    customer_city,
    customer_state,
    price,
    freight_value,
    item_total
)

SELECT
    foi.order_id,
    foi.order_item_id,

    dd.full_date AS order_date,

    dp.product_id,

    dc.category_name,
    dc.category_name_english,

    ds.seller_id,
    ds.seller_city,
    ds.seller_state,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    foi.price,
    foi.freight_value,
    foi.item_total

FROM warehouse.fact_order_items foi

INNER JOIN warehouse.dim_date dd
    ON foi.order_date_key = dd.date_key

INNER JOIN warehouse.dim_product dp
    ON foi.product_key = dp.product_key

LEFT JOIN warehouse.dim_category dc
    ON dp.category_key = dc.category_key

INNER JOIN warehouse.dim_seller ds
    ON foi.seller_key = ds.seller_key

INNER JOIN warehouse.dim_customer dcu
    ON foi.customer_key = dcu.customer_key;


/*
===============================================================================
SECTION 7: VALIDATE SALES MART
===============================================================================

PURPOSE:
--------
Confirm that mart_sales contains every warehouse order-item record and that
the key sales measures are populated correctly.

CHECKS:
-------
1. Row count matches fact_order_items.
2. order_id + order_item_id is unique.
3. Price is not NULL.
4. Freight is not NULL.
5. Item total is not NULL.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.fact_order_items)
        AS warehouse_rows,

    (SELECT COUNT(*)
     FROM marts.mart_sales)
        AS mart_rows,

    (SELECT COUNT(*)
     FROM (
         SELECT
             order_id,
             order_item_id
         FROM marts.mart_sales
         GROUP BY
             order_id,
             order_item_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_order_items,

    (SELECT COUNT(*)
     FROM marts.mart_sales
     WHERE price IS NULL)
        AS null_prices,

    (SELECT COUNT(*)
     FROM marts.mart_sales
     WHERE freight_value IS NULL)
        AS null_freight,

    (SELECT COUNT(*)
     FROM marts.mart_sales
     WHERE item_total IS NULL)
        AS null_item_totals;


/*
===============================================================================
SECTION 8: PREVIEW CUSTOMER MART METRICS
===============================================================================

PURPOSE:
--------
Preview customer-level metrics before creating marts.mart_customer.

GRAIN:
------
1 row = 1 customer.
===============================================================================
*/

SELECT
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    MIN(fo.order_date_key) AS first_order_date_key,

    MAX(fo.order_date_key) AS last_order_date_key,

    COUNT(DISTINCT fo.order_id) AS total_orders,

    COUNT(foi.order_item_id) AS total_items,

    SUM(foi.item_total) AS total_revenue,

    SUM(foi.freight_value) AS total_freight,

    ROUND(
        SUM(foi.item_total)
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS average_order_value

FROM warehouse.dim_customer dcu

INNER JOIN warehouse.fact_orders fo
    ON dcu.customer_key = fo.customer_key

INNER JOIN warehouse.fact_order_items foi
    ON fo.order_id = foi.order_id

GROUP BY
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state

ORDER BY total_revenue DESC

LIMIT 10;


/*
===============================================================================
SECTION 9: PREVIEW CUSTOMER MART — CORRECTED METRICS
===============================================================================

PURPOSE:
--------
Preview customer-level business metrics using the correct customer grain.

GRAIN:
------
1 row = 1 customer.

METRICS:
--------
gross_sales        = product price only
total_freight      = shipping charges
total_order_value  = price + freight
average_order_value = total_order_value / orders

LEFT JOIN:
----------
Keeps every customer in the mart, including customers with no orders.
===============================================================================
*/

SELECT
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    MIN(dd.full_date) AS first_order_date,

    MAX(dd.full_date) AS last_order_date,

    COUNT(DISTINCT fo.order_id) AS total_orders,

    COUNT(foi.order_item_id) AS total_items,

    COALESCE(SUM(foi.price), 0) AS gross_sales,

    COALESCE(SUM(foi.freight_value), 0) AS total_freight,

    COALESCE(SUM(foi.item_total), 0) AS total_order_value,

    ROUND(
        COALESCE(SUM(foi.item_total), 0)
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS average_order_value

FROM warehouse.dim_customer dcu

LEFT JOIN warehouse.fact_orders fo
    ON dcu.customer_key = fo.customer_key

LEFT JOIN warehouse.fact_order_items foi
    ON fo.order_id = foi.order_id

LEFT JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

GROUP BY
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state

ORDER BY total_order_value DESC

LIMIT 10;


/*
===============================================================================
SECTION 10: CREATE CUSTOMER MART
===============================================================================

PURPOSE:
--------
Create a business-focused customer mart for customer analysis and
segmentation.

GRAIN:
------
1 row = 1 customer.

KEY METRICS:
------------
first_order_date
last_order_date
total_orders
total_items
gross_sales
total_freight
total_order_value
average_order_value
is_repeat_customer
===============================================================================
*/

CREATE TABLE marts.mart_customer (

    customer_id VARCHAR(50) NOT NULL,

    customer_city VARCHAR(100),

    customer_state VARCHAR(10),

    first_order_date DATE,

    last_order_date DATE,

    total_orders INTEGER NOT NULL,

    total_items INTEGER NOT NULL,

    gross_sales NUMERIC NOT NULL,

    total_freight NUMERIC NOT NULL,

    total_order_value NUMERIC NOT NULL,

    average_order_value NUMERIC,

    is_repeat_customer BOOLEAN NOT NULL
);

/*
===============================================================================
SECTION 11: VERIFY CUSTOMER MART STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that marts.mart_customer contains the expected customer-level
attributes and metrics.

GRAIN:
------
1 row = 1 customer.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'marts'
  AND table_name = 'mart_customer'
ORDER BY ordinal_position;


/*
===============================================================================
SECTION 12: LOAD CUSTOMER MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_customer with one row per customer.

GRAIN:
------
1 row = 1 customer.

METRICS:
--------
gross_sales         = SUM(product price)
total_freight       = SUM(freight)
total_order_value   = SUM(price + freight)
average_order_value = total_order_value / total_orders

REPEAT CUSTOMER:
----------------
TRUE when a customer has more than one order.

LEFT JOIN:
----------
Keeps every customer, even if they have no orders.
===============================================================================
*/

INSERT INTO marts.mart_customer (
    customer_id,
    customer_city,
    customer_state,
    first_order_date,
    last_order_date,
    total_orders,
    total_items,
    gross_sales,
    total_freight,
    total_order_value,
    average_order_value,
    is_repeat_customer
)

SELECT
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    MIN(dd.full_date) AS first_order_date,

    MAX(dd.full_date) AS last_order_date,

    COUNT(DISTINCT fo.order_id)::INTEGER AS total_orders,

    COUNT(foi.order_item_id)::INTEGER AS total_items,

    COALESCE(SUM(foi.price), 0) AS gross_sales,

    COALESCE(SUM(foi.freight_value), 0) AS total_freight,

    COALESCE(SUM(foi.item_total), 0) AS total_order_value,

    ROUND(
        COALESCE(SUM(foi.item_total), 0)
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS average_order_value,

    CASE
        WHEN COUNT(DISTINCT fo.order_id) > 1
        THEN TRUE
        ELSE FALSE
    END AS is_repeat_customer

FROM warehouse.dim_customer dcu

LEFT JOIN warehouse.fact_orders fo
    ON dcu.customer_key = fo.customer_key

LEFT JOIN warehouse.fact_order_items foi
    ON fo.order_id = foi.order_id

LEFT JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

GROUP BY
    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state;


/*
===============================================================================
SECTION 13: VALIDATE CUSTOMER MART
===============================================================================

PURPOSE:
--------
Confirm that the customer mart contains exactly one row per customer and
that the calculated metrics are populated correctly.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.dim_customer)
        AS warehouse_customers,

    (SELECT COUNT(*)
     FROM marts.mart_customer)
        AS mart_customers,

    (SELECT COUNT(*)
     FROM (
         SELECT customer_id
         FROM marts.mart_customer
         GROUP BY customer_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_customers,

    (SELECT COUNT(*)
     FROM marts.mart_customer
     WHERE total_orders < 0)
        AS invalid_order_counts,

    (SELECT COUNT(*)
     FROM marts.mart_customer
     WHERE total_items < 0)
        AS invalid_item_counts,

    (SELECT COUNT(*)
     FROM marts.mart_customer
     WHERE gross_sales < 0)
        AS negative_gross_sales,

    (SELECT COUNT(*)
     FROM marts.mart_customer
     WHERE total_order_value < 0)
        AS negative_order_values;


/*
===============================================================================
SECTION 14: RECONCILE CUSTOMER MART WITH SALES MART
===============================================================================

PURPOSE:
--------
Confirm that the customer mart preserves the same total sales and freight
amounts as the transaction-level sales mart.

This is a business reconciliation, not just a row-count check.
===============================================================================
*/

SELECT
    (
        SELECT ROUND(SUM(total_order_value), 2)
        FROM marts.mart_customer
    ) AS customer_mart_total,

    (
        SELECT ROUND(SUM(item_total), 2)
        FROM marts.mart_sales
    ) AS sales_mart_total,

    (
        SELECT ROUND(SUM(total_freight), 2)
        FROM marts.mart_customer
    ) AS customer_mart_freight,

    (
        SELECT ROUND(SUM(freight_value), 2)
        FROM marts.mart_sales
    ) AS sales_mart_freight;


/*
===============================================================================
SECTION 15: PREVIEW SELLER PERFORMANCE MART
===============================================================================

PURPOSE:
--------
Preview seller-level business and delivery performance metrics.

GRAIN:
------
1 row = 1 seller.
===============================================================================
*/

SELECT
    ds.seller_id,
    ds.seller_city,
    ds.seller_state,

    COUNT(DISTINCT fo.order_id) AS total_orders,

    COUNT(foi.order_item_id) AS total_items,

    COALESCE(SUM(foi.price), 0) AS gross_sales,

    COALESCE(SUM(foi.freight_value), 0) AS total_freight,

    COALESCE(SUM(foi.item_total), 0) AS total_order_value,

    ROUND(
        COALESCE(SUM(foi.item_total), 0)
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS average_order_value,

    COUNT(DISTINCT fo.order_id) FILTER (
        WHERE fo.is_delivered = TRUE
    ) AS delivered_orders,

    COUNT(DISTINCT fo.order_id) FILTER (
        WHERE fo.is_late = TRUE
    ) AS late_orders,

    ROUND(
        100.0 * COUNT(DISTINCT fo.order_id) FILTER (
            WHERE fo.is_late = TRUE
        )
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(fo.delivery_days) FILTER (
            WHERE fo.is_delivered = TRUE
        ),
        2
    ) AS average_delivery_days

FROM warehouse.dim_seller ds

LEFT JOIN warehouse.fact_order_items foi
    ON ds.seller_key = foi.seller_key

LEFT JOIN warehouse.fact_orders fo
    ON foi.order_id = fo.order_id

GROUP BY
    ds.seller_id,
    ds.seller_city,
    ds.seller_state

ORDER BY total_order_value DESC

LIMIT 10;

/*
===============================================================================
SECTION 16: CREATE SELLER PERFORMANCE MART
===============================================================================

PURPOSE:
--------
Create a business-focused seller performance mart.

GRAIN:
------
1 row = 1 seller.

BUSINESS AREAS:
---------------
Sales performance
Delivery performance
Seller-level operational performance
===============================================================================
*/

CREATE TABLE marts.mart_seller_performance (

    seller_id VARCHAR(50) NOT NULL,

    seller_city VARCHAR(100),

    seller_state VARCHAR(10),

    total_orders INTEGER NOT NULL,

    total_items INTEGER NOT NULL,

    gross_sales NUMERIC NOT NULL,

    total_freight NUMERIC NOT NULL,

    total_order_value NUMERIC NOT NULL,

    average_order_value NUMERIC,

    delivered_orders INTEGER NOT NULL,

    late_orders INTEGER NOT NULL,

    late_delivery_rate NUMERIC,

    average_delivery_days NUMERIC
);

/*
===============================================================================
SECTION 17: VERIFY SELLER PERFORMANCE MART STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that marts.mart_seller_performance contains the expected seller-level
sales and delivery metrics.

GRAIN:
------
1 row = 1 seller.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'marts'
  AND table_name = 'mart_seller_performance'
ORDER BY ordinal_position;


/*
===============================================================================
SECTION 18: LOAD SELLER PERFORMANCE MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_seller_performance with one row per seller.

GRAIN:
------
1 row = 1 seller.

METRICS:
--------
Sales metrics are calculated from fact_order_items.

Delivery metrics are calculated from fact_orders.

COUNT(DISTINCT order_id) is used for order counts so multiple items from the
same order do not inflate the number of orders.
===============================================================================
*/

INSERT INTO marts.mart_seller_performance (
    seller_id,
    seller_city,
    seller_state,
    total_orders,
    total_items,
    gross_sales,
    total_freight,
    total_order_value,
    average_order_value,
    delivered_orders,
    late_orders,
    late_delivery_rate,
    average_delivery_days
)

SELECT
    ds.seller_id,
    ds.seller_city,
    ds.seller_state,

    COUNT(DISTINCT fo.order_id)::INTEGER AS total_orders,

    COUNT(foi.order_item_id)::INTEGER AS total_items,

    COALESCE(SUM(foi.price), 0) AS gross_sales,

    COALESCE(SUM(foi.freight_value), 0) AS total_freight,

    COALESCE(SUM(foi.item_total), 0) AS total_order_value,

    ROUND(
        COALESCE(SUM(foi.item_total), 0)
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS average_order_value,

    COUNT(DISTINCT fo.order_id) FILTER (
        WHERE fo.is_delivered = TRUE
    )::INTEGER AS delivered_orders,

    COUNT(DISTINCT fo.order_id) FILTER (
        WHERE fo.is_late = TRUE
    )::INTEGER AS late_orders,

    ROUND(
        100.0 * COUNT(DISTINCT fo.order_id) FILTER (
            WHERE fo.is_late = TRUE
        )
        / NULLIF(COUNT(DISTINCT fo.order_id), 0),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(fo.delivery_days) FILTER (
            WHERE fo.is_delivered = TRUE
        ),
        2
    ) AS average_delivery_days

FROM warehouse.dim_seller ds

LEFT JOIN warehouse.fact_order_items foi
    ON ds.seller_key = foi.seller_key

LEFT JOIN warehouse.fact_orders fo
    ON foi.order_id = fo.order_id

GROUP BY
    ds.seller_id,
    ds.seller_city,
    ds.seller_state;


/*
===============================================================================
SECTION 19: VALIDATE SELLER PERFORMANCE MART
===============================================================================

PURPOSE:
--------
Confirm that the seller mart contains exactly one row per seller and that
its calculated sales and delivery metrics are valid.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.dim_seller)
        AS warehouse_sellers,

    (SELECT COUNT(*)
     FROM marts.mart_seller_performance)
        AS mart_sellers,

    (SELECT COUNT(*)
     FROM (
         SELECT seller_id
         FROM marts.mart_seller_performance
         GROUP BY seller_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_sellers,

    (SELECT COUNT(*)
     FROM marts.mart_seller_performance
     WHERE total_orders < 0)
        AS invalid_order_counts,

    (SELECT COUNT(*)
     FROM marts.mart_seller_performance
     WHERE total_items < 0)
        AS invalid_item_counts,

    (SELECT COUNT(*)
     FROM marts.mart_seller_performance
     WHERE gross_sales < 0)
        AS negative_gross_sales,

    (SELECT COUNT(*)
     FROM marts.mart_seller_performance
     WHERE late_orders > total_orders)
        AS invalid_late_orders;


/*
===============================================================================
SECTION 20: RECONCILE SELLER PERFORMANCE MART
===============================================================================

PURPOSE:
--------
Confirm that seller-level aggregation preserves the same sales and freight
totals as the transaction-level sales mart.
===============================================================================
*/

SELECT
    (
        SELECT ROUND(SUM(total_order_value), 2)
        FROM marts.mart_seller_performance
    ) AS seller_mart_total,

    (
        SELECT ROUND(SUM(item_total), 2)
        FROM marts.mart_sales
    ) AS sales_mart_total,

    (
        SELECT ROUND(SUM(total_freight), 2)
        FROM marts.mart_seller_performance
    ) AS seller_mart_freight,

    (
        SELECT ROUND(SUM(freight_value), 2)
        FROM marts.mart_sales
    ) AS sales_mart_freight;


/*
===============================================================================
SECTION 21: PREVIEW DELIVERY MART
===============================================================================

PURPOSE:
--------
Preview order-level delivery performance metrics.

GRAIN:
------
1 row = 1 order.

METRICS:
--------
delivery_days
is_delivered
is_late
is_cancelled
is_pending_delivery
===============================================================================
*/

SELECT
    fo.order_id,

    dd.full_date AS order_date,

    fo.order_status,

    fo.is_delivered,

    fo.has_delivery_timestamp,

    fo.is_cancelled,

    fo.is_late,

    fo.is_pending_delivery,

    fo.delivery_days,

    fo.customer_key

FROM warehouse.fact_orders fo

INNER JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

ORDER BY dd.full_date, fo.order_id

LIMIT 20;

/*
===============================================================================
SECTION 22: PREVIEW DELIVERY MART — BUSINESS VIEW
===============================================================================

PURPOSE:
--------
Preview a business-friendly order-level delivery dataset.

GRAIN:
------
1 row = 1 order.

BUSINESS ATTRIBUTES:
--------------------
Order date
Customer
Seller
Order status

DELIVERY METRICS:
-----------------
Delivery days
Delivered flag
Late flag
Cancelled flag
Pending-delivery flag
===============================================================================
*/

SELECT
    fo.order_id,

    dd.full_date AS order_date,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    ds.seller_id,
    ds.seller_city,
    ds.seller_state,

    fo.order_status,

    fo.is_delivered,
    fo.is_cancelled,
    fo.is_late,
    fo.is_pending_delivery,

    CASE
        WHEN fo.delivery_days IS NOT NULL
        THEN ROUND(fo.delivery_days, 2)
        ELSE NULL
    END AS delivery_days,

    fo.has_delivery_timestamp

FROM warehouse.fact_orders fo

INNER JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key

LEFT JOIN (
    SELECT DISTINCT
        fo2.order_id,
        foi.seller_key
    FROM warehouse.fact_orders fo2
    INNER JOIN warehouse.fact_order_items foi
        ON fo2.order_id = foi.order_id
) order_sellers
    ON fo.order_id = order_sellers.order_id

LEFT JOIN warehouse.dim_seller ds
    ON order_sellers.seller_key = ds.seller_key

ORDER BY dd.full_date, fo.order_id

LIMIT 20;

/*
===============================================================================
SECTION 22A: CHECK MULTI-SELLER ORDERS
===============================================================================

PURPOSE:
--------
Determine whether a single order can contain items from multiple sellers.

This is critical because mart_delivery is intended to have:

1 row = 1 order

If an order has multiple sellers, seller attributes cannot be directly added
without changing the grain.
===============================================================================
*/

SELECT
    COUNT(*) AS multi_seller_orders
FROM (
    SELECT
        foi.order_id,
        COUNT(DISTINCT foi.seller_key) AS seller_count
    FROM warehouse.fact_order_items foi
    GROUP BY foi.order_id
    HAVING COUNT(DISTINCT foi.seller_key) > 1
) x;

/*
===============================================================================
SECTION 23: FINAL PREVIEW DELIVERY MART
===============================================================================

PURPOSE:
--------
Preview the final business-friendly delivery mart.

GRAIN:
------
1 row = 1 order.

IMPORTANT:
----------
Seller information is intentionally excluded because 1,278 orders contain
multiple sellers. Including seller attributes would change the grain.
===============================================================================
*/

SELECT
    fo.order_id,

    dd.full_date AS order_date,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    fo.order_status,

    fo.is_delivered,

    fo.has_delivery_timestamp,

    fo.is_cancelled,

    fo.is_late,

    fo.is_pending_delivery,

    CASE
        WHEN fo.delivery_days IS NOT NULL
        THEN ROUND(fo.delivery_days, 2)
        ELSE NULL
    END AS delivery_days

FROM warehouse.fact_orders fo

INNER JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key

ORDER BY
    dd.full_date,
    fo.order_id

LIMIT 20;

/*
===============================================================================
SECTION 24: CREATE DELIVERY MART
===============================================================================

PURPOSE:
--------
Create a business-focused order-level delivery performance mart.

GRAIN:
------
1 row = 1 order.

IMPORTANT:
----------
Seller attributes are intentionally excluded because 1,278 orders contain
multiple sellers. Adding seller attributes would break the order-level grain.

BUSINESS USE:
-------------
This mart supports analysis of:
- delivery performance
- late deliveries
- cancellations
- pending orders
- delivery duration
===============================================================================
*/

CREATE TABLE marts.mart_delivery (

    order_id VARCHAR(50) NOT NULL,

    order_date DATE NOT NULL,

    customer_id VARCHAR(50) NOT NULL,

    customer_city VARCHAR(100),

    customer_state VARCHAR(10),

    order_status VARCHAR(30) NOT NULL,

    is_delivered BOOLEAN NOT NULL,

    has_delivery_timestamp BOOLEAN NOT NULL,

    is_cancelled BOOLEAN NOT NULL,

    is_late BOOLEAN NOT NULL,

    is_pending_delivery BOOLEAN NOT NULL,

    delivery_days NUMERIC,

    CONSTRAINT pk_mart_delivery
        PRIMARY KEY (order_id)
);


/*
===============================================================================
SECTION 25: VERIFY DELIVERY MART STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that marts.mart_delivery contains the intended order-level delivery
attributes.

GRAIN:
------
1 row = 1 order.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'marts'
  AND table_name = 'mart_delivery'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 26: LOAD DELIVERY MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_delivery with one business-ready record per order.

GRAIN:
------
1 row = 1 order.

DELIVERY DAYS:
--------------
Rounded to 2 decimal places for cleaner BI reporting.

SELLER INFORMATION:
-------------------
Intentionally excluded because 1,278 orders contain multiple sellers and
including seller attributes would break the one-row-per-order grain.
===============================================================================
*/

INSERT INTO marts.mart_delivery (
    order_id,
    order_date,
    customer_id,
    customer_city,
    customer_state,
    order_status,
    is_delivered,
    has_delivery_timestamp,
    is_cancelled,
    is_late,
    is_pending_delivery,
    delivery_days
)

SELECT
    fo.order_id,

    dd.full_date AS order_date,

    dcu.customer_id,

    dcu.customer_city,

    dcu.customer_state,

    fo.order_status,

    fo.is_delivered,

    fo.has_delivery_timestamp,

    fo.is_cancelled,

    fo.is_late,

    fo.is_pending_delivery,

    CASE
        WHEN fo.delivery_days IS NOT NULL
        THEN ROUND(fo.delivery_days, 2)
        ELSE NULL
    END AS delivery_days

FROM warehouse.fact_orders fo

INNER JOIN warehouse.dim_date dd
    ON fo.order_date_key = dd.date_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key;


/*
===============================================================================
SECTION 27: VALIDATE DELIVERY MART
===============================================================================

PURPOSE:
--------
Confirm that the delivery mart contains exactly one record per order and that
the delivery metrics are logically valid.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.fact_orders)
        AS warehouse_orders,

    (SELECT COUNT(*)
     FROM marts.mart_delivery)
        AS mart_orders,

    (SELECT COUNT(*)
     FROM (
         SELECT order_id
         FROM marts.mart_delivery
         GROUP BY order_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_orders,

    (SELECT COUNT(*)
     FROM marts.mart_delivery
     WHERE delivery_days < 0)
        AS negative_delivery_days,

    (SELECT COUNT(*)
     FROM marts.mart_delivery
     WHERE is_late = TRUE
       AND is_cancelled = TRUE)
        AS late_cancelled_orders,

    (SELECT COUNT(*)
     FROM marts.mart_delivery
     WHERE is_delivered = TRUE
       AND delivery_days IS NULL)
        AS delivered_without_delivery_days;


/*
===============================================================================
SECTION 28: INVESTIGATE MISSING DELIVERY DAYS
===============================================================================

PURPOSE:
--------
Identify delivered orders that do not have a delivery duration.

This is a data-quality investigation. No data is modified.
===============================================================================
*/

SELECT
    order_id,
    order_status,
    is_delivered,
    has_delivery_timestamp,
    delivery_days
FROM warehouse.fact_orders
WHERE is_delivered = TRUE
  AND delivery_days IS NULL
ORDER BY order_id;



/*
===============================================================================
SECTION 29: TRACE MISSING DELIVERY DAYS TO STAGING
===============================================================================

PURPOSE:
--------
Verify whether the eight delivered orders actually lack a delivered-customer
timestamp in the staging layer.

No data is modified.
===============================================================================
*/

SELECT
    order_id,
    order_status,
    purchase_timestamp,
    delivered_customer_timestamp,
    estimated_delivery_timestamp,
    delivery_days,
    is_delivered,
    has_delivery_timestamp
FROM staging.orders
WHERE order_id IN (
    '0d3268bad9b086af767785e3f0fc0133',
    '20edc82cf5400ce95e1afacc25798b31',
    '2d1e2d5bf4dc7227b3bfebb81328c15f',
    '2d858f451373b04fb5c984a1cc2defaf',
    '2ebdfc4f15f23b91474edf87475f108e',
    'ab7c89dc1bf4a1ead9d6ec1ec8968a84',
    'e69f75a717d64fc5ecdfae42b2e8e086',
    'f5dd62b788049ad9fc0526e3ad11a097'
)
ORDER BY order_id;


/*
===============================================================================
SECTION 30: FINAL VALIDATION OF DELIVERY MART
===============================================================================

PURPOSE:
--------
Confirm that the delivery mart preserves the order-level grain and correctly
represents missing source delivery timestamps.

IMPORTANT:
----------
Delivered orders without an actual delivery timestamp are retained with
delivery_days = NULL rather than being assigned an estimated or fabricated
value.
===============================================================================
*/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
    ) AS delivered_orders,

    COUNT(*) FILTER (
        WHERE has_delivery_timestamp = TRUE
    ) AS orders_with_delivery_timestamp,

    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
          AND has_delivery_timestamp = FALSE
    ) AS delivered_without_timestamp,

    COUNT(*) FILTER (
        WHERE delivery_days IS NOT NULL
    ) AS orders_with_delivery_days,

    COUNT(*) FILTER (
        WHERE is_late = TRUE
    ) AS late_orders,

    COUNT(*) FILTER (
        WHERE is_cancelled = TRUE
    ) AS cancelled_orders,

    COUNT(*) FILTER (
        WHERE is_pending_delivery = TRUE
    ) AS pending_orders

FROM marts.mart_delivery;


/*
===============================================================================
SECTION 31: RECONCILE DELIVERY FLAGS
===============================================================================

PURPOSE:
--------
Check whether the warehouse delivery flags agree with the actual
delivered_customer_timestamp availability.

This is a data-quality reconciliation.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
          AND has_delivery_timestamp = FALSE
    ) AS delivered_without_flagged_timestamp,

    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
          AND delivery_days IS NULL
    ) AS delivered_without_delivery_days,

    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
          AND has_delivery_timestamp = TRUE
          AND delivery_days IS NULL
    ) AS timestamp_but_no_delivery_days,

    COUNT(*) FILTER (
        WHERE is_delivered = FALSE
          AND has_delivery_timestamp = TRUE
    ) AS not_delivered_with_timestamp

FROM warehouse.fact_orders;

/*
===============================================================================
SECTION 32: PREVIEW REVIEW MART
===============================================================================

PURPOSE:
--------
Preview a business-friendly customer-review dataset.

GRAIN:
------
1 row = 1 review.

BUSINESS USE:
-------------
- Customer satisfaction
- Rating distribution
- Review response performance
- Comment analysis
===============================================================================
*/

SELECT
    fr.review_id,

    dd.full_date AS review_date,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    fr.order_id,

    fr.review_score,

    fr.review_response_days,

    fr.has_comment

FROM warehouse.fact_reviews fr

INNER JOIN warehouse.dim_date dd
    ON fr.review_date_key = dd.date_key

INNER JOIN warehouse.fact_orders fo
    ON fr.order_key = fo.fact_order_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key

ORDER BY
    dd.full_date,
    fr.review_id

LIMIT 20;


/*
===============================================================================
SECTION 33: CREATE REVIEW MART
===============================================================================

PURPOSE:
--------
Create a business-focused customer review mart.

GRAIN:
------
1 row = 1 review.

BUSINESS USE:
-------------
- Review score analysis
- Customer satisfaction
- Review response-time analysis
- Comment availability analysis
===============================================================================
*/

CREATE TABLE marts.mart_reviews (

    review_id VARCHAR(50) NOT NULL,

    review_date DATE NOT NULL,

    customer_id VARCHAR(50) NOT NULL,

    customer_city VARCHAR(100),

    customer_state VARCHAR(10),

    order_id VARCHAR(50) NOT NULL,

    review_score INTEGER NOT NULL,

    review_response_days NUMERIC,

    has_comment BOOLEAN NOT NULL,

    CONSTRAINT pk_mart_reviews
        PRIMARY KEY (review_id)
);

/*
===============================================================================
SECTION 34: VERIFY REVIEW MART STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that marts.mart_reviews contains the expected review-level
business attributes and metrics.

GRAIN:
------
1 row = 1 review.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'marts'
  AND table_name = 'mart_reviews'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 35: LOAD REVIEW MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_reviews with one business-ready record per review.

GRAIN:
------
1 row = 1 review.

TRANSFORMATIONS:
----------------
- Warehouse date key → actual review date
- Warehouse customer key → customer information
- Review response days → rounded to 2 decimals
===============================================================================
*/

INSERT INTO marts.mart_reviews (
    review_id,
    review_date,
    customer_id,
    customer_city,
    customer_state,
    order_id,
    review_score,
    review_response_days,
    has_comment
)

SELECT
    fr.review_id,

    dd.full_date AS review_date,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    fr.order_id,

    fr.review_score,

    CASE
        WHEN fr.review_response_days IS NOT NULL
        THEN ROUND(fr.review_response_days, 2)
        ELSE NULL
    END AS review_response_days,

    fr.has_comment

FROM warehouse.fact_reviews fr

INNER JOIN warehouse.dim_date dd
    ON fr.review_date_key = dd.date_key

INNER JOIN warehouse.fact_orders fo
    ON fr.order_key = fo.fact_order_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key;


/*
===============================================================================
SECTION 36: INVESTIGATE DUPLICATE REVIEW IDS
===============================================================================

PURPOSE:
--------
Determine whether review_id is actually unique in the source data.

No data is modified.
===============================================================================
*/

SELECT
    review_id,
    COUNT(*) AS occurrence_count
FROM staging.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC, review_id
LIMIT 20;


/*
===============================================================================
SECTION 37: INSPECT DUPLICATE REVIEW RECORDS
===============================================================================

PURPOSE:
--------
Inspect all source records for one review_id that appears multiple times.

No data is modified.
===============================================================================
*/

SELECT
    review_id,
    order_id,
    review_creation_date,
    review_answer_timestamp,
    review_score,
    review_comment_title,
    review_comment_message
FROM staging.order_reviews
WHERE review_id = '08528f70f579f0c830189efc523d2182'
ORDER BY
    order_id,
    review_creation_date;

/*
===============================================================================
SECTION 37A: VERIFY ORDER REVIEW COLUMNS
===============================================================================

PURPOSE:
--------
Inspect the exact column names available in staging.order_reviews before
investigating duplicate review IDs.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'staging'
  AND table_name = 'order_reviews'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 37B: INSPECT DUPLICATE REVIEW RECORDS
===============================================================================

PURPOSE:
--------
Inspect all source records for one review_id that appears multiple times.

No data is modified.
===============================================================================
*/

SELECT
    review_id,
    order_id,
    review_creation_timestamp,
    review_answer_timestamp,
    review_score,
    review_comment_title,
    review_comment_message,
    review_response_days
FROM staging.order_reviews
WHERE review_id = '08528f70f579f0c830189efc523d2182'
ORDER BY
    order_id,
    review_creation_timestamp;


/*
===============================================================================
SECTION 38: VALIDATE REVIEW COMPOSITE KEY
===============================================================================

PURPOSE:
--------
Verify whether order_id + review_id uniquely identifies review records.

PROPOSED GRAIN:
---------------
1 row = 1 review record associated with 1 order.
===============================================================================
*/

SELECT
    COUNT(*) AS total_review_rows,

    COUNT(*) AS distinct_order_review_pairs
FROM (
    SELECT DISTINCT
        order_id,
        review_id
    FROM staging.order_reviews
) x;


/*
===============================================================================
SECTION 39: FIX REVIEW MART PRIMARY KEY
===============================================================================

PURPOSE:
--------
Replace the incorrect review_id-only primary key with the correct composite
business key.

GRAIN:
------
1 row = 1 review record associated with 1 order.

COMPOSITE KEY:
--------------
(order_id, review_id)
===============================================================================
*/

ALTER TABLE marts.mart_reviews
DROP CONSTRAINT pk_mart_reviews;

/*
===============================================================================
SECTION 40: ADD CORRECT REVIEW MART PRIMARY KEY
===============================================================================

PURPOSE:
--------
Use order_id + review_id as the unique identifier for review records.

GRAIN:
------
1 row = 1 review record associated with 1 order.
===============================================================================
*/

ALTER TABLE marts.mart_reviews
ADD CONSTRAINT pk_mart_reviews
PRIMARY KEY (order_id, review_id);


/*
===============================================================================
SECTION 41: LOAD REVIEW MART
===============================================================================

PURPOSE:
--------
Populate marts.mart_reviews with one row per review record associated with
an order.

GRAIN:
------
1 row = 1 order + 1 review_id combination.

RESPONSE TIME:
--------------
Rounded to 2 decimal places.
===============================================================================
*/

INSERT INTO marts.mart_reviews (
    review_id,
    review_date,
    customer_id,
    customer_city,
    customer_state,
    order_id,
    review_score,
    review_response_days,
    has_comment
)

SELECT
    fr.review_id,

    dd.full_date AS review_date,

    dcu.customer_id,
    dcu.customer_city,
    dcu.customer_state,

    fr.order_id,

    fr.review_score,

    CASE
        WHEN fr.review_response_days IS NOT NULL
        THEN ROUND(fr.review_response_days, 2)
        ELSE NULL
    END AS review_response_days,

    fr.has_comment

FROM warehouse.fact_reviews fr

INNER JOIN warehouse.dim_date dd
    ON fr.review_date_key = dd.date_key

INNER JOIN warehouse.fact_orders fo
    ON fr.order_key = fo.fact_order_key

INNER JOIN warehouse.dim_customer dcu
    ON fo.customer_key = dcu.customer_key;


/*
===============================================================================
SECTION 42: VALIDATE REVIEW MART
===============================================================================

PURPOSE:
--------
Confirm that every warehouse review record reached the mart, that the
order_id + review_id grain is unique, and that review scores are valid.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.fact_reviews)
        AS warehouse_rows,

    (SELECT COUNT(*)
     FROM marts.mart_reviews)
        AS mart_rows,

    (SELECT COUNT(*)
     FROM (
         SELECT
             order_id,
             review_id
         FROM marts.mart_reviews
         GROUP BY
             order_id,
             review_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_order_review_pairs,

    (SELECT COUNT(*)
     FROM marts.mart_reviews
     WHERE review_score < 1
        OR review_score > 5)
        AS invalid_review_scores,

    (SELECT COUNT(*)
     FROM marts.mart_reviews
     WHERE review_response_days < 0)
        AS negative_response_days;


/*
===============================================================================
SECTION 43: RECONCILE REVIEW MART
===============================================================================

PURPOSE:
--------
Confirm that review counts, score totals, and response-time totals are
preserved from the warehouse fact into the business mart.
===============================================================================
*/

SELECT
    (
        SELECT COUNT(*)
        FROM warehouse.fact_reviews
    ) AS warehouse_review_count,

    (
        SELECT COUNT(*)
        FROM marts.mart_reviews
    ) AS mart_review_count,

    (
        SELECT SUM(review_score)
        FROM warehouse.fact_reviews
    ) AS warehouse_score_total,

    (
        SELECT SUM(review_score)
        FROM marts.mart_reviews
    ) AS mart_score_total,

    (
        SELECT ROUND(SUM(review_response_days), 2)
        FROM warehouse.fact_reviews
    ) AS warehouse_response_days_total,

    (
        SELECT ROUND(SUM(review_response_days), 2)
        FROM marts.mart_reviews
    ) AS mart_response_days_total;

/*
===============================================================================
SECTION 44: RESTORE FULL-PRECISION REVIEW RESPONSE DAYS
===============================================================================

PURPOSE:
--------
Replace the rounded mart values with the original warehouse precision.

WHY:
----
Analytical measures should retain their source precision. Presentation
rounding can be handled later in Power BI.

No review records are added or removed.
===============================================================================
*/

UPDATE marts.mart_reviews mr

SET review_response_days = fr.review_response_days

FROM warehouse.fact_reviews fr

WHERE mr.order_id = fr.order_id
  AND mr.review_id = fr.review_id;


 /*
===============================================================================
SECTION 45: RECONCILE REVIEW RESPONSE TIME
===============================================================================

PURPOSE:
--------
Confirm that the review response-time values in the mart now match the
warehouse values after restoring full precision.
===============================================================================
*/

SELECT
    (
        SELECT ROUND(SUM(review_response_days), 2)
        FROM warehouse.fact_reviews
    ) AS warehouse_response_days_total,

    (
        SELECT ROUND(SUM(review_response_days), 2)
        FROM marts.mart_reviews
    ) AS mart_response_days_total,

    (
        SELECT ROUND(
            AVG(review_response_days),
            2
        )
        FROM warehouse.fact_reviews
    ) AS warehouse_avg_response_days,

    (
        SELECT ROUND(
            AVG(review_response_days),
            2
        )
        FROM marts.mart_reviews
    ) AS mart_avg_response_days;


/*
===============================================================================
SECTION 46: FINAL DATA PLATFORM TABLE AUDIT
===============================================================================

PURPOSE:
--------
Confirm that all expected warehouse and mart tables exist and show their
current row counts.

LAYERS:
-------
WAREHOUSE → dimensional model + facts
MARTS    → business-ready analytical datasets
===============================================================================
*/

SELECT
    table_schema,
    table_name,
    (
        xpath(
            '/row/count/text()',
            query_to_xml(
                format(
                    'SELECT COUNT(*) AS count FROM %I.%I',
                    table_schema,
                    table_name
                ),
                false,
                true,
                ''
            )
        )
    )[1]::TEXT::BIGINT AS row_count

FROM information_schema.tables

WHERE table_schema IN ('warehouse', 'marts')
  AND table_type = 'BASE TABLE'

ORDER BY
    table_schema,
    table_name;


/*
===============================================================================
SECTION 47: FINAL WAREHOUSE KEY-INTEGRITY AUDIT
===============================================================================

PURPOSE:
--------
Verify that every required foreign-key-style reference in the fact tables
actually resolves to a corresponding dimension record.

No data is modified.

EXPECTED:
---------
All orphan counts should be 0.
===============================================================================
*/

SELECT

    /* fact_order_items */
    (
        SELECT COUNT(*)
        FROM warehouse.fact_order_items foi
        LEFT JOIN warehouse.dim_customer dc
            ON foi.customer_key = dc.customer_key
        WHERE dc.customer_key IS NULL
    ) AS orphan_order_item_customers,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_order_items foi
        LEFT JOIN warehouse.dim_product dp
            ON foi.product_key = dp.product_key
        WHERE dp.product_key IS NULL
    ) AS orphan_order_item_products,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_order_items foi
        LEFT JOIN warehouse.dim_seller ds
            ON foi.seller_key = ds.seller_key
        WHERE ds.seller_key IS NULL
    ) AS orphan_order_item_sellers,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_order_items foi
        LEFT JOIN warehouse.dim_date dd
            ON foi.order_date_key = dd.date_key
        WHERE dd.date_key IS NULL
    ) AS orphan_order_item_dates,

    /* fact_orders */
    (
        SELECT COUNT(*)
        FROM warehouse.fact_orders fo
        LEFT JOIN warehouse.dim_customer dc
            ON fo.customer_key = dc.customer_key
        WHERE dc.customer_key IS NULL
    ) AS orphan_order_customers,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_orders fo
        LEFT JOIN warehouse.dim_date dd
            ON fo.order_date_key = dd.date_key
        WHERE dd.date_key IS NULL
    ) AS orphan_order_dates,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_orders fo
        LEFT JOIN warehouse.dim_date dd
            ON fo.delivery_date_key = dd.date_key
        WHERE fo.delivery_date_key IS NOT NULL
          AND dd.date_key IS NULL
    ) AS orphan_delivery_dates,

    /* fact_payments */
    (
        SELECT COUNT(*)
        FROM warehouse.fact_payments fp
        LEFT JOIN warehouse.fact_orders fo
            ON fp.order_key = fo.fact_order_key
        WHERE fo.fact_order_key IS NULL
    ) AS orphan_payment_orders,

    /* fact_reviews */
    (
        SELECT COUNT(*)
        FROM warehouse.fact_reviews fr
        LEFT JOIN warehouse.fact_orders fo
            ON fr.order_key = fo.fact_order_key
        WHERE fo.fact_order_key IS NULL
    ) AS orphan_review_orders,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_reviews fr
        LEFT JOIN warehouse.dim_date dd
            ON fr.review_date_key = dd.date_key
        WHERE dd.date_key IS NULL
    ) AS orphan_review_dates,

    (
        SELECT COUNT(*)
        FROM warehouse.fact_reviews fr
        LEFT JOIN warehouse.dim_date dd
            ON fr.answer_date_key = dd.date_key
        WHERE fr.answer_date_key IS NOT NULL
          AND dd.date_key IS NULL
    ) AS orphan_answer_dates;


/*
===============================================================================
SECTION 48: FINAL FINANCIAL RECONCILIATION
===============================================================================

PURPOSE:
--------
Confirm that the transaction-level sales mart and the aggregated customer
and seller marts preserve identical financial totals.

This is the final monetary consistency check before BI consumption.
===============================================================================
*/

SELECT
    (
        SELECT ROUND(SUM(item_total), 2)
        FROM marts.mart_sales
    ) AS sales_mart_total_value,

    (
        SELECT ROUND(SUM(total_order_value), 2)
        FROM marts.mart_customer
    ) AS customer_mart_total_value,

    (
        SELECT ROUND(SUM(total_order_value), 2)
        FROM marts.mart_seller_performance
    ) AS seller_mart_total_value,

    (
        SELECT ROUND(SUM(freight_value), 2)
        FROM marts.mart_sales
    ) AS sales_mart_freight,

    (
        SELECT ROUND(SUM(total_freight), 2)
        FROM marts.mart_customer
    ) AS customer_mart_freight,

    (
        SELECT ROUND(SUM(total_freight), 2)
        FROM marts.mart_seller_performance
    ) AS seller_mart_freight;