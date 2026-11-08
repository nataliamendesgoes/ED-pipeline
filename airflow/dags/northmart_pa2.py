from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

PROJETO = "/mnt/c/Users/natal/Dev/ED-work"
PY = "~/venvs/pipeline/bin/python"
DBT = "~/venvs/pipeline/bin/dbt --project-dir dbt --profiles-dir dbt"
DIA = "--vars '{execution_date: {{ ds }}}'"   # {{ ds }} = o dia que o Airflow está a processar

with DAG(
    dag_id="northmart_pa2",
    start_date=datetime(2018, 5, 1),
    end_date=datetime(2018, 5, 14),
    schedule= "@daily",          
    catchup=False,
    max_active_runs=1,   
) as dag:

    extract = BashOperator(task_id="extract",
        bash_command=f"cd {PROJETO} && {PY} src/extract.py {{{{ ds }}}}")

    load = BashOperator(task_id="load",
        bash_command=f"cd {PROJETO} && {PY} src/load.py {{{{ ds }}}}")

    transform_staging = BashOperator(task_id="transform_staging",
        bash_command=f"cd {PROJETO} && {DBT} run --select stg_orders {DIA}")

    test = BashOperator(task_id="test",
        bash_command=f"cd {PROJETO} && {DBT} test --select stg_orders {DIA}")

    transform_marts = BashOperator(task_id="transform_marts",
        bash_command=f"cd {PROJETO} && {DBT} run --select fact_sales {DIA}")

    extract >> load >> transform_staging >> test >> transform_marts