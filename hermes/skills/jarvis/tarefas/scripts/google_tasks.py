#!/usr/bin/env python3
"""Tarefas do Renato no Google Tasks (lista padrão, "Minhas tarefas"). Saída em JSON.

  listar [--ate AAAA-MM-DD]                    pendentes, por data (sem data no fim)
  criar TITULO [--data AAAA-MM-DD] [--notas T]
  concluir ID | adiar ID AAAA-MM-DD | apagar ID

Usa o token do Google que a skill google-workspace grava em ~/.hermes/google_token.json,
autorizado com os escopos de Calendar e Tasks (docs/aprendizado/70-integracoes.md).
Rode pelo `scripts/tarefas`, que escolhe o Python do Hermes (é ele que tem as bibliotecas do Google).
"""
import argparse
import datetime
import json
import os
import sys
from pathlib import Path

ESCOPO = "https://www.googleapis.com/auth/tasks"
LISTA = "@default"


def sair(msg):
    print(f"tarefas: {msg}", file=sys.stderr)
    sys.exit(1)


def data_valida(texto):
    try:
        return datetime.date.fromisoformat(texto).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"data inválida '{texto}': use AAAA-MM-DD")


def checar_escopos(token):
    if ESCOPO not in (token.get("scopes") or []):
        return ("o token do Google não tem o escopo do Google Tasks: autorize de novo com "
                "calendar e tasks (docs/aprendizado/70-integracoes.md)")
    return None


def servico_google():
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build

    caminho = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes")) / "google_token.json"
    if not caminho.exists():
        sair(f"sem token do Google em {caminho}")
    token = json.loads(caminho.read_text(encoding="utf-8"))
    erro = checar_escopos(token)
    if erro:
        sair(erro)
    creds = Credentials.from_authorized_user_info(token, token["scopes"])
    if not creds.valid:
        creds.refresh(Request())  # só em memória: o refresh_token no arquivo continua valendo
    return build("tasks", "v1", credentials=creds, cache_discovery=False)


def due(data):
    return f"{data}T00:00:00.000Z"  # o Google Tasks guarda só a data; a hora é ignorada


def resumo(t):
    return {"id": t["id"], "titulo": t.get("title", ""),
            "data": (t.get("due") or "")[:10] or None, "notas": t.get("notes") or None}


def listar(tasks, ate=None):
    itens, pagina = [], None
    while True:
        resp = tasks.list(tasklist=LISTA, showCompleted=False, showHidden=False,
                          maxResults=100, pageToken=pagina).execute()
        itens += [resumo(t) for t in resp.get("items", [])]
        pagina = resp.get("nextPageToken")
        if not pagina:
            break
    if ate:
        itens = [t for t in itens if t["data"] and t["data"] <= ate]
    return sorted(itens, key=lambda t: (t["data"] is None, t["data"] or "", t["titulo"]))


def main(argv=None, servico=servico_google):
    p = argparse.ArgumentParser(prog="tarefas", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("listar")
    s.add_argument("--ate", type=data_valida)
    s = sub.add_parser("criar")
    s.add_argument("titulo")
    s.add_argument("--data", type=data_valida)
    s.add_argument("--notas")
    s = sub.add_parser("concluir")
    s.add_argument("id")
    s = sub.add_parser("adiar")
    s.add_argument("id")
    s.add_argument("data", type=data_valida)
    s = sub.add_parser("apagar")
    s.add_argument("id")
    a = p.parse_args(argv)

    tasks = servico().tasks()
    if a.cmd == "listar":
        saida = listar(tasks, a.ate)
    elif a.cmd == "criar":
        corpo = {"title": a.titulo}
        if a.data:
            corpo["due"] = due(a.data)
        if a.notas:
            corpo["notes"] = a.notas
        saida = resumo(tasks.insert(tasklist=LISTA, body=corpo).execute())
    elif a.cmd == "concluir":
        saida = resumo(tasks.patch(tasklist=LISTA, task=a.id, body={"status": "completed"}).execute())
    elif a.cmd == "adiar":
        saida = resumo(tasks.patch(tasklist=LISTA, task=a.id, body={"due": due(a.data)}).execute())
    else:
        tasks.delete(tasklist=LISTA, task=a.id).execute()
        saida = {"id": a.id, "apagada": True}
    print(json.dumps(saida, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
