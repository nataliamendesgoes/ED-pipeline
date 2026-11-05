# NorthMart — Esquema em estrela (PA1)

```mermaid
erDiagram
    dim_date     ||--o{ fact_sales : "date_key"
    dim_product  ||--o{ fact_sales : "product_key"
    dim_seller   ||--o{ fact_sales : "seller_key"
    dim_customer ||--o{ fact_sales : "customer_key"
    dim_location ||--o{ fact_sales : "location_key"

    fact_sales {
        varchar order_id      "grão (1/2)"
        int     order_item_id "grão (2/2)"
        int     date_key      FK "data da compra"
        int     product_key   FK
        int     seller_key    FK
        int     customer_key  FK
        int     location_key  FK "morada desta compra"
        varchar order_status  "degenerate dimension"
        double  price         "medida"
        double  freight_value "medida"
    }

    dim_date {
        int     date_key PK "AAAAMMDD"
        date    full_date
        int     year
        int     quarter
        int     month
        varchar month_name
        varchar year_month "AAAA-MM"
        int     day
        varchar day_of_week
        boolean is_weekend
    }

    dim_product {
        int     product_key PK
        varchar product_id  "chave natural"
        varchar category_pt
        varchar category_en
        int     weight_g
        int     length_cm
        int     height_cm
        int     width_cm
    }

    dim_seller {
        int     seller_key PK
        varchar seller_id  "chave natural"
        varchar zip_code_prefix
        varchar city
        varchar state
        varchar tier          "JSON, normalizado"
        date    joined_on     "JSON"
        int     handling_days "JSON"
    }

    dim_customer {
        int     customer_key PK
        varchar customer_unique_id "chave natural = pessoa"
    }

    dim_location {
        int     location_key PK
        varchar zip_code_prefix "chave natural (1/3)"
        varchar city            "chave natural (2/3)"
        varchar state           "chave natural (3/3)"
    }
```

## Grão

**Uma linha da `fact_sales` = um item de uma encomenda**, identificado pelo par
(`order_id`, `order_item_id`), que é único em `olist_order_items_dataset.csv`
(112 650 linhas, 112 650 pares distintos).

## Medidas

| Medida | Significado | Aditividade |
|---|---|---|
| `price` | preço do item | aditiva — soma-se a qualquer nível (encomenda, mês, categoria) |
| `freight_value` | custo de envio do item | aditiva |

Receita = `sum(price)`. O valor de uma encomenda obtém-se somando os seus itens.

## Dimensões

| Dimensão | Uma linha = | Origem |
|---|---|---|
| `dim_date` | um dia, de 2016-01-01 a 2018-12-31 | gerada (cobre todas as datas de compra e de entrega estimada) |
| `dim_product` | um produto | products `LEFT JOIN` category_name_translation |
| `dim_seller` | um vendedor | sellers (CSV) `LEFT JOIN` perfil JSON deduplicado |
| `dim_customer` | uma pessoa (`customer_unique_id`) | customers |
| `dim_location` | uma morada de entrega (CEP + cidade + estado) | customers |

Ligação da fact ao cliente e à morada: `order_items → orders (customer_id) → customers`, de onde saem o `customer_unique_id` (→ `dim_customer`) e a morada da compra (→ `dim_location`).

## Decisões de modelação

1. **Cliente ao nível da pessoa, não do `customer_id` (decisão não óbvia).**
   Em `customers`, o `customer_id` é único mas é criado por encomenda (99 441, igual
   ao número de encomendas); a pessoa real é o `customer_unique_id` (96 096). Uma
   `dim_customer` por `customer_id` contaria 3 345 clientes a mais e tornaria
   impossível responder a "quantos clientes voltaram a comprar?". Por isso a
   dimensão tem uma linha por `customer_unique_id`.
2. **Pagamentos fora da fact.** `payment_value` está ao nível da encomenda; repeti-lo
   em cada item somaria o mesmo pagamento várias vezes (*double counting*).
3. **Categoria dentro da `dim_product`** (estrela, não floco de neve): a categoria é
   um atributo do produto; desnormalizar evita um JOIN extra em cada query.
4. **Dados de contacto dos vendedores excluídos.** `email` e `phone` não servem a
   análise de vendas e são dados pessoais (minimização de dados, RGPD).
5. **Morada numa dimensão própria, ligada a cada venda.** A mesma pessoa pode comprar
   em moradas diferentes: 250 pessoas têm mais do que um CEP e, entre as vendas da fact, 37
   compraram em mais do que um estado. Guardar só a morada mais recente na `dim_customer` apagava esse
   histórico e punha 49 itens (R$ 6 164,99) no estado errado. Com a `location_key` na
   fact, cada venda mantém a morada daquela compra, e a `dim_customer` continua com uma
   linha por pessoa. Como cada `customer_id` é criado por encomenda, a morada em
   `customers` já é a da compra. Preferiu-se isto a um SCD tipo 2 porque a data da
   compra já está na fact (`date_key`), sem precisar de datas de validade.
6. **`dim_seller` parte do CSV.** Os 40 vendedores sem perfil ficam com `tier`,
   `joined_on` e `handling_days` a `NULL`; os 15 perfis sem vendedor no CSV ficam de
   fora (não têm vendas). Dos perfis repetidos fica a versão de `updated_at` mais
   recente.
