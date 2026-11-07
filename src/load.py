"""Carrega os JSON de um dia de data/raw/ para a tabela raw_api_orders.

Executar a partir da raiz do repositório:
    python src/load.py 2018-05-03
"""
import sys

import duckdb

DB = "northmart_pa2.duckdb"
ITENS = (
    "STRUCT(order_id VARCHAR, order_item_id VARCHAR, customer_id VARCHAR, "
    "product_id VARCHAR, seller_id VARCHAR, order_status VARCHAR, "
    "order_purchase_timestamp VARCHAR, price VARCHAR, freight_value VARCHAR)[]"
)


def carregar_dia(data):
    con = duckdb.connect(DB)
    con.execute("""
        CREATE TABLE IF NOT EXISTS raw_api_orders (
            extraction_date VARCHAR, order_id VARCHAR, order_item_id VARCHAR,
            customer_id VARCHAR, product_id VARCHAR, seller_id VARCHAR,
            order_status VARCHAR, order_purchase_timestamp VARCHAR,
            price VARCHAR, freight_value VARCHAR
        )
    """)

    con.execute("BEGIN")
    con.execute("DELETE FROM raw_api_orders WHERE extraction_date = ?", [data])
    con.execute(f"""
        INSERT INTO raw_api_orders
        SELECT response_date, unnest(items, recursive := true)
        FROM read_json('data/raw/{data}/page_*.json',
            columns = {{date: 'VARCHAR', page: 'INTEGER', total_pages: 'INTEGER', items: '{ITENS}'}})
            AS t(response_date, page, total_pages, items)
    """)
    con.execute("COMMIT")

    linhas = con.execute(
        "SELECT count(*) FROM raw_api_orders WHERE extraction_date = ?", [data]
    ).fetchone()[0]
    print(f"{data}: {linhas} linhas em raw_api_orders")
    con.close()


if __name__ == "__main__":
    carregar_dia(sys.argv[1])