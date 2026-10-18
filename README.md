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

_Por fazer._

### Tarefa 4 — Parquet e benchmark

_Por fazer._

### Tarefa 5 — Data warehouse, data lake ou lakehouse?

_Por fazer._
