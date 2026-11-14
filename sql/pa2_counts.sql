-- =====================================================================
-- PA2 — Contagens do pipeline: linhas por dia no raw e na fact
-- Executar com nenhuma tarefa da DAG a correr (o DuckDB só aceita um escritor):
--   python src/run_sql.py sql/pa2_counts.sql northmart_pa2.duckdb
-- Um dia que está no raw mas não na fact foi travado pelos testes.
-- =====================================================================

-- 1. Linhas por dia: o que chegou da API (raw) e o que entrou na fact
WITH raw AS (
    SELECT extraction_date AS dia, count(*) AS linhas_raw
    FROM raw_api_orders
    GROUP BY extraction_date
),
fact AS (
    SELECT strftime(d.full_date, '%Y-%m-%d') AS dia, count(*) AS linhas_fact
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.full_date
)
SELECT raw.dia, raw.linhas_raw, COALESCE(fact.linhas_fact, 0) AS linhas_fact
FROM raw
LEFT JOIN fact ON raw.dia = fact.dia
ORDER BY raw.dia;

-- 2. Totais e duplicados no grão da fact (esperado: 0 duplicados)
SELECT
    (SELECT count(*) FROM raw_api_orders) AS total_raw,
    (SELECT count(*) FROM fact_sales)     AS total_fact,
    (SELECT count(*) FROM fact_sales)
  - (SELECT count(*) FROM (SELECT DISTINCT order_id, order_item_id FROM fact_sales)) AS duplicados_na_fact;
