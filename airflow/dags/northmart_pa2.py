from datetime import datetime
from pathlib import Path

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

# Raiz do repositório, calculada a partir deste ficheiro (<raiz>/airflow/dags/northmart_pa2.py),
# para a DAG correr em qualquer máquina sem editar caminhos.
PROJETO = Path(__file__).resolve().parents[2]
PY = "~/venvs/pipeline/bin/python"
DBT = "~/venvs/pipeline/bin/dbt"
# Opções do dbt: têm de vir depois do subcomando (dbt run ... / dbt test ...).
# {{ ds }} = o dia que o Airflow está a processar.
OPCOES = "--project-dir dbt --profiles-dir dbt --vars '{execution_date: {{ ds }}}'"

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
        bash_command=f"cd {PROJETO} && {DBT} run --select stg_orders {OPCOES}")

    test = BashOperator(task_id="test",
        bash_command=f"cd {PROJETO} && {DBT} test --select stg_orders {OPCOES}")

    transform_marts = BashOperator(task_id="transform_marts",
        bash_command=f"cd {PROJETO} && {DBT} run --select fact_sales {OPCOES}")

    extract >> load >> transform_staging >> test >> transform_marts