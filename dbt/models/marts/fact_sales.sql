{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['order_id', 'order_item_id']
) }}

SELECT
    s.order_id,
    s.order_item_id,
    dd.date_key,
    dp.product_key,
    ds.seller_key,
    dc.customer_key,
    dl.location_key,
    s.order_status,
    s.price,
    s.freight_value
FROM {{ ref('stg_orders') }} s
LEFT JOIN {{ source('raw', 'raw_customers') }} c  ON s.customer_id = c.customer_id
LEFT JOIN {{ source('raw', 'dim_date') }}      dd ON CAST(s.order_purchase_timestamp AS DATE) = dd.full_date
LEFT JOIN {{ source('raw', 'dim_product') }}   dp ON s.product_id = dp.product_id
LEFT JOIN {{ source('raw', 'dim_seller') }}    ds ON s.seller_id = ds.seller_id
LEFT JOIN {{ source('raw', 'dim_customer') }}  dc ON c.customer_unique_id = dc.customer_unique_id
LEFT JOIN {{ source('raw', 'dim_location') }}  dl ON c.customer_zip_code_prefix = dl.zip_code_prefix
                                                 AND c.customer_city = dl.city
                                                 AND c.customer_state = dl.state
