"""Testes do hermes/skills/jarvis/tarefas/scripts/google_tasks.py com um Google Tasks falso."""
import importlib.util
import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "google_tasks", RAIZ / "hermes/skills/jarvis/tarefas/scripts/google_tasks.py")
gt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gt)


class Req:
    def __init__(self, fn):
        self.fn = fn

    def execute(self):
        return self.fn()


class FakeTasks:
    """Imita service.tasks() da API: list/insert/patch/delete, com paginação de 2 em 2."""

    def __init__(self):
        self.itens = {}
        self.n = 0
        self.listas = []

    def list(self, tasklist, showCompleted=True, showHidden=False, maxResults=100, pageToken=None):
        self.listas.append(tasklist)
        abertos = [t for t in self.itens.values() if showCompleted or t.get("status") != "completed"]
        ini = int(pageToken or 0)
        pagina = abertos[ini:ini + 2]
        resp = {"items": pagina}
        if ini + 2 < len(abertos):
            resp["nextPageToken"] = str(ini + 2)
        return Req(lambda: resp)

    def insert(self, tasklist, body):
        self.n += 1
        t = dict(body, id=f"t{self.n}", status="needsAction")
        self.itens[t["id"]] = t
        return Req(lambda: t)

    def patch(self, tasklist, task, body):
        self.itens[task].update(body)
        return Req(lambda: self.itens[task])

    def delete(self, tasklist, task):
        del self.itens[task]
        return Req(lambda: "")


class FakeService:
    def __init__(self):
        self._tasks = FakeTasks()

    def tasks(self):
        return self._tasks


def rodar(svc, *args):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        try:
            rc = gt.main(list(args), servico=lambda: svc)
        except SystemExit as e:
            rc = e.code
    return rc, out.getvalue(), err.getvalue()


class TestGoogleTasks(unittest.TestCase):
    def setUp(self):
        self.svc = FakeService()

    def test_criar_com_data_grava_due_em_rfc3339(self):
        rc, out, _ = rodar(self.svc, "criar", "Pagar a luz", "--data", "2026-10-24", "--notas", "#casa")
        self.assertEqual(rc, 0)
        t = self.svc.tasks().itens["t1"]
        self.assertEqual(t["title"], "Pagar a luz")
        self.assertEqual(t["due"], "2026-10-24T00:00:00.000Z")
        self.assertEqual(t["notes"], "#casa")
        self.assertEqual(json.loads(out)["data"], "2026-10-24")

    def test_criar_sem_data_nao_manda_due(self):
        rodar(self.svc, "criar", "Ler sobre WireGuard")
        self.assertNotIn("due", self.svc.tasks().itens["t1"])

    def test_data_invalida_e_recusada_sem_chamar_a_api(self):
        rc, _, err = rodar(self.svc, "criar", "X", "--data", "24/10/2026")
        self.assertNotEqual(rc, 0)
        self.assertIn("AAAA-MM-DD", err)
        self.assertEqual(self.svc.tasks().itens, {})

    def test_listar_ordena_por_data_sem_data_no_fim_e_pagina(self):
        rodar(self.svc, "criar", "C sem data")
        rodar(self.svc, "criar", "B", "--data", "2026-10-25")
        rodar(self.svc, "criar", "A", "--data", "2026-10-24")
        rc, out, _ = rodar(self.svc, "listar")
        self.assertEqual(rc, 0)
        self.assertEqual([t["titulo"] for t in json.loads(out)], ["A", "B", "C sem data"])

    def test_listar_ate_filtra_vencidas_e_do_dia_e_ignora_sem_data(self):
        rodar(self.svc, "criar", "Ontem", "--data", "2026-10-22")
        rodar(self.svc, "criar", "Hoje", "--data", "2026-10-23")
        rodar(self.svc, "criar", "Amanha", "--data", "2026-10-24")
        rodar(self.svc, "criar", "Sem data")
        _, out, _ = rodar(self.svc, "listar", "--ate", "2026-10-23")
        self.assertEqual([t["titulo"] for t in json.loads(out)], ["Ontem", "Hoje"])

    def test_concluir_some_da_lista_de_pendentes(self):
        rodar(self.svc, "criar", "Feita")
        rodar(self.svc, "criar", "Aberta")
        rc, _, _ = rodar(self.svc, "concluir", "t1")
        self.assertEqual(rc, 0)
        self.assertEqual(self.svc.tasks().itens["t1"]["status"], "completed")
        _, out, _ = rodar(self.svc, "listar")
        self.assertEqual([t["titulo"] for t in json.loads(out)], ["Aberta"])

    def test_adiar_troca_a_data(self):
        rodar(self.svc, "criar", "X", "--data", "2026-10-24")
        rodar(self.svc, "adiar", "t1", "2026-10-30")
        self.assertEqual(self.svc.tasks().itens["t1"]["due"], "2026-10-30T00:00:00.000Z")

    def test_apagar(self):
        rodar(self.svc, "criar", "X")
        rc, _, _ = rodar(self.svc, "apagar", "t1")
        self.assertEqual(rc, 0)
        self.assertEqual(self.svc.tasks().itens, {})

    def test_usa_a_lista_padrao(self):
        rodar(self.svc, "listar")
        self.assertEqual(self.svc.tasks().listas, ["@default"])

    def test_token_sem_escopo_de_tasks_da_erro_claro(self):
        msg = gt.checar_escopos({"scopes": ["https://www.googleapis.com/auth/calendar"]})
        self.assertIn("tasks", msg)
        self.assertIsNone(gt.checar_escopos({"scopes": [gt.ESCOPO]}))


if __name__ == "__main__":
    unittest.main(verbosity=1)
