#!/usr/bin/env bash
# Arranca o Airflow (scheduler + servidor web) no WSL, a ler as DAGs deste projeto.
# Executar no Ubuntu: bash airflow/start_airflow.sh   ->   http://localhost:8080
PROJETO="$(cd "$(dirname "$0")/.." && pwd)"

export AIRFLOW_HOME="$HOME/airflow"
export AIRFLOW__CORE__DAGS_FOLDER="$PROJETO/airflow/dags"
export AIRFLOW__CORE__LOAD_EXAMPLES=False
# o standalone lança o scheduler e o servidor web como subprocessos "airflow"
export PATH="$HOME/venvs/airflow/bin:$PATH"

exec airflow standalone
