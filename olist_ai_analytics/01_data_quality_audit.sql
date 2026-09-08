/*
===============================================================================
PROJECT: Olist AI Analytics & Decision Intelligence Platform
DATABASE: olist_ecommerce
FILE: 01_data_quality_audit.sql

PURPOSE:
--------
Perform initial data-quality and integrity checks on the raw Olist datasets
loaded into the PostgreSQL database.

RAW DATA LOCATION:
------------------
All source tables are currently stored under the `public` schema.

IMPORTANT:
----------
The `public` schema represents the RAW layer and should remain unchanged.
These queries are READ-ONLY validation checks.

CHECKS INCLUDED:
----------------
1. Verify available raw tables
2. Check row counts
3. Check missing values
4. Check duplicate records
5. Validate review scores
6. Check negative monetary values
7. Check broken foreign-key relationships
8. Check invalid delivery dates

===============================================================================
*/


/*
===============================================================================
SECTION 1: VERIFY RAW TABLES
===============================================================================

Purpose:
--------
Confirm that the expected Olist tables exist in the public schema.
===============================================================================
*/

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;


/*
===============================================================================
SECTION 2: CHECK ROW COUNTS
===============================================================================

Purpose:
--------
Calculate the number of records in each raw table.

This helps verify that the CSV files were imported successfully and gives us
a baseline before building the staging and warehouse layers.
===============================================================================
*/

SELECT
    table_name,
    (xpath(
        '//*[local-name()="c"]/text()',
        query_to_xml(
            format('SELECT COUNT(*) AS c FROM public.%I', table_name),
            true,
            false,
            ''
        )
    ))[1]::text::bigint AS row_count
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;


/*
===============================================================================
SECTION 3: CHECK MISSING VALUES — ORDERS
===============================================================================

Purpose:
--------
Identify NULL values in important order-level fields.

NOTE:
-----
A missing delivery date does not automatically indicate bad data.
For example, cancelled or undelivered orders may legitimately have no
delivery timestamp.

Expected result:
----------------
All key identifiers and purchase timestamps should be populated.
Delivery date may contain NULL values.
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,
    COUNT(order_id) AS order_id_present,
    COUNT(customer_id) AS customer_id_present,
    COUNT(order_status) AS order_status_present,
    COUNT(order_purchase_timestamp) AS purchase_date_present,
    COUNT(order_delivered_customer_date) AS delivery_date_present
FROM public.orders;


/*
===============================================================================
SECTION 4: CHECK MISSING VALUES — ORDER ITEMS
===============================================================================

Purpose:
--------
Verify that every order-item record contains the key identifiers and price
information required for downstream analytics.
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,
    COUNT(order_id) AS order_id_present,
    COUNT(order_item_id) AS item_id_present,
    COUNT(product_id) AS product_id_present,
    COUNT(seller_id) AS seller_id_present,
    COUNT(price) AS price_present
FROM public.order_items;


/*
===============================================================================
SECTION 5: CHECK MISSING VALUES — PAYMENTS
===============================================================================

Purpose:
--------
Verify that payment records contain their required identifiers, payment type,
and payment value.
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,
    COUNT(order_id) AS order_id_present,
    COUNT(payment_type) AS payment_type_present,
    COUNT(payment_value) AS payment_value_present
FROM public.order_payments;


/*
===============================================================================
SECTION 6: CHECK DUPLICATE ORDER IDs
===============================================================================

Purpose:
--------
Identify order IDs that appear more than once in the orders table.

Expected result:
----------------
0 duplicate groups.

NOTE:
-----
We are checking the order ID at the order-header level. Multiple rows for an
order are expected in tables such as order_items and order_payments.
===============================================================================
*/

SELECT
    order_id,
    COUNT(*) AS occurrences
FROM public.orders
GROUP BY order_id
HAVING COUNT(*) > 1;


/*
===============================================================================
SECTION 7: CHECK DUPLICATE CUSTOMER IDs
===============================================================================

Purpose:
--------
Identify duplicate customer IDs in the customer table.

Expected result:
----------------
0 duplicate groups.
===============================================================================
*/

SELECT
    customer_id,
    COUNT(*) AS occurrences
FROM public.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;


/*
===============================================================================
SECTION 8: CHECK DUPLICATE PRODUCT IDs
===============================================================================

Purpose:
--------
Identify duplicate product IDs in the products table.

Expected result:
----------------
0 duplicate groups.
===============================================================================
*/

SELECT
    product_id,
    COUNT(*) AS occurrences
FROM public.products
GROUP BY product_id
HAVING COUNT(*) > 1;


/*
===============================================================================
SECTION 9: CHECK REVIEW SCORE DISTRIBUTION
===============================================================================

Purpose:
--------
Check the distribution of customer review scores.

Expected valid range:
---------------------
1 = very poor
2 = poor
3 = neutral
4 = good
5 = excellent

This check also gives us an initial understanding of customer satisfaction.
===============================================================================
*/

SELECT
    review_score,
    COUNT(*) AS count
FROM public.order_reviews
GROUP BY review_score
ORDER BY review_score;


/*
===============================================================================
SECTION 10: CHECK FOR NEGATIVE PRODUCT PRICES
===============================================================================

Purpose:
--------
Identify order items with a negative product price.

Expected result:
----------------
0 rows.
===============================================================================
*/

SELECT COUNT(*) AS negative_prices
FROM public.order_items
WHERE price < 0;


/*
===============================================================================
SECTION 11: CHECK FOR NEGATIVE FREIGHT VALUES
===============================================================================

Purpose:
--------
Identify order items with negative freight/shipping charges.

Expected result:
----------------
0 rows.
===============================================================================
*/

SELECT COUNT(*) AS negative_freight
FROM public.order_items
WHERE freight_value < 0;


/*
===============================================================================
SECTION 12: CHECK FOR NEGATIVE PAYMENT VALUES
===============================================================================

Purpose:
--------
Identify payment records containing negative payment amounts.

Expected result:
----------------
0 rows.
===============================================================================
*/

SELECT COUNT(*) AS negative_payments
FROM public.order_payments
WHERE payment_value < 0;


/*
===============================================================================
SECTION 13: CHECK ORPHAN ORDER ITEMS
===============================================================================

Purpose:
--------
Find order-item records whose order_id does not exist in the orders table.

This validates the relationship:

    order_items.order_id
             |
             v
       orders.order_id

Expected result:
----------------
0 orphan records.
===============================================================================
*/

SELECT COUNT(*) AS orphan_order_items
FROM public.order_items oi
LEFT JOIN public.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


/*
===============================================================================
SECTION 14: CHECK ORPHAN ORDERS
===============================================================================

Purpose:
--------
Find orders whose customer_id does not exist in the customers table.

This validates the relationship:

    orders.customer_id
           |
           v
    customers.customer_id

Expected result:
----------------
0 orphan records.
===============================================================================
*/

SELECT COUNT(*) AS orphan_orders
FROM public.orders o
LEFT JOIN public.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


/*
===============================================================================
SECTION 15: CHECK ORPHAN PRODUCTS
===============================================================================

Purpose:
--------
Find order-item records whose product_id does not exist in the products table.

This validates the relationship:

    order_items.product_id
             |
             v
       products.product_id

Expected result:
----------------
0 orphan records.
===============================================================================
*/

SELECT COUNT(*) AS orphan_products
FROM public.order_items oi
LEFT JOIN public.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


/*
===============================================================================
SECTION 16: CHECK ORPHAN SELLERS
===============================================================================

Purpose:
--------
Find order-item records whose seller_id does not exist in the sellers table.

This validates the relationship:

    order_items.seller_id
             |
             v
        sellers.seller_id

Expected result:
----------------
0 orphan records.
===============================================================================
*/

SELECT COUNT(*) AS orphan_sellers
FROM public.order_items oi
LEFT JOIN public.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/*
===============================================================================
SECTION 17: CHECK INVALID DELIVERY DATES
===============================================================================

Purpose:
--------
Identify orders where the delivery date occurs before the purchase date.

Business rule:

    delivery_date >= purchase_date

Expected result:
----------------
0 invalid records.
===============================================================================
*/

SELECT COUNT(*) AS invalid_delivery_dates
FROM public.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp;


/*
===============================================================================
SECTION 18: SUMMARY DUPLICATE CHECK — ORDERS
===============================================================================

Purpose:
--------
Return a single number representing the number of duplicate order groups.

Expected result:
----------------
0
===============================================================================
*/

SELECT
    COUNT(*) AS duplicate_order_groups
FROM (
    SELECT order_id
    FROM public.orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d;


/*
===============================================================================
SECTION 19: SUMMARY DUPLICATE CHECK — CUSTOMERS
===============================================================================

Purpose:
--------
Return a single number representing the number of duplicate customer groups.

Expected result:
----------------
0
===============================================================================
*/

SELECT
    COUNT(*) AS duplicate_customer_groups
FROM (
    SELECT customer_id
    FROM public.customers
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) d;


/*
===============================================================================
SECTION 20: SUMMARY DUPLICATE CHECK — PRODUCTS
===============================================================================

Purpose:
--------
Return a single number representing the number of duplicate product groups.

Expected result:
----------------
0
===============================================================================
*/

SELECT
    COUNT(*) AS duplicate_product_groups
FROM (
    SELECT product_id
    FROM public.products
    GROUP BY product_id
    HAVING COUNT(*) > 1
) d;


/*
===============================================================================
END OF DATA QUALITY AUDIT
===============================================================================

NEXT STEP:
----------
Create the STAGING layer.

Architecture:

    RAW
    public.*
       |
       v
    STAGING
    staging.*
       |
       v
    WAREHOUSE
    warehouse.*
       |
       v
    ANALYTICAL MARTS
    marts.*

===============================================================================
*/