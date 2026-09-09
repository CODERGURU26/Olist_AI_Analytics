/*
===============================================================================
FILE: 03_warehouse.sql

PROJECT:
Olist AI Analytics & Decision Intelligence Platform

PURPOSE:
Create the warehouse layer using a dimensional/star-schema design.

WAREHOUSE STRUCTURE:

RAW
public
   ↓
STAGING
staging
   ↓
WAREHOUSE
warehouse

CURRENT STEP:
Create the customer dimension.

===============================================================================
*/


/*
/*
===============================================================================
SECTION 1: CREATE WAREHOUSE SCHEMA
===============================================================================

PURPOSE:
--------
Create the warehouse schema that will contain our dimensional data model.

ARCHITECTURE:

public
  ↓
staging
  ↓
warehouse

===============================================================================
*/


CREATE SCHEMA IF NOT EXISTS warehouse;


/*
===============================================================================
SECTION 2: VERIFY WAREHOUSE SCHEMA
===============================================================================
*/

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'warehouse';

/*
===============================================================================
SECTION 3: CREATE CUSTOMER DIMENSION
===============================================================================

PURPOSE:
--------
Create the customer dimension for the warehouse.

GRAIN:
------
One row = one customer record.

KEYS:
-----
customer_key:
    Warehouse-generated surrogate key.

customer_id:
    Original Olist source-system identifier.

customer_unique_id:
    Olist business/customer identity.

SOURCE:
-------
staging.customers

TARGET:
-------
warehouse.dim_customer
===============================================================================
*/

CREATE TABLE warehouse.dim_customer (

    customer_key BIGINT GENERATED ALWAYS AS IDENTITY,

    customer_id VARCHAR(50) NOT NULL,

    customer_unique_id VARCHAR(50) NOT NULL,

    customer_zip_code_prefix INTEGER,

    customer_city VARCHAR(100),

    customer_state VARCHAR(10),

    CONSTRAINT pk_dim_customer
        PRIMARY KEY (customer_key)
);

/*
===============================================================================
SECTION 4: VERIFY CUSTOMER DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that the dimension contains the expected columns and data types.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_customer'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 5: LOAD CUSTOMER DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_customer using the validated staging.customers table.

IMPORTANT:
----------
customer_key is NOT inserted manually.
PostgreSQL generates the surrogate key automatically.
===============================================================================
*/

INSERT INTO warehouse.dim_customer (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM staging.customers;

/*
===============================================================================
SECTION 6: INSPECT CUSTOMER DIMENSION
===============================================================================

PURPOSE:
--------
Verify that the warehouse-generated customer_key values were created
correctly and that the source customer information was loaded as expected.
===============================================================================
*/

SELECT
    customer_key,
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM warehouse.dim_customer
ORDER BY customer_key
LIMIT 10;

/*
===============================================================================
SECTION 7: VALIDATE CUSTOMER DIMENSION
===============================================================================

PURPOSE:
--------
Perform the final validation of warehouse.dim_customer.

CHECKS:
-------
1. Row count matches staging.
2. customer_key is unique.
3. customer_id has no duplicates.
4. customer_unique_id has no NULL values.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.customers)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.dim_customer)
        AS warehouse_rows,

    (SELECT COUNT(DISTINCT customer_key)
     FROM warehouse.dim_customer)
        AS unique_customer_keys,

    (SELECT COUNT(*)
     FROM (
         SELECT customer_id
         FROM warehouse.dim_customer
         GROUP BY customer_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_customer_ids,

    (SELECT COUNT(*)
     FROM warehouse.dim_customer
     WHERE customer_unique_id IS NULL)
        AS null_unique_customer_ids;

/*

/*
===============================================================================
SECTION 8: CREATE PRODUCT DIMENSION
===============================================================================

PURPOSE:
--------
Create the warehouse product dimension.

GRAIN:
------
One row = one product.

SOURCE:
-------
staging.products
staging.category_translation

KEY:
----
product_key = warehouse-generated surrogate key.

===============================================================================
*/

CREATE TABLE warehouse.dim_product (

    product_key BIGINT GENERATED ALWAYS AS IDENTITY,

    product_id VARCHAR(50) NOT NULL,

    product_category_name VARCHAR(100),

    product_category_name_english VARCHAR(100),

    product_name_length INTEGER,

    product_description_length INTEGER,

    product_photos_qty INTEGER,

    product_weight_g NUMERIC,

    product_length_cm NUMERIC,

    product_height_cm NUMERIC,

    product_width_cm NUMERIC,

    CONSTRAINT pk_dim_product
        PRIMARY KEY (product_key)
);

/*
===============================================================================
SECTION 9: VERIFY PRODUCT DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.dim_product contains the columns we designed.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_product'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 10: LOAD PRODUCT DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_product from the validated staging tables.

LOGIC:
------
Every product is retained.

A LEFT JOIN is used so that:
- Products with translations receive an English category.
- Products without translations remain in the dimension.
- Products without a category remain in the dimension.

The product_key is generated automatically by PostgreSQL.
===============================================================================
*/

INSERT INTO warehouse.dim_product (
    product_id,
    product_category_name,
    product_category_name_english,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)

SELECT
    p.product_id,
    p.product_category_name,
    ct.product_category_name_english,
    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm

FROM staging.products p

LEFT JOIN staging.category_translation ct
    ON p.product_category_name = ct.product_category_name;


/*
===============================================================================
SECTION 11: INSPECT PRODUCT DIMENSION
===============================================================================

PURPOSE:
--------
Verify that products were loaded correctly and that product_key values were
generated automatically.
===============================================================================
*/

SELECT
    product_key,
    product_id,
    product_category_name,
    product_category_name_english,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM warehouse.dim_product

ORDER BY product_key

LIMIT 10;

/*
===============================================================================
SECTION 12: VALIDATE PRODUCT CATEGORY COVERAGE
===============================================================================

PURPOSE:
--------
Confirm that the product dimension preserved:
1. Products with translated categories
2. Products with categories but no translation
3. Products with no category
===============================================================================
*/

SELECT
    COUNT(*) AS total_products,

    COUNT(*) FILTER (
        WHERE product_category_name IS NOT NULL
          AND product_category_name_english IS NOT NULL
    ) AS translated_products,

    COUNT(*) FILTER (
        WHERE product_category_name IS NOT NULL
          AND product_category_name_english IS NULL
    ) AS category_without_translation,

    COUNT(*) FILTER (
        WHERE product_category_name IS NULL
    ) AS products_without_category

FROM warehouse.dim_product;

/*
===============================================================================
SECTION 12: VALIDATE PRODUCT DIMENSION
===============================================================================

PURPOSE:
--------
Perform the final validation of warehouse.dim_product.

CHECKS:
-------
1. Row count matches staging.
2. product_key is unique.
3. product_id has no duplicates.
4. All source products are represented.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.products)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.dim_product)
        AS warehouse_rows,

    (SELECT COUNT(DISTINCT product_key)
     FROM warehouse.dim_product)
        AS unique_product_keys,

    (SELECT COUNT(*)
     FROM (
         SELECT product_id
         FROM warehouse.dim_product
         GROUP BY product_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_product_ids;

/*
===============================================================================
SECTION 13: INSPECT CATEGORY DATA
===============================================================================

PURPOSE:
--------
Understand the distinct product categories before creating the category
dimension.

We want to know:
- How many categories exist?
- Which categories have English translations?
===============================================================================
*/

SELECT
    COUNT(*) AS total_category_rows,

    COUNT(DISTINCT product_category_name)
        AS distinct_portuguese_categories,

    COUNT(DISTINCT product_category_name_english)
        AS distinct_english_categories

FROM staging.category_translation;

/*
===============================================================================
SECTION 14: CREATE CATEGORY DIMENSION
===============================================================================

PURPOSE:
--------
Create the warehouse category dimension.

GRAIN:
------
One row = one product category.

SOURCE:
-------
staging.category_translation

TARGET:
-------
warehouse.dim_category

KEY:
----
category_key = warehouse-generated surrogate key.

===============================================================================
*/

CREATE TABLE warehouse.dim_category (

    category_key BIGINT GENERATED ALWAYS AS IDENTITY,

    category_name VARCHAR(100) NOT NULL,

    category_name_english VARCHAR(100) NOT NULL,

    CONSTRAINT pk_dim_category
        PRIMARY KEY (category_key)
);

/*
===============================================================================
SECTION 15: VERIFY CATEGORY DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.dim_category contains the expected columns and
warehouse-generated surrogate key.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_category'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 16: LOAD CATEGORY DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_category from the validated staging category
translation table.

The category_key is generated automatically by PostgreSQL.
===============================================================================
*/

INSERT INTO warehouse.dim_category (
    category_name,
    category_name_english
)
SELECT
    product_category_name,
    product_category_name_english
FROM staging.category_translation;

/*
===============================================================================
SECTION 17: INSPECT CATEGORY DIMENSION
===============================================================================

PURPOSE:
--------
Verify that category records were loaded and that category_key values were
generated automatically.
===============================================================================
*/

SELECT
    category_key,
    category_name,
    category_name_english
FROM warehouse.dim_category
ORDER BY category_key
LIMIT 10;

/*
===============================================================================
SECTION 18: VALIDATE CATEGORY DIMENSION
===============================================================================

PURPOSE:
--------
Perform the final validation of warehouse.dim_category.

CHECKS:
-------
1. Row count matches staging.
2. category_key is unique.
3. Portuguese category names are unique.
4. English category names are unique.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.category_translation)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.dim_category)
        AS warehouse_rows,

    (SELECT COUNT(DISTINCT category_key)
     FROM warehouse.dim_category)
        AS unique_category_keys,

    (SELECT COUNT(*)
     FROM (
         SELECT category_name
         FROM warehouse.dim_category
         GROUP BY category_name
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_category_names,

    (SELECT COUNT(*)
     FROM (
         SELECT category_name_english
         FROM warehouse.dim_category
         GROUP BY category_name_english
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_english_names;

/*
===============================================================================
SECTION 19: CHECK PRODUCT → CATEGORY MATCHING
===============================================================================

PURPOSE:
--------
Understand how products currently map to the category dimension.

IMPORTANT:
----------
This is a READ-ONLY analysis.
No warehouse tables are modified.
===============================================================================
*/

SELECT
    COUNT(*) AS total_products,

    COUNT(dc.category_key) AS products_with_category,

    COUNT(*) FILTER (
        WHERE dp.product_category_name IS NULL
    ) AS products_without_category,

    COUNT(*) FILTER (
        WHERE dp.product_category_name IS NOT NULL
          AND dc.category_key IS NULL
    ) AS products_with_unmatched_category

FROM warehouse.dim_product dp

LEFT JOIN warehouse.dim_category dc
    ON dp.product_category_name = dc.category_name;


/*
===============================================================================
SECTION 20: IDENTIFY UNMATCHED PRODUCT CATEGORIES
===============================================================================

PURPOSE:
--------
Find product categories that exist in staging.products but do not exist in
warehouse.dim_category.

These categories have no entry in the translation lookup table.
===============================================================================
*/

SELECT
    dp.product_category_name,
    COUNT(*) AS product_count
FROM warehouse.dim_product dp
LEFT JOIN warehouse.dim_category dc
    ON dp.product_category_name = dc.category_name
WHERE dp.product_category_name IS NOT NULL
  AND dc.category_key IS NULL
GROUP BY dp.product_category_name
ORDER BY product_count DESC;


/*
===============================================================================
SECTION 21: ADD UNTRANSLATED PRODUCT CATEGORIES
===============================================================================

PURPOSE:
--------
Add valid product categories that exist in staging.products but are absent
from the translation lookup.

BUSINESS RULE:
--------------
The Portuguese/source category is preserved.
The English translation remains NULL because no translation exists.

CURRENT ADDITIONS:
------------------
1. portateis_cozinha_e_preparadores_de_alimentos
2. pc_gamer
===============================================================================
*/

INSERT INTO warehouse.dim_category (
    category_name,
    category_name_english
)
VALUES
(
    'portateis_cozinha_e_preparadores_de_alimentos',
    NULL
),
(
    'pc_gamer',
    NULL
);

/*
===============================================================================
SECTION 22: ALLOW NULL ENGLISH CATEGORY TRANSLATIONS
===============================================================================

PURPOSE:
--------
Allow category_name_english to be NULL when the source category exists but
no English translation is available.

BUSINESS RULE:
--------------
Missing translation = NULL

We do not invent or guess translations.
===============================================================================
*/

ALTER TABLE warehouse.dim_category
ALTER COLUMN category_name_english DROP NOT NULL;

/*
===============================================================================
SECTION 23: ADD UNTRANSLATED PRODUCT CATEGORIES
===============================================================================

PURPOSE:
--------
Add valid product categories that exist in staging.products but are absent
from the translation lookup.

English translation is intentionally NULL because no source translation
exists.
===============================================================================
*/

INSERT INTO warehouse.dim_category (
    category_name,
    category_name_english
)
VALUES
(
    'portateis_cozinha_e_preparadores_de_alimentos',
    NULL
),
(
    'pc_gamer',
    NULL
);

/*
===============================================================================
SECTION 24: VERIFY CATEGORY DIMENSION
===============================================================================
*/

SELECT
    COUNT(*) AS total_categories,

    COUNT(category_name_english)
        AS translated_categories,

    COUNT(*) FILTER (
        WHERE category_name_english IS NULL
    ) AS untranslated_categories

FROM warehouse.dim_category;

/*
===============================================================================
SECTION 25: ADD CATEGORY SURROGATE KEY TO PRODUCT DIMENSION
===============================================================================

PURPOSE:
--------
Create the relationship between products and the warehouse category
dimension.

RELATIONSHIP:

dim_product.category_key
          ↓
dim_category.category_key

NOTE:
-----
Products without a category will keep category_key = NULL.
===============================================================================
*/

ALTER TABLE warehouse.dim_product
ADD COLUMN category_key BIGINT;

/*
===============================================================================
SECTION 26: POPULATE PRODUCT CATEGORY KEY
===============================================================================

PURPOSE:
--------
Link each product to its corresponding category dimension record.

LOGIC:
------
dim_product.product_category_name
        ↓
dim_category.category_name
        ↓
dim_product.category_key

IMPORTANT:
----------
Products without a category will remain with category_key = NULL.
===============================================================================
*/

UPDATE warehouse.dim_product dp
SET category_key = dc.category_key
FROM warehouse.dim_category dc
WHERE dp.product_category_name = dc.category_name;


/*
===============================================================================
SECTION 27: VALIDATE PRODUCT → CATEGORY RELATIONSHIP
===============================================================================

PURPOSE:
--------
Verify how many products have been successfully linked to dim_category.

EXPECTED:
---------
32,341 products should have a category_key.
610 products should have NULL category_key because they have no category.
===============================================================================
*/

SELECT
    COUNT(*) AS total_products,

    COUNT(category_key) AS products_with_category_key,

    COUNT(*) FILTER (
        WHERE category_key IS NULL
    ) AS products_without_category_key

FROM warehouse.dim_product;


/*
===============================================================================
SECTION 28: VALIDATE PRODUCT → CATEGORY KEY INTEGRITY
===============================================================================

PURPOSE:
--------
Ensure every category_key stored in dim_product points to a real category
record in dim_category.

EXPECTED:
---------
0 orphan category keys.
===============================================================================
*/

SELECT COUNT(*) AS orphan_category_keys
FROM warehouse.dim_product dp
LEFT JOIN warehouse.dim_category dc
    ON dp.category_key = dc.category_key
WHERE dp.category_key IS NOT NULL
  AND dc.category_key IS NULL;


/*
===============================================================================
SECTION 29: INSPECT SELLER STAGING DATA
===============================================================================

PURPOSE:
--------
Understand the seller records before creating the seller dimension.
===============================================================================
*/

SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM staging.sellers
LIMIT 10;

/*
===============================================================================
SECTION 30: CHECK SELLER RECORD COUNT
===============================================================================
*/

SELECT COUNT(*) AS total_sellers
FROM staging.sellers;

/*
===============================================================================
SECTION 31: CREATE SELLER DIMENSION
===============================================================================

PURPOSE:
--------
Create the warehouse seller dimension.

GRAIN:
------
One row = one seller.

SOURCE:
-------
staging.sellers

KEY:
----
seller_key = warehouse-generated surrogate key.
===============================================================================
*/

CREATE TABLE warehouse.dim_seller (

    seller_key BIGINT GENERATED ALWAYS AS IDENTITY,

    seller_id VARCHAR(50) NOT NULL,

    seller_zip_code_prefix INTEGER,

    seller_city VARCHAR(100),

    seller_state VARCHAR(10),

    CONSTRAINT pk_dim_seller
        PRIMARY KEY (seller_key)
);


/*
===============================================================================
SECTION 32: VERIFY SELLER DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.dim_seller contains the expected columns and that
seller_key is the warehouse-generated surrogate key.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_seller'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 33: LOAD SELLER DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_seller from the validated staging.sellers table.

The seller_key is generated automatically by PostgreSQL.
===============================================================================
*/

INSERT INTO warehouse.dim_seller (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM staging.sellers;

/*
===============================================================================
SECTION 34: INSPECT SELLER DIMENSION
===============================================================================

PURPOSE:
--------
Verify that seller records were loaded correctly and that seller_key values
were generated automatically.
===============================================================================
*/

SELECT
    seller_key,
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM warehouse.dim_seller
ORDER BY seller_key
LIMIT 10;

/*
===============================================================================
SECTION 35: VALIDATE SELLER DIMENSION
===============================================================================

PURPOSE:
--------
Perform the final validation of warehouse.dim_seller.

CHECKS:
-------
1. Row count matches staging.
2. seller_key is unique.
3. seller_id has no duplicates.
4. seller_id contains no NULL values.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.sellers)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.dim_seller)
        AS warehouse_rows,

    (SELECT COUNT(DISTINCT seller_key)
     FROM warehouse.dim_seller)
        AS unique_seller_keys,

    (SELECT COUNT(*)
     FROM (
         SELECT seller_id
         FROM warehouse.dim_seller
         GROUP BY seller_id
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_seller_ids,

    (SELECT COUNT(*)
     FROM warehouse.dim_seller
     WHERE seller_id IS NULL)
        AS null_seller_ids;


/*
===============================================================================
SECTION 36: UNDERSTAND GEOLOCATION GRAIN
===============================================================================

PURPOSE:
--------
Determine whether a ZIP-code prefix has multiple geolocation records.

This helps us decide the correct grain for dim_geography.
===============================================================================
*/

SELECT
    COUNT(*) AS total_geolocation_rows,

    COUNT(DISTINCT geolocation_zip_code_prefix)
        AS distinct_zip_prefixes

FROM staging.geolocation;


/*
===============================================================================
SECTION 37: CHECK ZIP PREFIX MULTIPLICITY
===============================================================================

PURPOSE:
--------
Understand how many geolocation records belong to each ZIP-code prefix.

This helps us determine how to select a representative geography record
for the warehouse dimension.
===============================================================================
*/

SELECT
    MAX(records_per_zip) AS maximum_records_per_zip,
    AVG(records_per_zip)::numeric(10,2) AS average_records_per_zip
FROM (
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS records_per_zip
    FROM staging.geolocation
    GROUP BY geolocation_zip_code_prefix
) z;

/*
===============================================================================
SECTION 38: CHECK ZIP → CITY/STATE CONSISTENCY
===============================================================================

PURPOSE:
--------
Determine whether a ZIP-code prefix is associated with multiple cities or
states in the raw geolocation data.

This helps us decide how to construct dim_geography.

EXPECTED:
---------
Most ZIP prefixes should map to one city and one state.
===============================================================================
*/

SELECT
    geolocation_zip_code_prefix,

    COUNT(DISTINCT geolocation_city) AS distinct_cities,

    COUNT(DISTINCT geolocation_state) AS distinct_states

FROM staging.geolocation

GROUP BY geolocation_zip_code_prefix

HAVING COUNT(DISTINCT geolocation_city) > 1
    OR COUNT(DISTINCT geolocation_state) > 1

ORDER BY distinct_cities DESC, distinct_states DESC;

/*
===============================================================================
SECTION : 39COUNT ZIP PREFIXES WITH MULTIPLE LOCATIONS
===============================================================================

PURPOSE:
--------
Count the actual number of ZIP prefixes associated with multiple cities or
states.

This avoids relying on the pgAdmin result-display limit.
===============================================================================
*/

SELECT
    COUNT(*) AS inconsistent_zip_prefixes
FROM (
    SELECT
        geolocation_zip_code_prefix

    FROM staging.geolocation

    GROUP BY geolocation_zip_code_prefix

    HAVING COUNT(DISTINCT geolocation_city) > 1
        OR COUNT(DISTINCT geolocation_state) > 1
) x;


/*
===============================================================================
SECTION 40: DETERMINE GEOGRAPHY DIMENSION GRAIN
===============================================================================

PURPOSE:
--------
Count unique ZIP-code + city + state combinations.

This will determine the number of rows required by dim_geography.

DECISION:
---------
We will use:

1 row = 1 unique ZIP-code + city + state combination
===============================================================================
*/

SELECT
    COUNT(*) AS unique_zip_city_state_combinations,

    COUNT(DISTINCT geolocation_zip_code_prefix)
        AS distinct_zip_prefixes

FROM (
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state
    FROM staging.geolocation
) g;

/*
===============================================================================
SECTION 41: CREATE GEOGRAPHY DIMENSION
===============================================================================

PURPOSE:
--------
Create the warehouse geography dimension from the geolocation staging data.

GRAIN:
------
One row = one unique ZIP-code + city + state combination.

SOURCE:
-------
staging.geolocation

KEY:
----
geography_key = warehouse-generated surrogate key.

GEOGRAPHIC ATTRIBUTES:
----------------------
- ZIP-code prefix
- city
- state
- representative latitude
- representative longitude

NOTE:
-----
The raw geolocation table contains multiple coordinate observations for many
ZIP prefixes. The warehouse will store the average latitude and longitude
for each unique ZIP + city + state combination.
===============================================================================
*/

CREATE TABLE warehouse.dim_geography (

    geography_key BIGINT GENERATED ALWAYS AS IDENTITY,

    zip_code_prefix INTEGER NOT NULL,

    city VARCHAR(100),

    state VARCHAR(10),

    latitude NUMERIC,

    longitude NUMERIC,

    CONSTRAINT pk_dim_geography
        PRIMARY KEY (geography_key)
);

/*
===============================================================================
SECTION 42: VERIFY GEOGRAPHY DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.dim_geography contains the expected columns.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_geography'
ORDER BY ordinal_position;


/*
===============================================================================
SECTION 43: PREVIEW GEOGRAPHY AGGREGATION
===============================================================================

PURPOSE:
--------
Preview how the 1,000,163 geolocation staging records will be reduced to
one warehouse record per unique ZIP + city + state combination.

LATITUDE/LONGITUDE:
-------------------
AVG() is used to create a representative coordinate for each geography.
===============================================================================
*/

SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,

    geolocation_city AS city,

    geolocation_state AS state,

    ROUND(AVG(latitude), 6) AS latitude,

    ROUND(AVG(longitude), 6) AS longitude,

    COUNT(*) AS source_records

FROM staging.geolocation

GROUP BY
    geolocation_zip_code_prefix,
    geolocation_city,
    geolocation_state

ORDER BY zip_code_prefix

LIMIT 20;

/*
===============================================================================
SECTION 44: PREVIEW NORMALIZED GEOGRAPHY
===============================================================================

PURPOSE:
--------
Preview city normalization before loading dim_geography.

NORMALIZATION:
--------------
- Convert city names to lowercase.
- Remove common Latin accents.
- Preserve the raw staging table unchanged.

This allows values such as:

    sao paulo
    são paulo

to be treated as the same analytical city.
===============================================================================
*/

SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,

    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ) AS normalized_city,

    geolocation_state AS state,

    ROUND(AVG(latitude), 6) AS latitude,

    ROUND(AVG(longitude), 6) AS longitude,

    COUNT(*) AS source_records

FROM staging.geolocation

GROUP BY
    geolocation_zip_code_prefix,
    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ),
    geolocation_state

ORDER BY zip_code_prefix

LIMIT 20;

/*
===============================================================================
SECTION 45: COUNT NORMALIZED GEOGRAPHY RECORDS
===============================================================================

PURPOSE:
--------
Determine the final number of geography records after city-name normalization.

GRAIN:
------
One row = one ZIP-code prefix + normalized city + state.
===============================================================================
*/

SELECT
    COUNT(*) AS normalized_geography_rows
FROM (
    SELECT DISTINCT
        geolocation_zip_code_prefix,

        LOWER(
            TRANSLATE(
                geolocation_city,
                'áàãâäéèêëíìîïóòõôöúùûüç',
                'aaaaaeeeeiiiiooooouuuuc'
            )
        ) AS normalized_city,

        geolocation_state

    FROM staging.geolocation
) g;

/*
===============================================================================
SECTION 46: INSERT GEOGRAPHY DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_geography from staging.geolocation.

GRAIN:
------
1 row = 1 ZIP-code prefix + normalized city + state.

TRANSFORMATIONS:
----------------
1. Normalize city names to lowercase.
2. Remove common Latin accents.
3. Average latitude and longitude for the geography.
4. Preserve every unique geography combination.

The geography_key is generated automatically by PostgreSQL.
===============================================================================
*/

INSERT INTO warehouse.dim_geography (
    zip_code_prefix,
    city,
    state,
    latitude,
    longitude
)

SELECT
    geolocation_zip_code_prefix,

    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ) AS normalized_city,

    geolocation_state,

    ROUND(AVG(latitude), 6) AS latitude,

    ROUND(AVG(longitude), 6) AS longitude

FROM staging.geolocation

GROUP BY
    geolocation_zip_code_prefix,

    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ),

    geolocation_state;


/*
===============================================================================
SECTION 47: LOAD GEOGRAPHY DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_geography from staging.geolocation.

GRAIN:
------
1 row = 1 ZIP-code prefix + normalized city + state.

TRANSFORMATIONS:
----------------
1. Normalize city names to lowercase.
2. Remove common Latin accents.
3. Average latitude and longitude for the geography.
4. Preserve every unique geography combination.

The geography_key is generated automatically by PostgreSQL.
===============================================================================
*/

INSERT INTO warehouse.dim_geography (
    zip_code_prefix,
    city,
    state,
    latitude,
    longitude
)
SELECT
    geolocation_zip_code_prefix,

    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ) AS normalized_city,

    geolocation_state,

    ROUND(AVG(latitude), 6) AS latitude,
    ROUND(AVG(longitude), 6) AS longitude

FROM staging.geolocation

GROUP BY
    geolocation_zip_code_prefix,

    LOWER(
        TRANSLATE(
            geolocation_city,
            'áàãâäéèêëíìîïóòõôöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )
    ),

    geolocation_state;

/*
===============================================================================
SECTION :48 INSPECT GEOGRAPHY DIMENSION
===============================================================================

PURPOSE:
--------
Verify that the geography records were loaded correctly and that the
geography_key values were generated automatically.
===============================================================================
*/

SELECT
    geography_key,
    zip_code_prefix,
    city,
    state,
    latitude,
    longitude
FROM warehouse.dim_geography
ORDER BY geography_key
LIMIT 10;

/*
===============================================================================
SECTION 49: VALIDATE GEOGRAPHY DIMENSION
===============================================================================

PURPOSE:
--------
Perform final validation of warehouse.dim_geography.

CHECKS:
-------
1. Row count matches the expected normalized geography count.
2. geography_key is unique.
3. No duplicate ZIP + city + state combinations.
4. Latitude values are valid.
5. Longitude values are valid.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM warehouse.dim_geography)
        AS warehouse_rows,

    (SELECT COUNT(DISTINCT geography_key)
     FROM warehouse.dim_geography)
        AS unique_geography_keys,

    (SELECT COUNT(*)
     FROM (
         SELECT
             zip_code_prefix,
             city,
             state
         FROM warehouse.dim_geography
         GROUP BY
             zip_code_prefix,
             city,
             state
         HAVING COUNT(*) > 1
     ) d)
        AS duplicate_geographies,

    (SELECT COUNT(*)
     FROM warehouse.dim_geography
     WHERE latitude IS NOT NULL
       AND (latitude < -90 OR latitude > 90))
        AS invalid_latitudes,

    (SELECT COUNT(*)
     FROM warehouse.dim_geography
     WHERE longitude IS NOT NULL
       AND (longitude < -180 OR longitude > 180))
        AS invalid_longitudes;


/*
===============================================================================
SECTION 50: DETERMINE DATE DIMENSION RANGE
===============================================================================

PURPOSE:
--------
Find the minimum and maximum order purchase dates so that dim_date covers
the complete period represented in our dataset.
===============================================================================
*/

SELECT
    MIN(purchase_timestamp::date) AS minimum_date,
    MAX(purchase_timestamp::date) AS maximum_date
FROM staging.orders;


/*
===============================================================================
SECTION 51: CREATE DATE DIMENSION
===============================================================================

PURPOSE:
--------
Create the warehouse date dimension.

GRAIN:
------
One row = one calendar date.

SOURCE:
-------
Generated from PostgreSQL's date series.

WHY WE NEED IT:
---------------
Provides reusable time attributes for:
- Monthly analysis
- Quarterly analysis
- Yearly analysis
- Weekday analysis
- Year-over-year comparisons
- Month-over-month comparisons
===============================================================================
*/

CREATE TABLE warehouse.dim_date (

    date_key INTEGER NOT NULL,

    full_date DATE NOT NULL,

    year INTEGER NOT NULL,

    quarter INTEGER NOT NULL,

    month INTEGER NOT NULL,

    month_name VARCHAR(20) NOT NULL,

    week INTEGER NOT NULL,

    day INTEGER NOT NULL,

    day_name VARCHAR(20) NOT NULL,

    CONSTRAINT pk_dim_date
        PRIMARY KEY (date_key)
);

/*
===============================================================================
SECTION 52: VERIFY DATE DIMENSION STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.dim_date contains the expected calendar attributes.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'dim_date'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 53: PREVIEW DATE DIMENSION
===============================================================================

PURPOSE:
--------
Generate a calendar between the minimum and maximum dates in the Olist data.

DATE SOURCE:
------------
staging.orders

GRAIN:
------
1 row = 1 calendar date.

The preview lets us verify the generated attributes before loading them.
===============================================================================
*/

SELECT
    TO_CHAR(d::date, 'YYYYMMDD')::INTEGER AS date_key,

    d::date AS full_date,

    EXTRACT(YEAR FROM d)::INTEGER AS year,

    EXTRACT(QUARTER FROM d)::INTEGER AS quarter,

    EXTRACT(MONTH FROM d)::INTEGER AS month,

    TO_CHAR(d, 'Month') AS month_name,

    EXTRACT(WEEK FROM d)::INTEGER AS week,

    EXTRACT(DAY FROM d)::INTEGER AS day,

    TO_CHAR(d, 'Day') AS day_name

FROM generate_series(
    (SELECT MIN(purchase_timestamp::date) FROM staging.orders),
    (SELECT MAX(purchase_timestamp::date) FROM staging.orders),
    INTERVAL '1 day'
) AS gs(d)

ORDER BY d

LIMIT 10;

/*
===============================================================================
SECTION 54: LOAD DATE DIMENSION
===============================================================================

PURPOSE:
--------
Populate warehouse.dim_date with one record for every calendar date in the
Olist analytical period.

DATE RANGE:
-----------
2016-09-04 through 2018-10-17

GRAIN:
------
1 row = 1 calendar date.

DATE KEY:
---------
YYYYMMDD format, for example:

20160904 → 2016-09-04
===============================================================================
*/

INSERT INTO warehouse.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    week,
    day,
    day_name
)

SELECT
    TO_CHAR(d::date, 'YYYYMMDD')::INTEGER AS date_key,

    d::date AS full_date,

    EXTRACT(YEAR FROM d)::INTEGER AS year,

    EXTRACT(QUARTER FROM d)::INTEGER AS quarter,

    EXTRACT(MONTH FROM d)::INTEGER AS month,

    TRIM(TO_CHAR(d, 'Month')) AS month_name,

    EXTRACT(WEEK FROM d)::INTEGER AS week,

    EXTRACT(DAY FROM d)::INTEGER AS day,

    TRIM(TO_CHAR(d, 'Day')) AS day_name

FROM generate_series(
    (SELECT MIN(purchase_timestamp::date)
     FROM staging.orders),

    (SELECT MAX(purchase_timestamp::date)
     FROM staging.orders),

    INTERVAL '1 day'
) AS gs(d);

/*
===============================================================================
SECTION 55: VALIDATE DATE DIMENSION
===============================================================================

PURPOSE:
--------
Verify that the generated calendar contains the complete expected date range,
unique date keys, and no missing calendar attributes.
===============================================================================
*/

SELECT
    COUNT(*) AS total_dates,

    MIN(full_date) AS minimum_date,

    MAX(full_date) AS maximum_date,

    COUNT(DISTINCT date_key) AS unique_date_keys,

    COUNT(*) FILTER (
        WHERE month_name IS NULL
    ) AS missing_month_names,

    COUNT(*) FILTER (
        WHERE day_name IS NULL
    ) AS missing_day_names

FROM warehouse.dim_date;

/*
===============================================================================
SECTION 56: UNDERSTAND ORDER ITEM GRAIN
===============================================================================

PURPOSE:
--------
Inspect one order and its individual items.

GRAIN:
------
1 row = 1 item within an order.
===============================================================================
*/

SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    price,
    freight_value,
    item_total
FROM staging.order_items
WHERE order_id = (
    SELECT order_id
    FROM staging.order_items
    GROUP BY order_id
    HAVING COUNT(*) > 1
    ORDER BY COUNT(*) DESC
    LIMIT 1
)
ORDER BY order_item_id;

/*
===============================================================================
SECTION 57: VALIDATE ORDER ITEM → CUSTOMER PATH
===============================================================================

PURPOSE:
--------
Verify that every order item can be traced through its order to a valid
customer.

RELATIONSHIP:

order_items
     ↓ order_id
orders
     ↓ customer_id
customers

This relationship will be used when building fact_order_items.
===============================================================================
*/

SELECT COUNT(*) AS order_items_without_customer
FROM staging.order_items oi

JOIN staging.orders o
    ON oi.order_id = o.order_id

LEFT JOIN staging.customers c
    ON o.customer_id = c.customer_id

WHERE c.customer_id IS NULL;

/*
===============================================================================
SECTION 58: CREATE FACT ORDER ITEMS
===============================================================================

PURPOSE:
--------
Create the central transactional fact table for item-level sales analysis.

GRAIN:
------
1 row = 1 order-item record.

FACT MEASURES:
--------------
price
freight_value
item_total

DIMENSION KEYS:
---------------
customer_key
product_key
seller_key
order_date_key
shipping_date_key

SOURCE IDENTIFIERS:
-------------------
order_id
order_item_id

These are retained for traceability back to the source/staging layer.
===============================================================================
*/

CREATE TABLE warehouse.fact_order_items (

    fact_order_item_key BIGINT GENERATED ALWAYS AS IDENTITY,

    order_id VARCHAR(50) NOT NULL,

    order_item_id INTEGER NOT NULL,

    customer_key BIGINT NOT NULL,

    product_key BIGINT NOT NULL,

    seller_key BIGINT NOT NULL,

    order_date_key INTEGER NOT NULL,

    shipping_date_key INTEGER,

    price NUMERIC NOT NULL,

    freight_value NUMERIC NOT NULL,

    item_total NUMERIC NOT NULL,

    CONSTRAINT pk_fact_order_items
        PRIMARY KEY (fact_order_item_key)
);


/*
===============================================================================
SECTION 59: VERIFY FACT ORDER ITEMS STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that the fact table contains the expected source identifiers,
dimension keys, and measures.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'fact_order_items'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 60: LOAD FACT ORDER ITEMS
===============================================================================

PURPOSE:
--------
Load the item-level transactional data into the warehouse fact table while
converting source/business IDs into warehouse surrogate keys.

GRAIN:
------
1 row = 1 order-item record.

SOURCE PATH:
------------
staging.order_items
        ↓
staging.orders
        ↓
staging.customers / warehouse.dim_customer

PRODUCT:
--------
staging.order_items.product_id
        ↓
warehouse.dim_product.product_id

SELLER:
-------
staging.order_items.seller_id
        ↓
warehouse.dim_seller.seller_id

DATES:
------
Order purchase date and shipping-limit date are converted into date keys
from warehouse.dim_date.
===============================================================================
*/

INSERT INTO warehouse.fact_order_items (
    order_id,
    order_item_id,
    customer_key,
    product_key,
    seller_key,
    order_date_key,
    shipping_date_key,
    price,
    freight_value,
    item_total
)

SELECT
    oi.order_id,

    oi.order_item_id,

    dc.customer_key,

    dp.product_key,

    ds.seller_key,

    TO_CHAR(o.purchase_timestamp::date, 'YYYYMMDD')::INTEGER
        AS order_date_key,

    CASE
        WHEN oi.shipping_limit_timestamp IS NOT NULL
        THEN TO_CHAR(
            oi.shipping_limit_timestamp::date,
            'YYYYMMDD'
        )::INTEGER
        ELSE NULL
    END AS shipping_date_key,

    oi.price,

    oi.freight_value,

    oi.item_total

FROM staging.order_items oi

INNER JOIN staging.orders o
    ON oi.order_id = o.order_id

INNER JOIN warehouse.dim_customer dc
    ON o.customer_id = dc.customer_id

INNER JOIN warehouse.dim_product dp
    ON oi.product_id = dp.product_id

INNER JOIN warehouse.dim_seller ds
    ON oi.seller_id = ds.seller_id;


/*
===============================================================================
SECTION 61: VALIDATE FACT ORDER ITEMS
===============================================================================

PURPOSE:
--------
Confirm that the fact table contains the same number of transactional records
as staging.order_items and that the key measures were loaded.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.order_items)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.fact_order_items)
        AS fact_rows,

    (SELECT COUNT(DISTINCT fact_order_item_key)
     FROM warehouse.fact_order_items)
        AS unique_fact_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_order_items
     WHERE customer_key IS NULL)
        AS null_customer_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_order_items
     WHERE product_key IS NULL)
        AS null_product_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_order_items
     WHERE seller_key IS NULL)
        AS null_seller_keys;

/*
===============================================================================
SECTION 62: PREPARE FOR FACT ORDERS
===============================================================================

PURPOSE:
--------
Verify that every staging order can be connected to the customer dimension
and the date dimension before creating fact_orders.
===============================================================================
*/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE dc.customer_key IS NOT NULL
    ) AS orders_with_customer,

    COUNT(*) FILTER (
        WHERE dd.date_key IS NOT NULL
    ) AS orders_with_order_date

FROM staging.orders o

LEFT JOIN warehouse.dim_customer dc
    ON o.customer_id = dc.customer_id

LEFT JOIN warehouse.dim_date dd
    ON o.purchase_timestamp::date = dd.full_date;


/*
===============================================================================
SECTION 63: CREATE FACT ORDERS
===============================================================================

PURPOSE:
--------
Create the order-level fact table.

GRAIN:
------
1 row = 1 order.

This table stores order-level business events and links the order to the
customer and relevant dates through warehouse surrogate keys.
===============================================================================
*/

CREATE TABLE warehouse.fact_orders (

    fact_order_key BIGINT GENERATED ALWAYS AS IDENTITY,

    order_id VARCHAR(50) NOT NULL,

    customer_key BIGINT NOT NULL,

    order_date_key INTEGER NOT NULL,

    delivery_date_key INTEGER,

    order_status VARCHAR(30) NOT NULL,

    is_delivered BOOLEAN NOT NULL,

    has_delivery_timestamp BOOLEAN NOT NULL,

    is_cancelled BOOLEAN NOT NULL,

    is_late BOOLEAN NOT NULL,

    is_pending_delivery BOOLEAN NOT NULL,

    delivery_days NUMERIC,

    CONSTRAINT pk_fact_orders
        PRIMARY KEY (fact_order_key)
);


/*
===============================================================================
SECTION 64: VERIFY FACT ORDERS STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that warehouse.fact_orders contains the expected order-level
attributes, dimension keys, and business flags.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'fact_orders'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 65: LOAD FACT ORDERS
===============================================================================

PURPOSE:
--------
Load one warehouse fact record for every order.

GRAIN:
------
1 row = 1 order.

KEY MAPPING:
------------
customer_id
    → dim_customer.customer_key

purchase date
    → dim_date.date_key

delivery date
    → dim_date.date_key

The delivery-date relationship is optional because some orders do not have
a customer delivery timestamp.
===============================================================================
*/

INSERT INTO warehouse.fact_orders (
    order_id,
    customer_key,
    order_date_key,
    delivery_date_key,
    order_status,
    is_delivered,
    has_delivery_timestamp,
    is_cancelled,
    is_late,
    is_pending_delivery,
    delivery_days
)

SELECT
    o.order_id,

    dc.customer_key,

    dd_order.date_key
        AS order_date_key,

    dd_delivery.date_key
        AS delivery_date_key,

    o.order_status,

    o.is_delivered,

    o.has_delivery_timestamp,

    o.is_cancelled,

    o.is_late,

    o.is_pending_delivery,

    o.delivery_days

FROM staging.orders o

INNER JOIN warehouse.dim_customer dc
    ON o.customer_id = dc.customer_id

INNER JOIN warehouse.dim_date dd_order
    ON o.purchase_timestamp::date = dd_order.full_date

LEFT JOIN warehouse.dim_date dd_delivery
    ON o.delivered_customer_timestamp::date = dd_delivery.full_date;


/*
===============================================================================
SECTION 66: VALIDATE FACT ORDERS
===============================================================================

PURPOSE:
--------
Confirm that every staging order was loaded into the fact table and that
the required warehouse keys are populated.

EXPECTED:
---------
99,441 fact rows
99,441 unique fact keys
0 missing customer keys
0 missing order date keys
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.orders)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.fact_orders)
        AS fact_rows,

    (SELECT COUNT(DISTINCT fact_order_key)
     FROM warehouse.fact_orders)
        AS unique_fact_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_orders
     WHERE customer_key IS NULL)
        AS null_customer_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_orders
     WHERE order_date_key IS NULL)
        AS null_order_date_keys;


/*
===============================================================================
SECTION 67: VALIDATE DELIVERY DATE KEY
===============================================================================

PURPOSE:
--------
Compare orders that have a delivery timestamp with orders that have a
delivery_date_key in the warehouse.
===============================================================================
*/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE has_delivery_timestamp = TRUE
    ) AS orders_with_delivery_timestamp,

    COUNT(delivery_date_key)
        AS orders_with_delivery_date_key,

    COUNT(*) FILTER (
        WHERE has_delivery_timestamp = TRUE
          AND delivery_date_key IS NULL
    ) AS timestamp_but_no_date_key

FROM warehouse.fact_orders;


/*
===============================================================================
SECTION 68: PREPARE FOR FACT PAYMENTS
===============================================================================

PURPOSE:
--------
Verify that every staging payment belongs to a valid warehouse order.
===============================================================================
*/

SELECT
    COUNT(*) AS total_payments,

    COUNT(fo.fact_order_key) AS payments_with_order,

    COUNT(*) FILTER (
        WHERE fo.fact_order_key IS NULL
    ) AS orphan_payments

FROM staging.order_payments p

LEFT JOIN warehouse.fact_orders fo
    ON p.order_id = fo.order_id;


/*
===============================================================================
SECTION 69: CREATE FACT PAYMENTS
===============================================================================

PURPOSE:
--------
Create the payment-level fact table.

GRAIN:
------
1 row = 1 payment record.

SOURCE:
-------
staging.order_payments

RELATIONSHIP:
------------
Each payment belongs to an order and connects to fact_orders through
fact_order_key.
===============================================================================
*/

CREATE TABLE warehouse.fact_payments (

    fact_payment_key BIGINT GENERATED ALWAYS AS IDENTITY,

    order_key BIGINT NOT NULL,

    order_id VARCHAR(50) NOT NULL,

    payment_sequential INTEGER NOT NULL,

    payment_type VARCHAR(30) NOT NULL,

    payment_installments INTEGER NOT NULL,

    payment_value NUMERIC NOT NULL,

    CONSTRAINT pk_fact_payments
        PRIMARY KEY (fact_payment_key)
);


/*
===============================================================================
SECTION 70: VERIFY FACT PAYMENTS STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that the payment fact table contains the expected order relationship,
payment attributes, and measure.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'fact_payments'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 71: LOAD FACT PAYMENTS
===============================================================================

PURPOSE:
--------
Load one fact record for every payment record in staging.order_payments.

GRAIN:
------
1 row = 1 payment record.

ORDER MAPPING:
--------------
staging.order_payments.order_id
        ↓
warehouse.fact_orders.order_id
        ↓
warehouse.fact_orders.fact_order_key
===============================================================================
*/

INSERT INTO warehouse.fact_payments (
    order_key,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)

SELECT
    fo.fact_order_key,

    p.order_id,

    p.payment_sequential,

    p.payment_type,

    p.payment_installments,

    p.payment_value

FROM staging.order_payments p

INNER JOIN warehouse.fact_orders fo
    ON p.order_id = fo.order_id;



/*
===============================================================================
SECTION 72: VALIDATE FACT PAYMENTS
===============================================================================

PURPOSE:
--------
Confirm that all payment records were loaded and that every payment points
to a valid order in fact_orders.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.order_payments)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.fact_payments)
        AS fact_rows,

    (SELECT COUNT(DISTINCT fact_payment_key)
     FROM warehouse.fact_payments)
        AS unique_fact_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_payments
     WHERE order_key IS NULL)
        AS null_order_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_payments fp
     LEFT JOIN warehouse.fact_orders fo
        ON fp.order_key = fo.fact_order_key
     WHERE fo.fact_order_key IS NULL)
        AS orphan_order_keys;


/*
===============================================================================
SECTION 73: PREPARE FOR FACT REVIEWS
===============================================================================

PURPOSE:
--------
Verify that every review can be connected to a valid warehouse order.

RELATIONSHIP:

staging.order_reviews
        ↓
       order_id
        ↓
warehouse.fact_orders
        ↓
    fact_order_key
===============================================================================
*/

SELECT
    COUNT(*) AS total_reviews,

    COUNT(fo.fact_order_key) AS reviews_with_order,

    COUNT(*) FILTER (
        WHERE fo.fact_order_key IS NULL
    ) AS orphan_reviews

FROM staging.order_reviews r

LEFT JOIN warehouse.fact_orders fo
    ON r.order_id = fo.order_id;


/*
===============================================================================
SECTION 74: CREATE FACT REVIEWS
===============================================================================

PURPOSE:
--------
Create the review-level fact table.

GRAIN:
------
1 row = 1 review.

KEY RELATIONSHIPS:
------------------
order_key
review_date_key
answer_date_key

MEASURES / ATTRIBUTES:
----------------------
review_score
review_response_days
has_comment
===============================================================================
*/

CREATE TABLE warehouse.fact_reviews (

    fact_review_key BIGINT GENERATED ALWAYS AS IDENTITY,

    review_id VARCHAR(50) NOT NULL,

    order_key BIGINT NOT NULL,

    order_id VARCHAR(50) NOT NULL,

    review_date_key INTEGER NOT NULL,

    answer_date_key INTEGER,

    review_score INTEGER NOT NULL,

    review_response_days NUMERIC,

    has_comment BOOLEAN NOT NULL,

    CONSTRAINT pk_fact_reviews
        PRIMARY KEY (fact_review_key)
);


/*
===============================================================================
SECTION 75: VERIFY FACT REVIEWS STRUCTURE
===============================================================================

PURPOSE:
--------
Confirm that the review fact table contains the expected review, order,
date-key, and review-analysis columns.
===============================================================================
*/

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'warehouse'
  AND table_name = 'fact_reviews'
ORDER BY ordinal_position;

/*
===============================================================================
SECTION 76: LOAD FACT REVIEWS
===============================================================================

PURPOSE:
--------
Load one warehouse fact record for every review.

GRAIN:
------
1 row = 1 review.

KEY MAPPING:
------------
review.order_id
    → fact_orders.fact_order_key

review_creation_timestamp
    → dim_date.date_key

review_answer_timestamp
    → dim_date.date_key

has_comment:
    TRUE when either a review title or message exists.
===============================================================================
*/

INSERT INTO warehouse.fact_reviews (
    review_id,
    order_key,
    order_id,
    review_date_key,
    answer_date_key,
    review_score,
    review_response_days,
    has_comment
)

SELECT
    r.review_id,

    fo.fact_order_key,

    r.order_id,

    dd_review.date_key
        AS review_date_key,

    dd_answer.date_key
        AS answer_date_key,

    r.review_score,

    r.review_response_days,

    CASE
        WHEN r.review_comment_title IS NOT NULL
          OR r.review_comment_message IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS has_comment

FROM staging.order_reviews r

INNER JOIN warehouse.fact_orders fo
    ON r.order_id = fo.order_id

INNER JOIN warehouse.dim_date dd_review
    ON r.review_creation_timestamp::date = dd_review.full_date

LEFT JOIN warehouse.dim_date dd_answer
    ON r.review_answer_timestamp::date = dd_answer.full_date;


/*
===============================================================================
SECTION 77: VALIDATE FACT REVIEWS
===============================================================================

PURPOSE:
--------
Confirm that all review records were loaded and that the required
relationships and review scores are valid.
===============================================================================
*/

SELECT
    (SELECT COUNT(*)
     FROM staging.order_reviews)
        AS staging_rows,

    (SELECT COUNT(*)
     FROM warehouse.fact_reviews)
        AS fact_rows,

    (SELECT COUNT(DISTINCT fact_review_key)
     FROM warehouse.fact_reviews)
        AS unique_fact_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_reviews
     WHERE order_key IS NULL)
        AS null_order_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_reviews
     WHERE review_date_key IS NULL)
        AS null_review_date_keys,

    (SELECT COUNT(*)
     FROM warehouse.fact_reviews
     WHERE review_score < 1
        OR review_score > 5)
        AS invalid_review_scores;