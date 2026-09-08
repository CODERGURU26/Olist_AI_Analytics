/*
===============================================================================
PROJECT: Olist AI Analytics & Decision Intelligence Platform
DATABASE: olist_ecommerce
FILE: 02_staging_tables.sql

SECTION 1: STAGING ORDERS
===============================================================================

PURPOSE:
--------
Create a cleaned and standardized version of the raw `public.orders` table.

RAW SOURCE:
-----------
public.orders

TARGET:
-------
staging.orders

DESIGN PRINCIPLE:
-----------------
The RAW `public` tables remain untouched.
All transformations happen inside the `staging` schema.

TRANSFORMATIONS:
----------------
1. Standardize timestamp columns.
2. Rename timestamp fields for clarity.
3. Preserve NULL delivery dates.
4. Prepare the table for downstream warehouse modeling.

===============================================================================
*/

CREATE TABLE staging.orders AS

SELECT
    order_id,
    customer_id,
    order_status,

    order_purchase_timestamp::timestamp
        AS purchase_timestamp,

    order_approved_at::timestamp
        AS approved_timestamp,

    order_delivered_carrier_date::timestamp
        AS delivered_carrier_timestamp,

    order_delivered_customer_date::timestamp
        AS delivered_customer_timestamp,

    order_estimated_delivery_date::timestamp
        AS estimated_delivery_timestamp

FROM public.orders;

/*
===============================================================================
SECTION 2: VALIDATE STAGING ORDERS
===============================================================================
*/

SELECT COUNT(*) AS total_orders
FROM staging.orders;

SELECT *
FROM staging.orders
LIMIT 10;

/*
===============================================================================
SECTION 3: ADD BUSINESS LOGIC COLUMNS
===============================================================================

PURPOSE:
--------
Add derived columns that will be reused throughout the analytics system.

COLUMNS:
--------
delivery_days
    Number of days between purchase and customer delivery.

is_delivered
    TRUE when a customer delivery timestamp exists.

is_cancelled
    TRUE when order_status = 'canceled'.

is_late
    TRUE when the actual delivery date is after the estimated delivery date.

IMPORTANT:
----------
NULL delivery dates are preserved.
We do not replace missing dates with artificial values.
===============================================================================
*/

ALTER TABLE staging.orders
ADD COLUMN delivery_days NUMERIC,
ADD COLUMN is_delivered BOOLEAN,
ADD COLUMN is_cancelled BOOLEAN,
ADD COLUMN is_late BOOLEAN;

UPDATE staging.orders
SET
    delivery_days =
        CASE
            WHEN delivered_customer_timestamp IS NOT NULL
            THEN EXTRACT(
                EPOCH FROM
                (
                    delivered_customer_timestamp
                    - purchase_timestamp
                )
            ) / 86400
            ELSE NULL
        END,

    is_delivered =
        delivered_customer_timestamp IS NOT NULL,

    is_cancelled =
        order_status = 'canceled',

    is_late =
        CASE
            WHEN delivered_customer_timestamp IS NOT NULL
             AND estimated_delivery_timestamp IS NOT NULL
            THEN delivered_customer_timestamp
                 > estimated_delivery_timestamp
            ELSE FALSE
        END;

/*
===============================================================================
SECTION 4: STAGING ORDERS QUALITY CHECK
===============================================================================
*/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE is_delivered = TRUE
    ) AS delivered_orders,

    COUNT(*) FILTER (
        WHERE is_cancelled = TRUE
    ) AS cancelled_orders,

    COUNT(*) FILTER (
        WHERE is_late = TRUE
    ) AS late_orders,

    ROUND(
        AVG(delivery_days)::numeric,
        2
    ) AS average_delivery_days

FROM staging.orders;

SELECT
    order_id,
    order_status,
    purchase_timestamp,
    delivered_customer_timestamp,
    estimated_delivery_timestamp,
    delivery_days,
    is_delivered,
    is_cancelled,
    is_late
FROM staging.orders
LIMIT 20;

/*
===============================================================================
SECTION 5: INSPECT RAW ORDERS COLUMN TYPES
===============================================================================
*/

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'orders'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 6: ADD ORDER STAGE CLASSIFICATION
===============================================================================

PURPOSE:
--------
Create a standardized business classification for each order.

This classification will later support:
- Funnel analysis
- Operations dashboards
- KPI calculations
- AI-agent explanations
===============================================================================
*/

ALTER TABLE staging.orders
ADD COLUMN order_stage VARCHAR(30);


/*
===============================================================================
SECTION 7: POPULATE ORDER STAGE
===============================================================================
*/

UPDATE staging.orders
SET order_stage =
    CASE
        WHEN order_status = 'delivered'
            THEN 'Delivered'

        WHEN order_status = 'shipped'
            THEN 'Shipped'

        WHEN order_status = 'canceled'
            THEN 'Cancelled'

        WHEN order_status = 'unavailable'
            THEN 'Unavailable'

        WHEN order_status = 'invoiced'
            THEN 'Invoiced'

        WHEN order_status = 'processing'
            THEN 'Processing'

        WHEN order_status = 'approved'
            THEN 'Approved'

        ELSE 'Other'
    END;

/*
===============================================================================
SECTION 8: VALIDATE ORDER STAGES
===============================================================================
*/

SELECT
    order_status,
    order_stage,
    COUNT(*) AS order_count
FROM staging.orders
GROUP BY
    order_status,
    order_stage
ORDER BY order_count DESC;

/*
===============================================================================
SECTION 9: INVESTIGATE DELIVERY STATUS CONSISTENCY
===============================================================================

PURPOSE:
--------
Compare the order_status value with the actual customer delivery timestamp.

We expect delivered orders to have a delivery timestamp.
This check identifies any exceptions.
===============================================================================
*/

SELECT
    order_status,
    is_delivered,
    COUNT(*) AS order_count
FROM staging.orders
GROUP BY
    order_status,
    is_delivered
ORDER BY
    order_status,
    is_delivered;

/*
===============================================================================
SECTION 10: FIND DELIVERED ORDERS WITHOUT DELIVERY TIMESTAMP
===============================================================================
*/

SELECT
    order_id,
    customer_id,
    order_status,
    purchase_timestamp,
    delivered_customer_timestamp
FROM staging.orders
WHERE order_status = 'delivered'
  AND delivered_customer_timestamp IS NULL;

/*
===============================================================================
SECTION 10B: FIND NON-DELIVERED ORDERS WITH DELIVERY TIMESTAMP
===============================================================================

PURPOSE:
--------
Identify orders whose status is NOT 'delivered' but which nevertheless have
a customer delivery timestamp.

This helps us determine the correct business definition of `is_delivered`.
===============================================================================
*/

SELECT
    order_id,
    customer_id,
    order_status,
    purchase_timestamp,
    delivered_customer_timestamp
FROM staging.orders
WHERE order_status <> 'delivered'
  AND delivered_customer_timestamp IS NOT NULL;

/*
===============================================================================
SECTION 10C: DELIVERY STATUS CONSISTENCY MATRIX
===============================================================================

PURPOSE:
--------
Compare the declared order status against the presence of a delivery
timestamp.

This gives us four possible scenarios:

1. Delivered + timestamp
2. Delivered + no timestamp
3. Not delivered + timestamp
4. Not delivered + no timestamp
===============================================================================
*/

SELECT
    CASE
        WHEN order_status = 'delivered'
             AND delivered_customer_timestamp IS NOT NULL
            THEN 'Delivered + Timestamp'

        WHEN order_status = 'delivered'
             AND delivered_customer_timestamp IS NULL
            THEN 'Delivered + No Timestamp'

        WHEN order_status <> 'delivered'
             AND delivered_customer_timestamp IS NOT NULL
            THEN 'Not Delivered Status + Timestamp'

        ELSE 'Not Delivered + No Timestamp'
    END AS consistency_group,

    COUNT(*) AS order_count

FROM staging.orders

GROUP BY consistency_group

ORDER BY consistency_group;

/*
===============================================================================
SECTION 11: ADD DELIVERY TIMESTAMP AVAILABILITY FLAG
===============================================================================

PURPOSE:
--------
Separate the business delivery status from the physical availability of a
delivery timestamp.

is_delivered:
    Based on the business order status.

has_delivery_timestamp:
    Based on whether a customer delivery timestamp exists.

This allows us to identify data inconsistencies without losing information.
===============================================================================
*/

ALTER TABLE staging.orders
ADD COLUMN has_delivery_timestamp BOOLEAN;

/*
===============================================================================
SECTION 12: STANDARDIZE DELIVERY FLAGS
===============================================================================
*/

UPDATE staging.orders
SET
    is_delivered =
        order_status = 'delivered',

    has_delivery_timestamp =
        delivered_customer_timestamp IS NOT NULL;

/*
===============================================================================
SECTION 13: VALIDATE DELIVERY FLAGS
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
        WHERE is_delivered = FALSE
          AND has_delivery_timestamp = TRUE
    ) AS not_delivered_with_timestamp

FROM staging.orders;

/*
===============================================================================
SECTION 14: ADD PENDING DELIVERY FLAG
===============================================================================

PURPOSE:
--------
Distinguish orders that are not late from orders that simply have not been
delivered yet.

This prevents the analytics layer from treating undelivered orders as
successfully on-time.
===============================================================================
*/

ALTER TABLE staging.orders
ADD COLUMN is_pending_delivery BOOLEAN;

/*
===============================================================================
SECTION 15: POPULATE PENDING DELIVERY FLAG
===============================================================================
*/

UPDATE staging.orders
SET is_pending_delivery =
    order_status NOT IN (
        'delivered',
        'canceled',
        'unavailable'
    );

/*
===============================================================================
SECTION 16: VALIDATE DELIVERY STATUS FLAGS
===============================================================================
*/

SELECT
    order_status,
    COUNT(*) AS order_count,

    COUNT(*) FILTER (
        WHERE is_delivered
    ) AS delivered,

    COUNT(*) FILTER (
        WHERE is_late
    ) AS late,

    COUNT(*) FILTER (
        WHERE is_pending_delivery
    ) AS pending_delivery

FROM staging.orders

GROUP BY order_status

ORDER BY order_count DESC;

/*
===============================================================================
SECTION 17: CORRECT LATE DELIVERY LOGIC
===============================================================================

PURPOSE:
--------
An order is considered late only when it was actually marked as delivered
and the actual customer delivery date exceeded the estimated delivery date.

Cancelled, unavailable, and other non-delivered orders are not classified
as late deliveries.
===============================================================================
*/

UPDATE staging.orders
SET is_late =
    CASE
        WHEN order_status = 'delivered'
         AND delivered_customer_timestamp IS NOT NULL
         AND estimated_delivery_timestamp IS NOT NULL
         AND delivered_customer_timestamp > estimated_delivery_timestamp
        THEN TRUE
        ELSE FALSE
    END;

/*
===============================================================================
SECTION 18: FINAL VALIDATION OF ORDER FLAGS
===============================================================================
*/

SELECT
    order_status,
    COUNT(*) AS order_count,
    COUNT(*) FILTER (WHERE is_delivered) AS delivered,
    COUNT(*) FILTER (WHERE is_late) AS late,
    COUNT(*) FILTER (WHERE is_pending_delivery) AS pending_delivery
FROM staging.orders
GROUP BY order_status
ORDER BY order_count DESC;

/*
===============================================================================
SECTION 19: DELIVERY KPI VALIDATION
===============================================================================

PURPOSE:
--------
Calculate initial operational KPIs from the staging orders table.
===============================================================================
*/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
    ) AS delivered_orders,

    COUNT(*) FILTER (
        WHERE is_late
    ) AS late_delivered_orders,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE is_late)
        / NULLIF(
            COUNT(*) FILTER (WHERE order_status = 'delivered'),
            0
        ),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(delivery_days)
            FILTER (WHERE order_status = 'delivered'),
        2
    ) AS avg_delivery_days

FROM staging.orders;

/*
===============================================================================
SECTION 20: CREATE STAGING CUSTOMERS
===============================================================================

PURPOSE:
--------
Create the standardized customer staging table from the raw customers table.

RAW SOURCE:
-----------
public.customers

TARGET:
-------
staging.customers

BUSINESS PURPOSE:
-----------------
This table will later support:

- Customer analytics
- Customer retention
- Cohort analysis
- Customer segmentation
- Customer-level KPIs
===============================================================================
*/

CREATE TABLE staging.customers AS

SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    TRIM(customer_city) AS customer_city,
    UPPER(TRIM(customer_state)) AS customer_state

FROM public.customers;


/*
===============================================================================
SECTION 21: VALIDATE STAGING CUSTOMERS
===============================================================================
*/

SELECT COUNT(*) AS total_customers
FROM staging.customers;

SELECT *
FROM staging.customers
LIMIT 10;

/*
===============================================================================
SECTION 22: CHECK CUSTOMER STATES
===============================================================================

PURPOSE:
--------
Verify that customer state values were standardized to uppercase.
===============================================================================
*/

SELECT
    customer_state,
    COUNT(*) AS customer_count
FROM staging.customers
GROUP BY customer_state
ORDER BY customer_count DESC;


/*
===============================================================================
SECTION 23: VALIDATE CUSTOMER ROW COUNT
===============================================================================

PURPOSE:
--------
Ensure that the staging transformation did not add or remove any customer
records compared with the RAW layer.
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.customers)  AS raw_customers,
    (SELECT COUNT(*) FROM staging.customers) AS staging_customers;

/*
===============================================================================
SECTION 24: CHECK CUSTOMER DATA COMPLETENESS
===============================================================================

PURPOSE:
--------
Check for NULL values in important customer attributes.
===============================================================================
*/

SELECT
    COUNT(*) AS total_customers,
    COUNT(customer_id) AS customer_id_present,
    COUNT(customer_unique_id) AS unique_customer_id_present,
    COUNT(customer_zip_code_prefix) AS zip_present,
    COUNT(customer_city) AS city_present,
    COUNT(customer_state) AS state_present
FROM staging.customers;

/*
===============================================================================
SECTION 25: CHECK BLANK CUSTOMER ATTRIBUTES
===============================================================================

PURPOSE:
--------
Identify empty-string customer cities or states after trimming.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE customer_city = ''
    ) AS blank_cities,

    COUNT(*) FILTER (
        WHERE customer_state = ''
    ) AS blank_states
FROM staging.customers;

/*
===============================================================================
SECTION 26: CREATE STAGING ORDER ITEMS
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw order_items table.

RAW SOURCE:
-----------
public.order_items

TARGET:
-------
staging.order_items

BUSINESS PURPOSE:
-----------------
This table will support:

- Revenue analysis
- Average Order Value (AOV)
- Product performance
- Seller performance
- Category performance
- Order-level financial analysis

TRANSFORMATIONS:
----------------
1. Preserve the transactional identifiers.
2. Standardize the shipping-limit timestamp.
3. Convert monetary fields to numeric.
4. Create item_total = price + freight_value.

IMPORTANT:
----------
The RAW public.order_items table remains unchanged.
===============================================================================
*/

CREATE TABLE staging.order_items AS

SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,

    shipping_limit_date::timestamp
        AS shipping_limit_timestamp,

    price::numeric
        AS price,

    freight_value::numeric
        AS freight_value,

    (
        price::numeric
        + freight_value::numeric
    ) AS item_total

FROM public.order_items;

/*
===============================================================================
SECTION 27: VALIDATE ORDER ITEMS ROW COUNT
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.order_items)  AS raw_order_items,
    (SELECT COUNT(*) FROM staging.order_items) AS staging_order_items;

/*
===============================================================================
SECTION 28: INSPECT STAGING ORDER ITEMS
===============================================================================
*/

SELECT *
FROM staging.order_items
LIMIT 10;

/*
===============================================================================
SECTION 29: VALIDATE ORDER ITEM TOTALS
===============================================================================

PURPOSE:
--------
Verify that item_total correctly represents:

    product price + freight value
===============================================================================
*/

SELECT
    COUNT(*) AS total_items,

    ROUND(SUM(price), 2) AS total_product_value,

    ROUND(SUM(freight_value), 2) AS total_freight_value,

    ROUND(SUM(item_total), 2) AS total_item_value

FROM staging.order_items;

/*
===============================================================================
SECTION 30: CHECK ITEM TOTAL CALCULATION
===============================================================================

PURPOSE:
--------
Ensure item_total equals price + freight_value for every record.
===============================================================================
*/

SELECT COUNT(*) AS calculation_errors
FROM staging.order_items
WHERE item_total <> (price + freight_value);


/*
===============================================================================
SECTION 31: CHECK ORDER ITEM COMPLETENESS
===============================================================================
*/

SELECT
    COUNT(*) AS total_items,

    COUNT(order_id) AS order_id_present,

    COUNT(order_item_id) AS item_id_present,

    COUNT(product_id) AS product_id_present,

    COUNT(seller_id) AS seller_id_present,

    COUNT(price) AS price_present,

    COUNT(freight_value) AS freight_present,

    COUNT(item_total) AS item_total_present

FROM staging.order_items;

/*
===============================================================================
SECTION 32: VALIDATE ORDER ITEM → ORDER RELATIONSHIP
===============================================================================
*/

SELECT COUNT(*) AS orphan_orders
FROM staging.order_items oi
LEFT JOIN staging.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

/*
===============================================================================
SECTION 33: CREATE STAGING ORDER PAYMENTS
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw order_payments table.

RAW SOURCE:
-----------
public.order_payments

TARGET:
-------
staging.order_payments

BUSINESS PURPOSE:
-----------------
This table will support:

- Payment analysis
- Revenue reconciliation
- Payment-method analysis
- Installment analysis
- Average payment value
- Order-level financial metrics

TRANSFORMATIONS:
----------------
1. Preserve order and payment identifiers.
2. Preserve payment method.
3. Standardize payment amount as NUMERIC.
4. Preserve installment information.

IMPORTANT:
----------
The RAW public.order_payments table remains unchanged.
===============================================================================
*/

CREATE TABLE staging.order_payments AS

SELECT
    order_id,
    payment_sequential,
    TRIM(payment_type) AS payment_type,
    payment_installments,
    payment_value::numeric AS payment_value

FROM public.order_payments;

/*
===============================================================================
SECTION 34: VALIDATE PAYMENT ROW COUNT
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.order_payments)
        AS raw_payments,

    (SELECT COUNT(*) FROM staging.order_payments)
        AS staging_payments;


/*
===============================================================================
SECTION 35: CHECK PAYMENT DATA COMPLETENESS
===============================================================================
*/

SELECT
    COUNT(*) AS total_payments,

    COUNT(order_id) AS order_id_present,

    COUNT(payment_sequential) AS sequence_present,

    COUNT(payment_type) AS payment_type_present,

    COUNT(payment_installments) AS installments_present,

    COUNT(payment_value) AS payment_value_present

FROM staging.order_payments;

/*
===============================================================================
SECTION 36: ANALYZE PAYMENT METHODS
===============================================================================

PURPOSE:
--------
Understand how customers are paying for their orders.

This will later become a Power BI KPI/visualization.
===============================================================================
*/

SELECT
    payment_type,
    COUNT(*) AS payment_count,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(AVG(payment_value), 2) AS average_payment_value

FROM staging.order_payments

GROUP BY payment_type

ORDER BY total_payment_value DESC;

/*
===============================================================================
SECTION 37: VALIDATE PAYMENT VALUES
===============================================================================

PURPOSE:
--------
Check whether payment values contain negative or zero amounts.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE payment_value < 0
    ) AS negative_payments,

    COUNT(*) FILTER (
        WHERE payment_value = 0
    ) AS zero_payments,

    COUNT(*) FILTER (
        WHERE payment_value > 0
    ) AS positive_payments

FROM staging.order_payments;

/*
===============================================================================
SECTION 38: VALIDATE PAYMENT → ORDER RELATIONSHIP
===============================================================================

PURPOSE:
--------
Ensure every payment record belongs to a valid order.
===============================================================================
*/

SELECT COUNT(*) AS orphan_payments

FROM staging.order_payments p

LEFT JOIN staging.orders o
    ON p.order_id = o.order_id

WHERE o.order_id IS NULL;

/*
===============================================================================
SECTION 39: ANALYZE PAYMENT INSTALLMENTS
===============================================================================

PURPOSE:
--------
Understand how frequently customers use installment payments.
===============================================================================
*/

SELECT
    payment_installments,
    COUNT(*) AS payment_count,
    ROUND(SUM(payment_value), 2) AS total_payment_value

FROM staging.order_payments

GROUP BY payment_installments

ORDER BY payment_installments;

/*
===============================================================================
SECTION 40: INVESTIGATE ZERO-INSTALLMENT PAYMENTS
===============================================================================

PURPOSE:
--------
Identify payment records where payment_installments = 0.

This helps determine whether zero installments are valid source-system values
or a data-quality issue.
===============================================================================
*/

SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
FROM staging.order_payments
WHERE payment_installments = 0;

/*
===============================================================================
SECTION 42: VALIDATE PAYMENT → ORDER RELATIONSHIP
===============================================================================

PURPOSE:
--------
Ensure every payment record belongs to a valid order.
===============================================================================
*/

SELECT COUNT(*) AS orphan_payments
FROM staging.order_payments p
LEFT JOIN staging.orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

/*
===============================================================================
SECTION 42: PAYMENT VALUE QUALITY CHECK
===============================================================================

PURPOSE:
--------
Verify the staging payment values contain no negative amounts and identify
zero-value payments separately.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE payment_value < 0
    ) AS negative_payments,

    COUNT(*) FILTER (
        WHERE payment_value = 0
    ) AS zero_payments,

    COUNT(*) FILTER (
        WHERE payment_value > 0
    ) AS positive_payments

FROM staging.order_payments;

/*
===============================================================================
SECTION 43: CREATE STAGING ORDER REVIEWS
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw order_reviews table.

RAW SOURCE:
-----------
public.order_reviews

TARGET:
-------
staging.order_reviews

BUSINESS PURPOSE:
-----------------
This table will support:

- Customer satisfaction analysis
- Review-score KPIs
- Product quality analysis
- Seller performance analysis
- Delivery vs. review analysis
- Customer experience analytics
- AI-generated business insights

TRANSFORMATIONS:
----------------
1. Preserve review_id and order_id.
2. Preserve the review score.
3. Standardize review dates as timestamps.
4. Remove unnecessary leading/trailing whitespace from text fields.
5. Convert empty text values to NULL.
6. Preserve NULL comments because written feedback is optional.

IMPORTANT:
----------
The RAW public.order_reviews table remains untouched.
===============================================================================
*/

CREATE TABLE staging.order_reviews AS

SELECT
    review_id,
    order_id,

    review_score,

    NULLIF(TRIM(review_comment_title), '')
        AS review_comment_title,

    NULLIF(TRIM(review_comment_message), '')
        AS review_comment_message,

    review_creation_date::timestamp
        AS review_creation_timestamp,

    review_answer_timestamp::timestamp
        AS review_answer_timestamp

FROM public.order_reviews;

/*
===============================================================================
SECTION 44: VALIDATE REVIEW ROW COUNT
===============================================================================

PURPOSE:
--------
Ensure the staging transformation did not add or remove review records.

EXPECTED:
---------
Raw review count = staging review count
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.order_reviews)
        AS raw_reviews,

    (SELECT COUNT(*) FROM staging.order_reviews)
        AS staging_reviews;

/*
===============================================================================
SECTION 45: CHECK REVIEW DATA COMPLETENESS
===============================================================================

PURPOSE:
--------
Check for NULL values in important review fields.

NOTE:
-----
Review comments are optional, so NULL comment values are acceptable.

The identifiers and review score are the important fields for analytics.
===============================================================================
*/

SELECT
    COUNT(*) AS total_reviews,

    COUNT(review_id) AS review_id_present,

    COUNT(order_id) AS order_id_present,

    COUNT(review_score) AS review_score_present,

    COUNT(review_creation_timestamp)
        AS creation_date_present,

    COUNT(review_answer_timestamp)
        AS answer_date_present

FROM staging.order_reviews;

/*
===============================================================================
SECTION 46: VALIDATE REVIEW SCORE RANGE
===============================================================================

PURPOSE:
--------
Ensure every review score falls within the valid business range.

BUSINESS RULE:
--------------
1 <= review_score <= 5

EXPECTED:
---------
0 invalid records
===============================================================================
*/

SELECT COUNT(*) AS invalid_review_scores

FROM staging.order_reviews

WHERE review_score < 1
   OR review_score > 5;


/*
===============================================================================
SECTION 47: REVIEW SCORE DISTRIBUTION
===============================================================================

PURPOSE:
--------
Measure the distribution of customer satisfaction scores.

This will later be used in:
- Power BI
- Customer experience analysis
- Seller analysis
- Product analysis
===============================================================================
*/

SELECT
    review_score,

    COUNT(*) AS review_count,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_reviews

FROM staging.order_reviews

GROUP BY review_score

ORDER BY review_score;

/*
===============================================================================
SECTION 48: VALIDATE REVIEW → ORDER RELATIONSHIP
===============================================================================

PURPOSE:
--------
Ensure every review belongs to a valid order.

RELATIONSHIP:

staging.order_reviews.order_id
            |
            v
staging.orders.order_id

EXPECTED:
---------
0 orphan reviews
===============================================================================
*/

SELECT COUNT(*) AS orphan_reviews

FROM staging.order_reviews r

LEFT JOIN staging.orders o
    ON r.order_id = o.order_id

WHERE o.order_id IS NULL;

/*
===============================================================================
SECTION 49: VALIDATE REVIEW COMMENT CLEANING
===============================================================================

PURPOSE:
--------
Ensure empty review comments were converted to NULL during staging.

EXPECTED:
---------
0 blank strings.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE review_comment_title = ''
    ) AS blank_titles,

    COUNT(*) FILTER (
        WHERE review_comment_message = ''
    ) AS blank_messages

FROM staging.order_reviews;

/*
===============================================================================
SECTION 50: MEASURE WRITTEN FEEDBACK AVAILABILITY
===============================================================================

PURPOSE:
--------
Measure how many customers provided written review feedback.

This allows us to distinguish:
- Reviews with written feedback
- Reviews with score only
===============================================================================
*/

SELECT
    COUNT(*) AS total_reviews,

    COUNT(*) FILTER (
        WHERE review_comment_title IS NOT NULL
           OR review_comment_message IS NOT NULL
    ) AS reviews_with_comments,

    COUNT(*) FILTER (
        WHERE review_comment_title IS NULL
          AND review_comment_message IS NULL
    ) AS score_only_reviews

FROM staging.order_reviews;

/*
===============================================================================
SECTION 51A: ADD REVIEW RESPONSE TIME
===============================================================================

PURPOSE:
--------
Calculate the time taken to respond to customer reviews.
===============================================================================
*/

ALTER TABLE staging.order_reviews
ADD COLUMN review_response_days NUMERIC;

/*
===============================================================================
SECTION 51B: CALCULATE REVIEW RESPONSE TIME
===============================================================================
*/

UPDATE staging.order_reviews
SET review_response_days =
    CASE
        WHEN review_creation_timestamp IS NOT NULL
         AND review_answer_timestamp IS NOT NULL
        THEN EXTRACT(
            EPOCH FROM (
                review_answer_timestamp
                - review_creation_timestamp
            )
        ) / 86400

        ELSE NULL
    END;

/*
===============================================================================
SECTION 51C: VALIDATE REVIEW RESPONSE TIME
===============================================================================
*/

SELECT
    COUNT(*) AS total_reviews,

    COUNT(review_response_days)
        AS reviews_with_response_time,

    ROUND(
        AVG(review_response_days),
        2
    ) AS average_response_days

FROM staging.order_reviews;

/*
===============================================================================
SECTION 51D: CHECK INVALID REVIEW RESPONSE TIMES
===============================================================================

BUSINESS RULE:

review_answer_timestamp >= review_creation_timestamp

EXPECTED:
---------
0 invalid records
===============================================================================
*/

SELECT COUNT(*) AS invalid_response_times

FROM staging.order_reviews

WHERE review_response_days < 0;

/*
===============================================================================
SECTION 52: CREATE STAGING PRODUCTS
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw products table.

RAW SOURCE:
-----------
public.products

TARGET:
-------
staging.products

BUSINESS PURPOSE:
-----------------
This table will support:

- Product performance analysis
- Category performance
- Revenue analysis
- Product quality analysis
- Product-level KPIs
- AI business insights

TRANSFORMATIONS:
----------------
1. Preserve product identifier.
2. Preserve category name.
3. Standardize text fields.
4. Preserve product dimensions and weight.
5. Preserve NULL values where product attributes are unavailable.

IMPORTANT:
----------
The RAW public.products table remains untouched.
===============================================================================
*/

CREATE TABLE staging.products AS

SELECT
    product_id,

    NULLIF(TRIM(product_category_name), '')
        AS product_category_name,

    product_name_lenght,
    product_description_lenght,
    product_photos_qty,

    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM public.products;

/*
===============================================================================
SECTION 53: VALIDATE PRODUCT ROW COUNT
===============================================================================

PURPOSE:
--------
Ensure the staging transformation preserves the complete product dataset.
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.products)
        AS raw_products,

    (SELECT COUNT(*) FROM staging.products)
        AS staging_products;

/*
===============================================================================
SECTION 54: CHECK PRODUCT DATA COMPLETENESS
===============================================================================

PURPOSE:
--------
Measure NULL values across important product attributes.

NOTE:
-----
Product category may legitimately be NULL in the source dataset.
The staging layer preserves those NULLs rather than inventing categories.
===============================================================================
*/

SELECT
    COUNT(*) AS total_products,

    COUNT(product_id) AS product_id_present,

    COUNT(product_category_name) AS category_present,

    COUNT(product_name_lenght) AS name_length_present,

    COUNT(product_description_lenght) AS description_length_present,

    COUNT(product_photos_qty) AS photos_present,

    COUNT(product_weight_g) AS weight_present,

    COUNT(product_length_cm) AS length_present,

    COUNT(product_height_cm) AS height_present,

    COUNT(product_width_cm) AS width_present

FROM staging.products;

/*
===============================================================================
SECTION 55: VALIDATE PRODUCT DIMENSIONS
===============================================================================

PURPOSE:
--------
Identify invalid negative physical measurements.

BUSINESS RULE:
--------------
Weight and physical dimensions cannot be negative.

NOTE:
-----
NULL values are not considered invalid here; they are handled separately as
missing source data.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE product_weight_g < 0
    ) AS negative_weight,

    COUNT(*) FILTER (
        WHERE product_length_cm < 0
    ) AS negative_length,

    COUNT(*) FILTER (
        WHERE product_height_cm < 0
    ) AS negative_height,

    COUNT(*) FILTER (
        WHERE product_width_cm < 0
    ) AS negative_width

FROM staging.products;

/*
===============================================================================
SECTION 56: VALIDATE PRODUCT PHOTO QUANTITY
===============================================================================

PURPOSE:
--------
Check for invalid negative photo counts.
===============================================================================
*/

SELECT COUNT(*) AS negative_photo_counts

FROM staging.products

WHERE product_photos_qty < 0;

/*
===============================================================================
SECTION 57: ANALYZE PRODUCT CATEGORY DISTRIBUTION
===============================================================================

PURPOSE:
--------
Understand how products are distributed across categories.

This will later support:
- Category revenue analysis
- Product performance
- Category KPIs
===============================================================================
*/
SELECT
    product_category_name,
    COUNT(*) AS product_count

FROM staging.products

GROUP BY product_category_name

ORDER BY product_count DESC
LIMIT 20;

/*
===============================================================================
SECTION 58: VALIDATE PRODUCT → ORDER ITEM RELATIONSHIP
===============================================================================

PURPOSE:
--------
Ensure every product referenced by an order item exists in staging.products.

RELATIONSHIP:

staging.order_items.product_id
             |
             v
staging.products.product_id

EXPECTED:
---------
0 orphan products.
===============================================================================
*/

SELECT COUNT(*) AS orphan_products

FROM staging.order_items oi

LEFT JOIN staging.products p
    ON oi.product_id = p.product_id

WHERE p.product_id IS NULL;

/*
===============================================================================
SECTION 59: CREATE STAGING SELLERS
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw sellers table.

RAW SOURCE:
-----------
public.sellers

TARGET:
-------
staging.sellers

BUSINESS PURPOSE:
-----------------
This table will support:

- Seller performance analysis
- Seller revenue analysis
- Seller order volume
- Seller geographic analysis
- Delivery performance by seller
- Seller quality analysis
- AI-generated seller insights

TRANSFORMATIONS:
----------------
1. Preserve seller identifiers.
2. Preserve ZIP-code prefix.
3. Standardize city text using TRIM().
4. Standardize state values using TRIM() and UPPER().

IMPORTANT:
----------
The RAW public.sellers table remains untouched.
===============================================================================
*/

CREATE TABLE staging.sellers AS

SELECT
    seller_id,

    seller_zip_code_prefix,

    TRIM(seller_city) AS seller_city,

    UPPER(TRIM(seller_state)) AS seller_state

FROM public.sellers;

/*
===============================================================================
SECTION 60: VALIDATE SELLER ROW COUNT
===============================================================================

PURPOSE:
--------
Ensure the staging transformation preserves every seller record.
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.sellers)
        AS raw_sellers,

    (SELECT COUNT(*) FROM staging.sellers)
        AS staging_sellers;

/*
===============================================================================
SECTION 61: CHECK SELLER DATA COMPLETENESS
===============================================================================

PURPOSE:
--------
Check for NULL values in important seller attributes.
===============================================================================
*/

SELECT
    COUNT(*) AS total_sellers,

    COUNT(seller_id) AS seller_id_present,

    COUNT(seller_zip_code_prefix) AS zip_present,

    COUNT(seller_city) AS city_present,

    COUNT(seller_state) AS state_present

FROM staging.sellers;

/*
===============================================================================
SECTION 62: CHECK BLANK SELLER ATTRIBUTES
===============================================================================

PURPOSE:
--------
Identify empty-string cities or states after standardization.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE seller_city = ''
    ) AS blank_cities,

    COUNT(*) FILTER (
        WHERE seller_state = ''
    ) AS blank_states

FROM staging.sellers;

/*
===============================================================================
SECTION 63: SELLER STATE DISTRIBUTION
===============================================================================

PURPOSE:
--------
Understand the geographic distribution of sellers.

This will later support:
- Seller geographic analysis
- Regional performance
- Revenue by seller state
===============================================================================
*/

SELECT
    seller_state,
    COUNT(*) AS seller_count

FROM staging.sellers

GROUP BY seller_state

ORDER BY seller_count DESC;

/*
===============================================================================
SECTION 64: VALIDATE SELLER → ORDER ITEM RELATIONSHIP
===============================================================================

PURPOSE:
--------
Ensure every seller referenced by an order item exists in staging.sellers.

EXPECTED:
---------
0 orphan sellers.
===============================================================================
*/

SELECT COUNT(*) AS orphan_sellers

FROM staging.order_items oi

LEFT JOIN staging.sellers s
    ON oi.seller_id = s.seller_id

WHERE s.seller_id IS NULL;

/*
===============================================================================
SECTION 65: CHECK DUPLICATE SELLER IDs
===============================================================================

PURPOSE:
--------
Ensure seller_id uniquely identifies a seller in the staging layer.
===============================================================================
*/

SELECT
    COUNT(*) AS duplicate_seller_groups

FROM (
    SELECT seller_id
    FROM staging.sellers
    GROUP BY seller_id
    HAVING COUNT(*) > 1
) d;

/*
===============================================================================
SECTION 66: CREATE STAGING GEOLOCATION
===============================================================================

PURPOSE:
--------
Create a standardized staging version of the raw geolocation table.

RAW SOURCE:
-----------
public.geolocation

TARGET:
-------
staging.geolocation

BUSINESS PURPOSE:
-----------------
This table will support:

- Geographic analysis
- Customer location analysis
- Seller location analysis
- Regional revenue analysis
- Delivery-distance analysis
- State and city performance

TRANSFORMATIONS:
----------------
1. Preserve ZIP-code prefix.
2. Rename latitude and longitude for clarity.
3. Cast geographic coordinates to NUMERIC.
4. Standardize city names using TRIM().
5. Standardize state values using TRIM() and UPPER().

IMPORTANT:
----------
The RAW public.geolocation table remains untouched.
===============================================================================
*/

CREATE TABLE staging.geolocation AS

SELECT
    geolocation_zip_code_prefix,

    geolocation_lat::numeric
        AS latitude,

    geolocation_lng::numeric
        AS longitude,

    TRIM(geolocation_city)
        AS geolocation_city,

    UPPER(TRIM(geolocation_state))
        AS geolocation_state

FROM public.geolocation;

/*
===============================================================================
SECTION 67: VALIDATE GEOLOCATION ROW COUNT
===============================================================================

PURPOSE:
--------
Ensure the staging transformation preserves the complete geolocation dataset.
===============================================================================
*/

SELECT
    (SELECT COUNT(*) FROM public.geolocation)
        AS raw_geolocation_rows,

    (SELECT COUNT(*) FROM staging.geolocation)
        AS staging_geolocation_rows;

/*
===============================================================================
SECTION 68: CHECK GEOLOCATION DATA COMPLETENESS
===============================================================================

PURPOSE:
--------
Measure missing values across the geographic attributes.
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,

    COUNT(geolocation_zip_code_prefix)
        AS zip_present,

    COUNT(latitude)
        AS latitude_present,

    COUNT(longitude)
        AS longitude_present,

    COUNT(geolocation_city)
        AS city_present,

    COUNT(geolocation_state)
        AS state_present

FROM staging.geolocation;

/*
===============================================================================
SECTION 69: VALIDATE GEOGRAPHIC COORDINATES
===============================================================================

PURPOSE:
--------
Identify geographic coordinates outside valid latitude/longitude ranges.

BUSINESS RULE:
--------------
Latitude  BETWEEN -90 AND 90
Longitude BETWEEN -180 AND 180

EXPECTED:
---------
0 invalid records.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE latitude < -90
           OR latitude > 90
    ) AS invalid_latitude,

    COUNT(*) FILTER (
        WHERE longitude < -180
           OR longitude > 180
    ) AS invalid_longitude

FROM staging.geolocation;

/*
===============================================================================
SECTION 70: CHECK BLANK GEOLOCATION ATTRIBUTES
===============================================================================

PURPOSE:
--------
Identify empty-string city or state values after standardization.
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE geolocation_city = ''
    ) AS blank_cities,

    COUNT(*) FILTER (
        WHERE geolocation_state = ''
    ) AS blank_states

FROM staging.geolocation;

/*
===============================================================================
SECTION 71: GEOLOCATION STATE DISTRIBUTION
===============================================================================

PURPOSE:
--------
Understand the distribution of geolocation records across Brazilian states.
===============================================================================
*/

SELECT
    geolocation_state,
    COUNT(*) AS location_count

FROM staging.geolocation

GROUP BY geolocation_state

ORDER BY location_count DESC;

/*
===============================================================================
SECTION 72: INSPECT GEOLOCATION SAMPLE
===============================================================================

PURPOSE:
--------
Inspect a sample of standardized geographic records.
===============================================================================
*/

SELECT
    geolocation_zip_code_prefix,
    latitude,
    longitude,
    geolocation_city,
    geolocation_state

FROM staging.geolocation

LIMIT 20;

/*
===============================================================================
SECTION 73: CHECK CITY NAME VARIATIONS
===============================================================================

PURPOSE:
--------
Identify possible duplicate city names caused by spelling, capitalization,
or accent differences.

NOTE:
-----
We are measuring the inconsistency first. We will not modify the raw data.
===============================================================================
*/

SELECT
    LOWER(geolocation_city) AS normalized_city,
    COUNT(DISTINCT geolocation_city) AS city_variants,
    COUNT(*) AS location_records
FROM staging.geolocation
GROUP BY LOWER(geolocation_city)
HAVING COUNT(DISTINCT geolocation_city) > 1
ORDER BY city_variants DESC, location_records DESC;

/*
===============================================================================
SECTION 74: INSPECT SÃO PAULO CITY VARIANTS
===============================================================================
*/

SELECT
    geolocation_city,
    COUNT(*) AS location_count
FROM staging.geolocation
WHERE LOWER(geolocation_city) LIKE '%paulo%'
GROUP BY geolocation_city
ORDER BY location_count DESC;

/*
===============================================================================
SECTION 75: IDENTIFY SUSPICIOUS CITY VALUES
===============================================================================

PURPOSE:
--------
Identify city names containing unusual characters that may indicate encoding
issues or malformed source data.

IMPORTANT:
----------
Do not modify these values in the staging layer.
They will be handled later through a standardized geography dimension.
===============================================================================
*/

SELECT
    geolocation_city,
    geolocation_state,
    COUNT(*) AS location_count
FROM staging.geolocation
WHERE geolocation_city ~ '[£�]'
GROUP BY
    geolocation_city,
    geolocation_state
ORDER BY location_count DESC;

/*
===============================================================================
SECTION 76: FINAL GEOLOCATION QUALITY CHECK
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,

    COUNT(*) FILTER (
        WHERE latitude IS NULL
    ) AS missing_latitude,

    COUNT(*) FILTER (
        WHERE longitude IS NULL
    ) AS missing_longitude,

    COUNT(*) FILTER (
        WHERE latitude < -90
           OR latitude > 90
    ) AS invalid_latitude,

    COUNT(*) FILTER (
        WHERE longitude < -180
           OR longitude > 180
    ) AS invalid_longitude

FROM staging.geolocation;

/*
===============================================================================
SECTION 78: CREATE STAGING CATEGORY TRANSLATION
===============================================================================

PURPOSE:
--------
Create a standardized lookup table that translates the original Portuguese
product category names into English.

RAW SOURCE:
-----------
public.product_category_name_translation

TARGET:
-------
staging.category_translation

BUSINESS PURPOSE:
-----------------
This table will support:

- English category reporting
- Power BI dashboards
- Category-level KPI analysis
- Product category analysis
- AI-agent responses

IMPORTANT:
----------
The RAW public table remains untouched.
===============================================================================
*/

CREATE TABLE staging.category_translation AS

SELECT
    NULLIF(TRIM(product_category_name), '')
        AS product_category_name,

    NULLIF(TRIM(product_category_name_english), '')
        AS product_category_name_english

FROM public.product_category_name_translation;

/*
===============================================================================
SECTION 79: VALIDATE CATEGORY TRANSLATION ROW COUNT
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM public.product_category_name_translation)
        AS raw_translation_rows,

    (SELECT COUNT(*)
     FROM staging.category_translation)
        AS staging_translation_rows;

/*
===============================================================================
SECTION 80: CHECK CATEGORY TRANSLATION COMPLETENESS
===============================================================================

PURPOSE:
--------
Verify that both the original category and translated category are populated.
===============================================================================
*/

SELECT
    COUNT(*) AS total_rows,

    COUNT(product_category_name)
        AS portuguese_category_present,

    COUNT(product_category_name_english)
        AS english_category_present

FROM staging.category_translation;

/*
===============================================================================
SECTION 81: CHECK DUPLICATE CATEGORY TRANSLATIONS
===============================================================================

PURPOSE:
--------
Ensure each Portuguese category maps cleanly to one English category.
===============================================================================
*/

SELECT
    product_category_name,
    COUNT(DISTINCT product_category_name_english)
        AS english_variants

FROM staging.category_translation

GROUP BY product_category_name

HAVING COUNT(DISTINCT product_category_name_english) > 1;

/*
===============================================================================
SECTION 82: INSPECT CATEGORY TRANSLATIONS
===============================================================================
*/

SELECT
    product_category_name,
    product_category_name_english

FROM staging.category_translation

ORDER BY product_category_name
LIMIT 20;