import sys
import time
from pathlib import Path

import requests

URL = "http://localhost:8000/orders"
MAX_TENTATIVAS = 5


def pedir_pagina(data, pagina):
    for tentativa in range(1, MAX_TENTATIVAS + 1):
        resposta = requests.get(URL, params={"date": data, "page": pagina}, timeout=10)

        if resposta.status_code == 200:
            return resposta

        if resposta.status_code == 503:
            print(f"Página {pagina}: 503, tentativa {tentativa} de {MAX_TENTATIVAS}")
            time.sleep(tentativa)
            continue

        resposta.raise_for_status()

    raise RuntimeError(f"A página {pagina} falhou após {MAX_TENTATIVAS} tentativas")


def extrair_dia(data):
    pasta = Path("data/raw") / data

    pagina = 1
    total_paginas = 1
    total_itens = 0

    while pagina <= total_paginas:
        resposta = pedir_pagina(data, pagina)
        dados = resposta.json()

        # Só cria a pasta depois de uma resposta válida.
        pasta.mkdir(parents=True, exist_ok=True)
        (pasta / f"page_{pagina}.json").write_text(resposta.text, encoding="utf-8")

        total_paginas = dados["total_pages"]
        total_itens += len(dados["items"])
        pagina = pagina + 1

    print(f"{data}: {total_paginas} páginas, {total_itens} itens")
    return total_itens


if __name__ == "__main__":
    extrair_dia(sys.argv[1])
