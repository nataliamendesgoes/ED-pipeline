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
