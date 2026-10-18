-- =====================================================================
-- PA1 · Tarefa 4 — As 3 queries do benchmark
-- `fact` é uma view criada pelo src/benchmark.py que aponta, à vez, para
-- o CSV, o Parquet e o Parquet particionado. O texto das queries é igual
-- nos três formatos; só muda a origem dos dados.
-- =====================================================================

-- Q1. Receita por mês no período completo
SELECT year_month, round(sum(price), 2) AS receita
FROM fact
GROUP BY year_month
ORDER BY year_month;

-- Q2. Receita e número de itens de um único mês (maio de 2018)
SELECT round(sum(price), 2) AS receita, count(*) AS itens
FROM fact
WHERE year_month = 201805;

-- Q3. As 5 categorias de produto com mais receita
SELECT p.category_en, round(sum(f.price), 2) AS receita
FROM fact f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.category_en
ORDER BY receita DESC
LIMIT 5;
