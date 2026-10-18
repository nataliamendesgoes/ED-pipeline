-- =====================================================================
-- PA1 · Tarefa 4 — Exportação da fact_sales em 3 formatos
-- Executar: python src/run_sql.py sql/export.sql northmart.duckdb
-- =====================================================================

-- 1. CSV (base de comparação)
COPY fact_sales TO 'data/curated/fact_sales.csv' (FORMAT csv, HEADER true);

-- 2. Parquet sem partições
COPY fact_sales TO 'data/curated/fact_sales.parquet' (FORMAT parquet);

-- 3. Parquet particionado por mês (year_month = AAAAMM, derivado de date_key)
COPY (SELECT *, date_key // 100 AS year_month FROM fact_sales)
TO 'data/curated/fact_sales_by_month'
(FORMAT parquet, PARTITION_BY (year_month), OVERWRITE true);
