-- =====================================================================
-- PA1 · Tarefa 1 — Profiling dos ficheiros em bruto (data/source/)
-- =====================================================================

-- 0. Pré-visualização
SELECT * FROM read_csv('data/source/olist_orders_dataset.csv') LIMIT 5;
SELECT * FROM read_json('data/source/northmart_seller_profiles.json') LIMIT 5;

-- 1. Contagem de linhas por ficheiro
SELECT 'orders' AS ficheiro, count(*) AS linhas
FROM read_csv('data/source/olist_orders_dataset.csv')
UNION ALL
SELECT 'order_items', count(*)
FROM read_csv('data/source/olist_order_items_dataset.csv')
UNION ALL
SELECT 'sellers', count(*)
FROM read_csv('data/source/olist_sellers_dataset.csv')
UNION ALL
SELECT 'products', count(*)
FROM read_csv('data/source/olist_products_dataset.csv')
UNION ALL
SELECT 'customers', count(*)
FROM read_csv('data/source/olist_customers_dataset.csv')
UNION ALL
SELECT 'payments', count(*)
FROM read_csv('data/source/olist_order_payments_dataset.csv')
UNION ALL
SELECT 'reviews', count(*)
FROM read_csv('data/source/olist_order_reviews_dataset.csv')
UNION ALL
SELECT 'geolocation', count(*)
FROM read_csv('data/source/olist_geolocation_dataset.csv')
UNION ALL
SELECT 'category_name_translation', count(*)
FROM read_csv('data/source/product_category_name_translation.csv')
UNION ALL
SELECT 'seller_profiles', count(*)
FROM read_json('data/source/northmart_seller_profiles.json');


-- 2. Chaves e duplicados
CREATE VIEW sellers AS
SELECT * FROM read_csv('data/source/olist_sellers_dataset.csv');

CREATE VIEW seller_profiles AS
SELECT * FROM read_json('data/source/northmart_seller_profiles.json');

CREATE VIEW orders AS
SELECT * FROM read_csv('data/source/olist_orders_dataset.csv');

CREATE VIEW order_items AS
SELECT * FROM read_csv('data/source/olist_order_items_dataset.csv');

CREATE VIEW customers AS
SELECT * FROM read_csv('data/source/olist_customers_dataset.csv');


-- 2a. Linhas vs. não-nulos vs. distintos na chave seller_id
SELECT 'sellers' AS tabela,
       count(*)                  AS linhas,
       count(seller_id)          AS nao_nulos,
       count(DISTINCT seller_id) AS distintos
FROM sellers
UNION ALL
SELECT 'seller_profiles',
       count(*),
       count(seller_id),
       count(DISTINCT seller_id)
FROM seller_profiles;

-- 2b. Cobertura entre o CSV de sellers e o JSON (nos dois sentidos)
SELECT 'csv_sem_perfil_json' AS verificacao, count(*) AS vendedores
FROM sellers
ANTI JOIN seller_profiles USING (seller_id)
UNION ALL
SELECT 'json_sem_seller_csv', count(DISTINCT seller_id)
FROM seller_profiles
ANTI JOIN sellers USING (seller_id);

-- 2c. Vendedores repetidos no JSON: cópias ou versões diferentes?
SELECT seller_id, count(*) AS n
FROM seller_profiles
GROUP BY seller_id
HAVING count(*) > 1;

-- todas as versões dos repetidos, lado a lado (campos achatados)
SELECT seller_id, updated_at,
       profile.tier, profile.joined_on, shipping.handling_days
FROM seller_profiles
WHERE seller_id IN (SELECT seller_id FROM seller_profiles
                    GROUP BY seller_id HAVING count(*) > 1)
ORDER BY seller_id, updated_at;

-- 2d. Quantos repetidos mudam de tier entre versões?
SELECT count(*) AS repetidos_com_tier_diferente
FROM (SELECT seller_id
      FROM seller_profiles
      GROUP BY seller_id
      HAVING count(*) > 1 AND count(DISTINCT profile.tier) > 1);

SELECT profile.tier, count(*) FROM seller_profiles GROUP BY 1;


-- 3. Nulos
-- 3a. Taxa de nulos nos campos do JSON que vão para dim_seller

SELECT count(*)                       AS linhas,
       count(shipping.handling_days)  AS com_valor
FROM seller_profiles;

SELECT round(100.0 * (count(*) - count(shipping.handling_days)) / count(*), 2) AS pct_nulos_handling
FROM seller_profiles;


SELECT
    round(100.0 * (count(*) - count(profile.tier)) / count(*), 2) AS pct_nulos_tier,
    round(100.0 * (count(*) - count(profile.joined_on)) / count(*), 2) AS pct_nulos_joined_on,
    round(100.0 * (count(*) - count(shipping.handling_days)) / count(*), 2) AS pct_nulos_handling
FROM seller_profiles;

-- 3b. Nulos nas datas das encomendas
SELECT
    round(100.0 * (count(*) - count(order_approved_at)) / count(*), 2)             AS pct_nulos_approved,
    round(100.0 * (count(*) - count(order_delivered_carrier_date)) / count(*), 2)  AS pct_nulos_delivered_carrier,
    round(100.0 * (count(*) - count(order_delivered_customer_date)) / count(*), 2) AS pct_nulos_delivered_customer
FROM orders;

SELECT order_status,
       count(*) AS encomendas,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS sem_entrega
FROM orders
GROUP BY order_status
ORDER BY encomendas DESC;

-- 4. Chaves nos CSV

-- 4a. orders: order_id é chave simples?
SELECT count(*)                 AS linhas,
       count(DISTINCT order_id) AS order_id_distintos
FROM orders;

-- 4b. order_items: chave composta (order_id, order_item_id) = grão da fact
SELECT count(*)                 AS linhas,
       count(DISTINCT order_id) AS encomendas_distintas,
       (SELECT count(*)
        FROM (SELECT DISTINCT order_id, order_item_id FROM order_items)) AS pares_distintos
FROM order_items;

-- 4b. Encomendas sem itens, por estado
SELECT order_status, count(*) AS encomendas
FROM orders
ANTI JOIN order_items USING (order_id)
GROUP BY order_status
ORDER BY encomendas DESC;

-- 4c. customers: customer_id vs customer_unique_id
SELECT count(*)                           AS linhas,
       count(DISTINCT customer_id)        AS customer_id_distintos,
       count(DISTINCT customer_unique_id) AS customer_unique_id_distintos
FROM customers;


DESCRIBE order_items;