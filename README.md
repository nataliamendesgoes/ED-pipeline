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
- **Dimensões:** `dim_date`, `dim_product`, `dim_seller`, `dim_customer`, `dim_location`.
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
5. **`dim_customer`** — uma linha por `customer_unique_id`.
6. **`dim_location`** — uma linha por morada (CEP + cidade + estado).
7. **`fact_sales`** — um item por linha; as chaves naturais são trocadas pelas chaves
   substitutas (`row_number()`) através de `LEFT JOIN` às dimensões. Cada venda guarda
   a morada daquela compra (`location_key`), por isso o histórico não se perde.
8. **Verificações referenciais.**

Resultado das verificações:

| Verificação | Resultado |
|---|---|
| Linhas da fact = linhas de `raw_order_items` | 112 650 = 112 650 |
| Órfãos (FK sem dimensão): date / product / seller / customer / location | 0 / 0 / 0 / 0 / 0 |
| Duplicados no grão (`order_id`, `order_item_id`) | 0 |
| Receita total raw vs fact | 13 591 643,70 = 13 591 643,70 |
| Uma linha por chave natural em cada dimensão | sim (32 951 produtos, 3 095 vendedores, 96 096 clientes, 15 034 moradas) |
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
| CSV | 9,33 | 178,2 | 184,3 | 218,1 |
| Parquet | 4,83 | 9,7 | 3,8 | 20,6 |
| Parquet particionado (mês) | 5,33 | 23,2 | 16,6 | 43,8 |

_(medianas de 5 execuções)_

### Tarefa 5 — Data warehouse, data lake ou lakehouse?

A NorthMart seria mais bem servida por um **data warehouse**. Os seus dados são
pequenos e estruturados, e os problemas dos analistas são relatórios lentos e
joins feitos de forma diferente por cada um.

Primeiro, no nosso benchmark, a receita por mês demorou 178,2 ms em CSV e 9,7 ms
em Parquet — 18 vezes mais rápido. Um warehouse com armazenamento colunar e um
único modelo em estrela, com as regras de limpeza aplicadas uma vez, resolve a
lentidão e a inconsistência.

Segundo, a tabela de factos ocupa apenas 4,83 MB e o particionamento por mês
tornou a query de um só mês mais lenta (16,6 ms contra 3,8 ms). A este volume, as
técnicas de data lake acrescentam complexidade sem benefício.

Um lakehouse passaria a compensar se o volume crescesse várias ordens de grandeza
ou se chegassem dados não estruturados, como imagens de produtos.

---

## PA2 — Pipeline diário orquestrado (API → raw → dbt → Airflow)

> ⏳ **Por preencher depois do backfill:** os campos marcados com `[...]` nas
> Tarefas 4, 5 e 6 e os ficheiros de evidência em `evidence/`.

### Visão geral

```
mock API (HTTP) ──extract──► data/raw/<dia>/page_<n>.json ──load──► raw_api_orders
     ──dbt run stg_orders──► stg_orders ──dbt test──► ✔ ──dbt run fact_sales──► fact_sales
```

Diagrama completo e decisões: [`architecture/pipeline.md`](architecture/pipeline.md).

Cada execução da DAG trata **um dia** (`{{ ds }}`). O pipeline só fala com a API por
HTTP; as dimensões ficam como na PA1 e só a `fact_sales` é alimentada pelo pipeline.

| Peça | Ficheiro |
|---|---|
| API de teste (fornecida) | [`mock_api.py`](mock_api.py) |
| Extração | [`src/extract.py`](src/extract.py) |
| Load para a camada raw | [`src/load.py`](src/load.py) |
| Projeto dbt | [`dbt/`](dbt/) |
| DAG | [`airflow/dags/northmart_pa2.py`](airflow/dags/northmart_pa2.py) |
| Arranque do Airflow | [`airflow/start_airflow.sh`](airflow/start_airflow.sh) |

### Reprodução

O Airflow não corre no Windows, por isso **todos os comandos desta secção correm no
Ubuntu (WSL2)**, na raiz do repositório (`/mnt/c/.../ED-work`). Requisitos: os dados
da PA1 em `data/source/` e o ficheiro `northmart_api_feed.parquet` (página da
disciplina), também em `data/source/`.

**1. Ambientes (uma vez).** Dois ambientes fora do repositório: um para o pipeline e
o dbt, outro para o Airflow, para as dependências não entrarem em conflito.

```bash
sudo apt install -y python3-venv
python3 -m venv ~/venvs/pipeline
~/venvs/pipeline/bin/pip install -r requirements.txt -r requirements-dbt.txt
python3 -m venv ~/venvs/airflow
~/venvs/airflow/bin/pip install "apache-airflow==3.4.0" \
  --constraint https://raw.githubusercontent.com/apache/airflow/constraints-3.4.0/constraints-3.14.txt
```

_(As constraints têm de corresponder à versão do Python: aqui 3.14.)_

**2. Base de dados (uma vez).** Constrói as dimensões da PA1 e esvazia a fact:

```bash
~/venvs/pipeline/bin/python src/run_sql.py sql/build_model.sql northmart_pa2.duckdb
~/venvs/pipeline/bin/python src/run_sql.py sql/prepare_pa2.sql northmart_pa2.duckdb
```

**3. Arrancar a API e o Airflow** (cada um no seu terminal, e deixá-los abertos):

```bash
~/venvs/pipeline/bin/python -m uvicorn mock_api:app --port 8000   # terminal 1
bash airflow/start_airflow.sh                                     # terminal 2 → http://localhost:8080
```

Utilizador `admin`; a password está em `~/airflow/simple_auth_manager_passwords.json.generated`.

**4. Correr o pipeline** (terminal 3):

```bash
export AIRFLOW_HOME=~/airflow PATH=~/venvs/airflow/bin:$PATH
airflow dags unpause northmart_pa2
# um dia
airflow dags trigger northmart_pa2 --logical-date 2018-05-03T00:00:00+00:00
# backfill dos 14 dias
airflow backfill create --dag-id northmart_pa2 --from-date 2018-05-01 --to-date 2018-05-14
```

Contar as linhas da fact (com nenhuma tarefa a correr, por causa do bloqueio do DuckDB):

```bash
~/venvs/pipeline/bin/python -c "import duckdb; print(duckdb.connect('northmart_pa2.duckdb', read_only=True).sql('SELECT count(*) FROM fact_sales').fetchone())"
```

Cada passo também pode correr à mão, sem Airflow (útil para depurar):

```bash
~/venvs/pipeline/bin/python src/extract.py 2018-05-03
~/venvs/pipeline/bin/python src/load.py 2018-05-03
~/venvs/pipeline/bin/dbt run  --project-dir dbt --profiles-dir dbt --select stg_orders --vars "{execution_date: '2018-05-03'}"
~/venvs/pipeline/bin/dbt test --project-dir dbt --profiles-dir dbt --select stg_orders --vars "{execution_date: '2018-05-03'}"
~/venvs/pipeline/bin/dbt run  --project-dir dbt --profiles-dir dbt --select fact_sales --vars "{execution_date: '2018-05-03'}"
```

### Tarefa 1 — Extração e landing raw

**Extração** ([`src/extract.py`](src/extract.py)) — `python src/extract.py <dia>`:
- **Paginação:** pede a página 1, lê `total_pages` da resposta e continua até à última.
- **Retry:** um `503` (serviço indisponível) é repetido até 5 vezes, com espera
  crescente (1 s, 2 s, 3 s, …); ao fim de 5 tentativas a tarefa falha.
- **Erros que não se repetem:** um `400` (pedido mal feito, ex.: data inválida) falha
  logo — repetir o mesmo pedido daria o mesmo erro.
- **Raw sem alterações:** cada resposta é gravada tal como chegou (`resposta.text`) em
  `data/raw/<dia>/page_<n>.json`. A pasta só é criada depois de uma resposta válida.
- Limitação conhecida: erros de ligação ou *timeout* não são repetidos.

**Load** ([`src/load.py`](src/load.py)) — `python src/load.py <dia>`:
- Lê os JSON do dia com `read_json` e desdobra os itens com `unnest` para a tabela
  `raw_api_orders` (uma linha por item, mais a coluna `extraction_date`).
- **Todas as colunas são `VARCHAR`:** um dia com dados corrompidos (ex.: um preço que
  não é número) é carregado na mesma e os problemas são apanhados pelos testes, em vez
  de o load rebentar sem dizer porquê.
- **Idempotente:** numa transação, apaga primeiro as linhas desse `extraction_date` e
  insere-as de novo — recarregar um dia não duplica linhas.
- Fecha a ligação no fim: o DuckDB só aceita um processo a escrever de cada vez.

### Tarefa 2 — Modelos dbt

- [`stg_orders`](dbt/models/staging/stg_orders.sql) (view): os itens **de um só dia**
  (`WHERE extraction_date = var('execution_date')`), com tipos corretos (`TRY_CAST`:
  um valor inválido fica `NULL` e é apanhado pelos testes) e `order_status` normalizado
  (`lower(trim(...))`).
- [`fact_sales`](dbt/models/marts/fact_sales.sql) (**incremental**, `delete+insert`,
  `unique_key = [order_id, order_item_id]`): troca as chaves naturais pelas chaves
  substitutas das dimensões da PA1, com o mesmo grão e as mesmas colunas. Ao
  reprocessar um dia, as linhas desse dia são apagadas e inseridas de novo.
- As dimensões e `raw_customers` são declaradas como `source` em
  [`sources.yml`](dbt/models/staging/sources.yml) e não são alteradas pelo dbt.
- Os `LEFT JOIN` às dimensões são de propósito: um item sem correspondência não
  desaparece em silêncio — é apanhado pelos testes antes de chegar à fact.

### Tarefa 3 — Testes dbt

Os testes correm sobre o `stg_orders` (o lote do dia), **antes** de a fact ser
atualizada. 10 testes, em [`schema.yml`](dbt/models/staging/schema.yml) e
[`dbt/tests/`](dbt/tests/):

| Categoria | Teste | O que garante |
|---|---|---|
| Unicidade | [`item_unico`](dbt/tests/item_unico.sql) | o par (`order_id`, `order_item_id`) — o grão da fact — não se repete |
| Não nulo | `not_null` em `order_id`, `customer_id`, `price` | campos essenciais preenchidos (e com tipo válido, por causa do `TRY_CAST`) |
| Integridade referencial | `relationships` `product_id` → `dim_product`, `seller_id` → `dim_seller`, `customer_id` → `raw_customers` | cada item encontra o produto, o vendedor e o cliente |
| Valores aceites | `accepted_values` em `order_status` | só os 8 estados conhecidos |
| Intervalo aceite | [`price_positivo`](dbt/tests/price_positivo.sql) | `price > 0` |
| Regra de negócio | [`compra_no_dia_do_lote`](dbt/tests/compra_no_dia_do_lote.sql) | a data de compra de cada item é o dia do lote (e é uma data válida) |

Os testes personalizados devolvem as **linhas que violam a regra**: 0 linhas = PASS.
A regra de negócio usa `IS DISTINCT FROM` em vez de `<>` para também falhar quando a
data é inválida (`NULL`).

Num dia limpo (2018-05-03): `PASS=10`. Para confirmar que os testes falham quando
devem, foram inseridos numa cópia da base de dados um item duplicado, um cliente
inexistente, um preço negativo e duas datas erradas: falharam `item_unico`,
`relationships` do `customer_id`, `price_positivo` e `compra_no_dia_do_lote`.

Output do `dbt test` (dia limpo e dia corrompido): ⏳ `evidence/dbt_test_[...].txt`

### Tarefa 4 — DAG no Airflow

[`airflow/dags/northmart_pa2.py`](airflow/dags/northmart_pa2.py):

```
extract >> load >> transform_staging >> test >> transform_marts
```

- **Agendamento diário** (`@daily`), de 2018-05-01 a 2018-05-14; cada execução passa o
  seu dia (`{{ ds }}`) aos scripts e ao dbt (`--vars`).
- **Testes entre o staging e o mart:** se a tarefa `test` falhar, a `transform_marts`
  não corre (`upstream_failed`) e a `fact_sales` desse dia não é tocada.
- **`max_active_runs=1`:** o backfill corre um dia de cada vez. Com dois dias em
  paralelo, o segundo processo falharia ao abrir o DuckDB, que só aceita um escritor.
- **`catchup=False`:** os dias antigos não arrancam sozinhos ao ligar a DAG; o backfill
  é lançado à mão (`airflow backfill create`).
- **Reprocessar um dia não duplica:** o load apaga o dia antes de o inserir, e a fact
  usa `delete+insert` pela chave `order_id` + `order_item_id`.

Evidências: ⏳
- Grelha do Airflow depois do backfill: `evidence/airflow_grid.png`
- Linhas da `fact_sales` antes e depois de reprocessar [DIA]: [ANTES] → [DEPOIS]

### Tarefa 5 — Incidente

⏳ **Dia corrompido:** [DIA]. **Testes que falharam:** [TESTES] (ver
`evidence/dbt_test_[...].txt`). A grelha mostra a tarefa `test` a vermelho e a
`transform_marts` em `upstream_failed`, por isso a `fact_sales` não foi atualizada
nesse dia: [contagem da fact antes e depois].

Como tratar o lote:

1. O lote de [DIA] fica guardado tal como chegou (JSON em `data/raw/[DIA]/` e linhas em `raw_api_orders`), sem correções à mão, para servir de prova e permitir repetir o processamento.
2. A `fact_sales` desse dia não é atualizada: a DAG parou na tarefa `test` e a `transform_marts` não correu, por isso os relatórios mostram um dia em falta, e não números errados.
3. A equipa responsável pela API é avisada com os testes que falharam ([TESTES]) e exemplos das linhas com defeito, para corrigir os dados na origem.
4. Quando chegarem dados corrigidos, corre-se de novo a DAG para esse dia: o extract volta a pedir os dados à API e o load substitui o lote antigo, porque apaga primeiro as linhas desse dia.
5. Se os testes passarem, a `transform_marts` atualiza a fact com `delete+insert` pela chave `order_id` + `order_item_id`, por isso repetir o dia não cria duplicados.

### Tarefa 6 — Tarefa mais lenta

⏳ Nas durações do Airflow (vista Gantt, [N] dias limpos), a tarefa mais lenta foi
**[TAREFA]**, com cerca de **[X] s**, contra [Y] s das restantes. A causa é [CAUSA].
Uma otimização seria [OTIMIZAÇÃO], o que reduziria [o quê] sem alterar o resultado da
`fact_sales`. _(máx. 100 palavras)_
