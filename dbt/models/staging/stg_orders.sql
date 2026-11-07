-- Itens de um só dia, com tipos corretos.
SELECT
    order_id,
    TRY_CAST(order_item_id AS INTEGER)              AS order_item_id,
    customer_id,
    product_id,
    seller_id,
    lower(trim(order_status))                       AS order_status,
    TRY_CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp,
    TRY_CAST(price AS DOUBLE)                       AS price,
    TRY_CAST(freight_value AS DOUBLE)               AS freight_value
FROM {{ source('raw', 'raw_api_orders') }}
WHERE extraction_date = '{{ var("execution_date") }}'
