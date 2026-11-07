-- =====================================================================
-- PA2 — Prepara a base de dados do pipeline
-- Executar depois do build_model.sql, na mesma base de dados:
--   python src/run_sql.py sql/build_model.sql northmart_pa2.duckdb
--   python src/run_sql.py sql/prepare_pa2.sql northmart_pa2.duckdb
-- As dimensões ficam como na PA1. A fact é preenchida pelo pipeline.
-- =====================================================================
DELETE FROM fact_sales;

SELECT count(*) AS linhas_fact FROM fact_sales;
