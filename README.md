# NorthMart — Data Engineering 2026/27

Plataforma de dados construída em três etapas (PA1, PA2, PA3) sobre o
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
e o export de perfis de vendedores `northmart_seller_profiles.json`.

## Setup

Requisitos: Python 3.11+.

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows (PowerShell)
# source .venv/bin/activate     # Linux / macOS / WSL
pip install -r requirements.txt
```

Dados de origem (não estão no repositório):

1. Descarregar os 9 CSV da Olist (conta Kaggle gratuita) — manualmente ou com
   `python src/download_olist.py` — e copiá-los, com os nomes originais, para `data/source/`.
2. Copiar `northmart_seller_profiles.json` (página da disciplina) para `data/source/`.

Para correr qualquer script SQL e ver o resultado de cada query:

```bash
python src/run_sql.py sql/<ficheiro>.sql
```

> No Windows, se aparecer `UnicodeEncodeError`, correr antes `$env:PYTHONIOENCODING="utf-8"`.

---

## PA1 — From raw files to a star schema

### Tarefa 1 — Profiling

Script: [`sql/profiling.sql`](sql/profiling.sql) ·
Executar: `python src/run_sql.py sql/profiling.sql`

O script está organizado em quatro secções: (1) contagem de linhas por ficheiro,
(2) chaves e duplicados no JSON, (3) taxas de nulos, (4) chaves nos CSV.

#### Volume

| Ficheiro | Linhas |
|---|---:|
| orders | 99 441 |
| order_items | 112 650 |
| customers | 99 441 |
| payments | 103 886 |
| reviews | 99 224 |
| products | 32 951 |
| sellers | 3 095 |
| geolocation | 1 000 163 |
| category_name_translation | 71 |
| seller_profiles (JSON) | 3 095 |

#### Conclusões sobre o JSON (`northmart_seller_profiles.json`)

1. **Vendedores repetidos.** O JSON tem 3 095 registos mas apenas 3 070 `seller_id`
   distintos: 25 vendedores aparecem duas vezes. Não são cópias — são versões
   diferentes do mesmo perfil, com `updated_at` distinto, e em 7 delas o `tier` muda
   (ex.: de bronze para gold). Para manter um registo por vendedor fica-se com a
   versão de `updated_at` mais recente.
2. **Cobertura incompleta.** 40 vendedores do `olist_sellers_dataset.csv` não têm
   perfil no JSON e 15 perfis do JSON referem vendedores que não existem no CSV.
   As contagens de linhas coincidem (3 095) apenas por acaso: as 15 linhas
   sem vendedor mais as 25 repetições compensam exatamente os 40 vendedores em
   falta (3 055 + 15 + 25 = 3 055 + 40). Comparar contagens não basta — é preciso
   comparar chaves.
3. **`tier` com grafias inconsistentes.** Há 9 variantes para 3 valores
   (`bronze`/`Bronze`/`BRONZE`, `silver`/`Silver`/`SILVER`, `gold`/`Gold`/`GOLD`).
   Tem de ser normalizado (`lower`) antes de ir para a dimensão.
4. **`updated_at` com valor por defeito.** Todas as versões antigas dos vendedores
   repetidos têm `updated_at = 2017-06-15 09:00:00`, por vezes anterior ao próprio
   `joined_on` (ex.: vendedor `05730013…` aderiu em 2018-03-11). Não é uma
   atualização real mas um valor carimbado em massa no export.
5. **`handling_days` em falta.** 30 perfis (0,97 %) não têm `handling_days`;
   `tier` e `joined_on` não têm nulos. Os nulos ficam `NULL` na dimensão
   (desconhecido), em vez de 0 ou da média, para não enviesar médias.

#### Conclusões sobre os CSV

6. **Chaves.** `order_id` é chave simples de `orders` (99 441 linhas, 99 441
   distintos). Em `order_items` o `order_id` repete-se (98 666 encomendas para
   112 650 linhas), mas o par (`order_id`, `order_item_id`) é único — é a chave
   composta e o grão da tabela de factos.
7. **Datas de entrega vs. estado.** 2,98 % das encomendas não têm
   `order_delivered_customer_date` (0,16 % sem aprovação, 1,79 % sem entrega à
   transportadora). Quase todos os nulos são esperados — encomendas ainda não
   entregues (`shipped`, `processing`, …) ou que nunca o serão (`canceled`,
   `unavailable`). Há, porém, 8 encomendas `delivered` sem data de entrega e 6
   `canceled` com data de entrega: inconsistências entre estado e datas.
8. **Encomendas sem itens.** 775 encomendas (0,8 %) não têm nenhuma linha em
   `order_items`: 603 `unavailable`, 164 `canceled`, 5 `created`, 2 `invoiced` e
   1 `shipped` (esta última é anómala). Como a fact está ao nível do item, estas
   encomendas não aparecem nela.
9. **`customer_id` não identifica o cliente.** `customer_id` é único (99 441), mas
   é criado por encomenda — há tantos quantos encomendas. A pessoa real é o
   `customer_unique_id` (96 096): 3 345 encomendas pertencem a clientes que
   voltaram a comprar. Contar clientes por `customer_id` sobrestima-os.

### Tarefa 2 — Esquema em estrela

Diagrama, grão, medidas e decisões: [`architecture/star_schema.md`](architecture/star_schema.md).

- **Grão:** um item de uma encomenda (`order_id`, `order_item_id`).
- **Fact:** `fact_sales`, com as medidas `price` e `freight_value`.
- **Dimensões:** `dim_date`, `dim_product`, `dim_seller`, `dim_customer`.
- **Decisão não óbvia:** a `dim_customer` tem uma linha por pessoa
  (`customer_unique_id`) e não por `customer_id`, que é criado a cada encomenda.

### Tarefa 3 — Implementação (`sql/build_model.sql`)

```bash
python src/run_sql.py sql/build_model.sql northmart.duckdb
```

O script é idempotente (`CREATE OR REPLACE`) e constrói, por esta ordem:

1. **Camada raw** — os 9 CSV e o JSON carregados sem alterações (`raw_*`).
2. **`dim_date`** — gerada, um dia por linha de 2016-01-01 a 2018-12-31 (1 096 dias).
3. **`dim_product`** — `LEFT JOIN` à tradução; categoria em falta → nome em PT ou `unknown`.
4. **`dim_seller`** — CSV `LEFT JOIN` perfis JSON achatados (`profile.tier`, …),
   deduplicados (versão de `updated_at` mais recente) e com `tier` normalizado.
5. **`dim_customer`** — uma linha por `customer_unique_id`, com a morada da compra mais recente.
6. **`fact_sales`** — um item por linha; as chaves naturais são trocadas pelas chaves
   substitutas (`row_number()`) através de `LEFT JOIN` às dimensões.
7. **Verificações referenciais.**

Resultado das verificações:

| Verificação | Resultado |
|---|---|
| Linhas da fact = linhas de `raw_order_items` | 112 650 = 112 650 |
| Órfãos (FK sem dimensão): date / product / seller / customer | 0 / 0 / 0 / 0 |
| Duplicados no grão (`order_id`, `order_item_id`) | 0 |
| Receita total raw vs fact | 13 591 643,70 = 13 591 643,70 |
| Uma linha por chave natural em cada dimensão | sim (32 951 produtos, 3 095 vendedores, 96 096 clientes) |
| Tiers após normalização | bronze 1 828 · silver 919 · gold 308 · `NULL` 40 (sem perfil) |

### Tarefa 4 — Parquet e benchmark

```bash
python src/run_sql.py sql/export.sql northmart.duckdb   # exporta a fact em 3 formatos
python src/benchmark.py                                  # mede tamanhos e tempos
```

**Exportação** ([`sql/export.sql`](sql/export.sql)), para `data/curated/`:
`fact_sales.csv`, `fact_sales.parquet` e `fact_sales_by_month/` — Parquet particionado
por `year_month` (AAAAMM, `date_key // 100`), em formato Hive (`year_month=201805/`).
O mês foi escolhido por ser o filtro da query Q2 e por dar ~24 partições de tamanho
equilibrado; `date_key` ou `product_key` criariam centenas/milhares de ficheiros
minúsculos, e `order_status` é desequilibrado (~97 % `delivered`) e não é filtrado
por nenhuma query.

**Método** ([`src/benchmark.py`](src/benchmark.py), queries em
[`sql/benchmark_queries.sql`](sql/benchmark_queries.sql)):
- as 3 queries têm o mesmo texto nos 3 formatos — correm sobre uma view `fact` que
  aponta, à vez, para cada ficheiro; a Q3 junta à `dim_product` da base de dados;
- por formato e query: 1 execução de aquecimento (descartada) + 5 execuções
  cronometradas com `time.perf_counter`; reporta-se a mediana, o mínimo e o máximo;
- o script confirma que os 3 formatos devolvem resultados idênticos;
- DuckDB 1.5.6, Windows 11, portátil pessoal, ficheiros em disco local.

**Resultados** (também em [`evidence/benchmark.md`](evidence/benchmark.md)):

| Formato | Tamanho (MB) | Q1 receita/mês (ms) | Q2 um mês (ms) | Q3 top 5 categorias (ms) |
|---|---:|---:|---:|---:|
| CSV | 8,76 | 133,9 | 129,3 | 161,9 |
| Parquet | 4,55 | 8,8 | 3,4 | 19,0 |
| Parquet particionado (mês) | 4,95 | 15,3 | 11,6 | 37,9 |

_(medianas de 5 execuções)_

### Tarefa 5 — Data warehouse, data lake ou lakehouse?

A NorthMart seria mais bem servida por um **data warehouse**. Os seus dados são
pequenos e estruturados, e os problemas dos analistas são relatórios lentos e
joins feitos de forma diferente por cada um.

Primeiro, no nosso benchmark, a receita por mês demorou 133,9 ms em CSV e 8,8 ms
em Parquet — 15 vezes mais rápido. Um warehouse com armazenamento colunar e um
único modelo em estrela, com as regras de limpeza aplicadas uma vez, resolve a
lentidão e a inconsistência.

Segundo, a tabela de factos ocupa apenas 4,55 MB e o particionamento por mês
tornou a query de um só mês mais lenta (11,6 ms contra 3,4 ms). A este volume, as
técnicas de data lake acrescentam complexidade sem benefício.

Um lakehouse passaria a compensar se o volume crescesse várias ordens de grandeza
ou se chegassem dados não estruturados, como imagens de produtos.
