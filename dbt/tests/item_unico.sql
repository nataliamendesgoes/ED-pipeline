-- Falha se o par (order_id, order_item_id), o grão da fact, aparecer mais do que uma vez.
SELECT order_id, order_item_id, count(*) AS vezes
FROM {{ ref('stg_orders') }}
GROUP BY order_id, order_item_id
HAVING count(*) > 1
