-- =====================================================================
-- PA1 · Tarefa 3 — Construção do modelo em estrela no DuckDB
-- Executar: python src/run_sql.py sql/build_model.sql northmart.duckdb
-- =====================================================================

-- 1. Camada raw: ficheiros carregados sem alterações
CREATE OR REPLACE TABLE raw_orders AS
SELECT * FROM read_csv('data/source/olist_orders_dataset.csv');

CREATE OR REPLACE TABLE raw_order_items AS
SELECT * FROM read_csv('data/source/olist_order_items_dataset.csv');

CREATE OR REPLACE TABLE raw_customers AS
SELECT * FROM read_csv('data/source/olist_customers_dataset.csv');

CREATE OR REPLACE TABLE raw_products AS
SELECT * FROM read_csv('data/source/olist_products_dataset.csv');

CREATE OR REPLACE TABLE raw_sellers AS
SELECT * FROM read_csv('data/source/olist_sellers_dataset.csv');

CREATE OR REPLACE TABLE raw_payments AS
SELECT * FROM read_csv('data/source/olist_order_payments_dataset.csv');

CREATE OR REPLACE TABLE raw_reviews AS
SELECT * FROM read_csv('data/source/olist_order_reviews_dataset.csv');

CREATE OR REPLACE TABLE raw_geolocation AS
SELECT * FROM read_csv('data/source/olist_geolocation_dataset.csv');

CREATE OR REPLACE TABLE raw_category_translation AS
SELECT * FROM read_csv('data/source/product_category_name_translation.csv');

CREATE OR REPLACE TABLE raw_seller_profiles AS
SELECT * FROM read_json('data/source/northmart_seller_profiles.json');

-- 1a. Contagem de linhas da camada raw (tem de bater com o profiling)
SELECT 'raw_orders' AS tabela, count(*) AS linhas FROM raw_orders
UNION ALL
SELECT 'raw_order_items', count(*) FROM raw_order_items
UNION ALL
SELECT 'raw_customers', count(*) FROM raw_customers
UNION ALL
SELECT 'raw_products', count(*) FROM raw_products
UNION ALL
SELECT 'raw_sellers', count(*) FROM raw_sellers
UNION ALL
SELECT 'raw_payments', count(*) FROM raw_payments
UNION ALL
SELECT 'raw_reviews', count(*) FROM raw_reviews
UNION ALL
SELECT 'raw_geolocation', count(*) FROM raw_geolocation
UNION ALL
SELECT 'raw_category_translation', count(*) FROM raw_category_translation
UNION ALL
SELECT 'raw_seller_profiles', count(*) FROM raw_seller_profiles;


-- 2. dim_date: um dia por linha, de 2016-01-01 a 2018-12-31
CREATE OR REPLACE TABLE dim_date AS
SELECT
    CAST(strftime(full_date, '%Y%m%d') AS INTEGER) AS date_key,
    full_date,
    year(full_date)                AS year,
    quarter(full_date)             AS quarter,
    month(full_date)               AS month,
    monthname(full_date)           AS month_name,
    strftime(full_date, '%Y-%m')   AS year_month,
    day(full_date)                 AS day,
    dayname(full_date)             AS day_of_week,
    dayofweek(full_date) IN (0, 6) AS is_weekend
FROM (SELECT range::DATE AS full_date
      FROM range(DATE '2016-01-01', DATE '2019-01-01', INTERVAL 1 DAY));

SELECT count(*) AS dias, min(full_date) AS inicio, max(full_date) AS fim FROM dim_date;

-- 3. dim_product: um produto por linha, com categoria em PT e EN
CREATE OR REPLACE TABLE dim_product AS
SELECT
    row_number() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.product_category_name         AS category_pt,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_en,
    p.product_weight_g              AS weight_g,
    p.product_length_cm             AS length_cm,
    p.product_height_cm             AS height_cm,
    p.product_width_cm              AS width_cm
FROM raw_products p
LEFT JOIN raw_category_translation t
       ON p.product_category_name = t.product_category_name;

-- 3a. A chave natural continua única?
SELECT count(*) AS linhas, count(DISTINCT product_id) AS produtos FROM dim_product;

-- 3b. Quantos produtos ficaram sem categoria em inglês? (esperado: 0)
SELECT count(*) FILTER (WHERE category_en IS NULL) AS sem_traducao FROM dim_product;

-- 4. dim_seller: um vendedor por linha (CSV) + perfil mais recente do JSON
CREATE OR REPLACE TABLE dim_seller AS
WITH profiles AS (
    SELECT
        seller_id,
        lower(trim(profile.tier)) AS tier,
        profile.joined_on         AS joined_on,
        shipping.handling_days    AS handling_days
    FROM raw_seller_profiles
    -- perfis repetidos: fica a versão mais recente
    QUALIFY row_number() OVER (PARTITION BY seller_id ORDER BY updated_at DESC) = 1
)
SELECT
    row_number() OVER (ORDER BY s.seller_id) AS seller_key,
    s.seller_id,
    s.seller_zip_code_prefix AS zip_code_prefix,
    s.seller_city            AS city,
    s.seller_state           AS state,
    p.tier,
    p.joined_on,
    p.handling_days
FROM raw_sellers s
LEFT JOIN profiles p ON s.seller_id = p.seller_id;

-- 4a. Um vendedor por linha? (esperado: 3095 = 3095)
SELECT count(*) AS linhas, count(DISTINCT seller_id) AS vendedores FROM dim_seller;

-- 4b. Tiers normalizados? (esperado: bronze, silver, gold + NULL dos 40 sem perfil)
SELECT tier, count(*) AS vendedores FROM dim_seller GROUP BY tier ORDER BY vendedores DESC;

-- 5. dim_customer: uma pessoa por linha, morada da compra mais recente
CREATE OR REPLACE TABLE dim_customer AS
WITH latest AS (
    SELECT
        c.customer_unique_id,
        c.customer_zip_code_prefix AS zip_code_prefix,
        c.customer_city            AS city,
        c.customer_state           AS state
    FROM raw_customers c
    JOIN raw_orders o ON c.customer_id = o.customer_id
    QUALIFY row_number() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp DESC) = 1
)
SELECT
    row_number() OVER (ORDER BY customer_unique_id) AS customer_key,
    customer_unique_id,
    zip_code_prefix,
    city,
    state
FROM latest;

-- 5a. Uma pessoa por linha? (esperado: 96096 = 96096)
SELECT count(*) AS linhas, count(DISTINCT customer_unique_id) AS pessoas FROM dim_customer;

-- 6. fact_sales: um item de encomenda por linha
CREATE OR REPLACE TABLE fact_sales AS
SELECT
    i.order_id,
    i.order_item_id,
    dd.date_key,
    dp.product_key,
    ds.seller_key,
    dc.customer_key,
    o.order_status,
    i.price,
    i.freight_value
FROM raw_order_items i
JOIN      raw_orders    o  ON i.order_id = o.order_id
JOIN      raw_customers c  ON o.customer_id = c.customer_id
LEFT JOIN dim_date      dd ON dd.full_date = CAST(o.order_purchase_timestamp AS DATE)
LEFT JOIN dim_product   dp ON i.product_id = dp.product_id
LEFT JOIN dim_seller    ds ON i.seller_id = ds.seller_id
LEFT JOIN dim_customer  dc ON c.customer_unique_id = dc.customer_unique_id;

-- 6a. O grão manteve-se? (esperado: 112650 linhas)
SELECT count(*) AS linhas FROM fact_sales;

-- 7. Verificações referenciais
-- 7a. Órfãos: linhas da fact cuja FK não encontrou a dimensão (esperado: tudo 0)
SELECT
    count(*) FILTER (WHERE date_key     IS NULL) AS orfaos_date,
    count(*) FILTER (WHERE product_key  IS NULL) AS orfaos_product,
    count(*) FILTER (WHERE seller_key   IS NULL) AS orfaos_seller,
    count(*) FILTER (WHERE customer_key IS NULL) AS orfaos_customer
FROM fact_sales;

-- 7b. Grão único na fact? (esperado: 0 duplicados)
SELECT count(*) - (SELECT count(*)
                   FROM (SELECT DISTINCT order_id, order_item_id FROM fact_sales)) AS duplicados
FROM fact_sales;

-- 7c. A receita total da fact é igual à da origem? (esperado: diferenca = 0)
SELECT
    (SELECT round(sum(price), 2) FROM raw_order_items) AS receita_raw,
    (SELECT round(sum(price), 2) FROM fact_sales)      AS receita_fact,
    (SELECT round(sum(price), 2) FROM raw_order_items)
  - (SELECT round(sum(price), 2) FROM fact_sales)      AS diferenca;
