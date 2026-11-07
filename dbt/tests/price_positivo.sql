-- Falha se existir algum item com preço zero ou negativo.
SELECT order_id, order_item_id, price
FROM {{ ref('stg_orders') }}
WHERE price <= 0
