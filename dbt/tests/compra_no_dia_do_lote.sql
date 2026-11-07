-- Falha se um item tiver data de compra diferente do dia do lote, ou data inválida.
SELECT order_id, order_item_id, order_purchase_timestamp
FROM {{ ref('stg_orders') }}
WHERE CAST(order_purchase_timestamp AS DATE)
      IS DISTINCT FROM CAST('{{ var("execution_date") }}' AS DATE)
