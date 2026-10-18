"""PA1 · Tarefa 4 — Benchmark CSV vs Parquet vs Parquet particionado.

Executar a partir da raiz do repositório, depois de build_model.sql e export.sql:
    python src/benchmark.py

Método:
- as 3 queries de sql/benchmark_queries.sql correm sobre uma view `fact` que
  aponta, à vez, para cada formato em data/curated/;
- por cada formato e query: 1 execução de aquecimento (não conta) seguida de
  RUNS execuções cronometradas com time.perf_counter;
- reporta-se a mediana (menos sensível a picos que a média), o mínimo e o máximo;
- confirma-se que os 3 formatos devolvem o mesmo resultado.

Resultados: evidence/benchmark_results.csv e evidence/benchmark.md
"""
import csv
import statistics
import time
from pathlib import Path

import duckdb

RUNS = 5
DB = "northmart.duckdb"
CURATED = Path("data/curated")
EVIDENCE = Path("evidence")

# Cada formato expõe as mesmas colunas, incluindo year_month (AAAAMM).
# No particionado, year_month vem do nome das pastas (Hive partitioning).
FORMATS = {
    "CSV": (
        CURATED / "fact_sales.csv",
        "SELECT *, date_key // 100 AS year_month "
        "FROM read_csv('data/curated/fact_sales.csv')",
    ),
    "Parquet": (
        CURATED / "fact_sales.parquet",
        "SELECT *, date_key // 100 AS year_month "
        "FROM read_parquet('data/curated/fact_sales.parquet')",
    ),
    "Parquet particionado (mês)": (
        CURATED / "fact_sales_by_month",
        "SELECT * FROM read_parquet('data/curated/fact_sales_by_month/**/*.parquet', "
        "hive_partitioning = true)",
    ),
}

QUERY_NAMES = ["Q1 receita por mês", "Q2 um mês (2018-05)", "Q3 top 5 categorias"]


def size_mb(path: Path) -> float:
    files = [path] if path.is_file() else [f for f in path.rglob("*") if f.is_file()]
    return sum(f.stat().st_size for f in files) / 1024 / 1024


def load_queries() -> list[str]:
    sql = Path("sql/benchmark_queries.sql").read_text(encoding="utf-8")
    lines = [l for l in sql.splitlines() if not l.strip().startswith("--")]
    return [q.strip() for q in "\n".join(lines).split(";") if q.strip()]


def main() -> None:
    queries = load_queries()
    # read_only: o benchmark só lê; dim_product vem da base de dados
    con = duckdb.connect(DB, read_only=True)

    rows = []
    answers = {}
    for fmt, (path, source) in FORMATS.items():
        con.execute(f"CREATE OR REPLACE TEMP VIEW fact AS {source}")
        for name, query in zip(QUERY_NAMES, queries):
            answers.setdefault(name, []).append(con.sql(query).fetchall())  # aquecimento
            times = []
            for _ in range(RUNS):
                start = time.perf_counter()
                con.sql(query).fetchall()
                times.append((time.perf_counter() - start) * 1000)
            rows.append({
                "formato": fmt,
                "tamanho_mb": round(size_mb(path), 2),
                "query": name,
                "mediana_ms": round(statistics.median(times), 1),
                "min_ms": round(min(times), 1),
                "max_ms": round(max(times), 1),
            })

    for name, results in answers.items():
        assert all(r == results[0] for r in results), f"{name}: formatos dão resultados diferentes"

    EVIDENCE.mkdir(exist_ok=True)
    with open(EVIDENCE / "benchmark_results.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    header = "| Formato | Tamanho (MB) | Query | Mediana (ms) | Mín (ms) | Máx (ms) |"
    table = [header, "|---|---:|---|---:|---:|---:|"]
    table += [
        f"| {r['formato']} | {r['tamanho_mb']} | {r['query']} | "
        f"{r['mediana_ms']} | {r['min_ms']} | {r['max_ms']} |"
        for r in rows
    ]
    md = "\n".join(table)
    (EVIDENCE / "benchmark.md").write_text(
        f"# Benchmark PA1\n\n{RUNS} execuções por query após 1 de aquecimento; "
        f"DuckDB {duckdb.__version__}.\n\n{md}\n",
        encoding="utf-8",
    )
    print(md)
    print("\nOs 3 formatos devolvem resultados idênticos nas 3 queries.")


if __name__ == "__main__":
    main()
