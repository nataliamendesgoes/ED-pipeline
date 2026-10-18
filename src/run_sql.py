import sys
import duckdb

db = sys.argv[2] if len(sys.argv) > 2 else ":memory:"
con = duckdb.connect(db)
sql = open(sys.argv[1], encoding="utf-8").read()

for stmt in sql.split(";"):
    if stmt.strip():
        rel = con.sql(stmt)
        if rel is not None:
            rel.show()
