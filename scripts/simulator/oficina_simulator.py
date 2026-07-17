#!/usr/bin/env python3
"""Gera tráfego sintético seguro nas APIs públicas da Oficina SOAT."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter
from typing import Any, Callable


PROFILES = {
    "cotidiano": {
        "chegada_cliente": 42,
        "consulta_os": 20,
        "catalogo_estoque": 13,
        "orcamento_os_inexistente": 5,
        "chave_idempotente_divergente": 3,
        "retry_idempotente": 7,
        "payload_invalido": 5,
        "operacao_nao_autorizada": 3,
        "usuario_operacional": 2,
    },
    "pico": {
        "chegada_cliente": 50,
        "consulta_os": 22,
        "catalogo_estoque": 12,
        "orcamento_os_inexistente": 3,
        "chave_idempotente_divergente": 2,
        "retry_idempotente": 5,
        "payload_invalido": 3,
        "operacao_nao_autorizada": 2,
        "usuario_operacional": 1,
    },
    "falhas": {
        "chegada_cliente": 15,
        "consulta_os": 10,
        "catalogo_estoque": 10,
        "orcamento_os_inexistente": 12,
        "chave_idempotente_divergente": 8,
        "retry_idempotente": 15,
        "payload_invalido": 15,
        "operacao_nao_autorizada": 10,
        "usuario_operacional": 5,
    },
}

NARRATIVES = {
    "chegada_cliente": "Tem um cliente com um carro chegando; vamos iniciar o atendimento",
    "consulta_os": "A equipe quer conferir a fila atual de ordens de serviço",
    "catalogo_estoque": "Chegou uma peça sintética; vamos cadastrá-la no catálogo",
    "orcamento_os_inexistente": "Vamos confirmar que não se cria orçamento para uma OS inexistente",
    "chave_idempotente_divergente": "Vamos confirmar que a mesma chave não aceita outra operação",
    "retry_idempotente": "A conexão oscilou; vamos repetir a solicitação com a mesma chave",
    "payload_invalido": "Vamos confirmar que um cadastro inválido é rejeitado de forma controlada",
    "operacao_nao_autorizada": "Vamos confirmar que uma chamada sem credencial é bloqueada",
    "usuario_operacional": "Um novo usuário sintético será cadastrado para a oficina",
}


@dataclasses.dataclass(frozen=True)
class RequestSpec:
    method: str
    path: str
    body: dict[str, Any] | None = None
    expected: tuple[int, ...] = (200,)
    token: bool = True
    idempotency_key: str | None = None


@dataclasses.dataclass
class Result:
    scenario: str
    status: int
    classification: str
    correlation_id: str
    detail: str = ""


@dataclasses.dataclass(frozen=True)
class Config:
    base_url: str
    token: str | None
    duration: int
    intensity: int
    profile: str
    seed: int
    dry_run: bool
    max_events: int
    max_cost_brl: float
    interval: float
    timeout: float
    cleanup: bool
    async_wait: float


class HttpClient:
    def __init__(self, config: Config):
        self.config = config

    def execute(self, spec: RequestSpec, correlation_id: str) -> tuple[int, Any]:
        if self.config.dry_run:
            return spec.expected[0], {"dryRun": True}
        headers = {"Accept": "application/json", "X-Correlation-Id": correlation_id}
        if spec.body is not None:
            headers["Content-Type"] = "application/json"
        if spec.idempotency_key:
            headers["X-Idempotency-Key"] = spec.idempotency_key
        if spec.token and self.config.token:
            headers["Authorization"] = f"Bearer {self.config.token}"
        data = json.dumps(spec.body).encode() if spec.body is not None else None
        request = urllib.request.Request(
            f"{self.config.base_url.rstrip('/')}{spec.path}", data=data, headers=headers, method=spec.method
        )
        try:
            with urllib.request.urlopen(request, timeout=self.config.timeout) as response:
                raw = response.read().decode()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read().decode()
            try:
                return error.code, json.loads(raw) if raw else None
            except json.JSONDecodeError:
                return error.code, None


def mask(value: str) -> str:
    return f"{value[:8]}...{value[-4:]}"


def synthetic_uuid(seed: int, sequence: int, label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"oficina-sim:{seed}:{sequence}:{label}"))


def synthetic_cpf(seed: int, sequence: int) -> str:
    base = f"{abs(seed) % 10000:04d}{sequence % 100000:05d}"
    digits = [int(char) for char in base]
    first = (sum(value * weight for value, weight in zip(digits, range(10, 1, -1))) * 10) % 11
    first = 0 if first == 10 else first
    second_digits = digits + [first]
    second = (sum(value * weight for value, weight in zip(second_digits, range(11, 1, -1))) * 10) % 11
    second = 0 if second == 10 else second
    return base + str(first) + str(second)


class Simulator:
    def __init__(self, config: Config, output: Callable[[str], None] = print):
        self.config = config
        self.output = output
        self.random = random.Random(config.seed)
        self.client = HttpClient(config)
        self.results: list[Result] = []
        self.created: list[tuple[str, str]] = []
        self.orders: list[str] = []

    def select_scenarios(self) -> list[str]:
        count = min(self.config.max_events, max(1, self.config.duration * self.config.intensity))
        weights = PROFILES[self.config.profile]
        return self.random.choices(list(weights), weights=list(weights.values()), k=count)

    def request(self, scenario: str, spec: RequestSpec, sequence: int) -> tuple[int, Any]:
        correlation_id = synthetic_uuid(self.config.seed, sequence, scenario)
        status, body = self.client.execute(spec, correlation_id)
        classification = "approved" if 200 <= status < 300 else "expected_rejection" if status in spec.expected else "regression"
        if status not in spec.expected and 200 <= status < 300:
            classification = "regression"
        detail = f"{spec.method} {spec.path}"
        self.results.append(Result(scenario, status, classification, correlation_id, detail))
        timestamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
        mode = "DRY-RUN" if self.config.dry_run else classification.upper()
        self.output(f"{timestamp} [{mode}] {scenario} HTTP {status} correlation={mask(correlation_id)} {detail}")
        return status, body

    def specs_for(self, scenario: str, sequence: int) -> list[RequestSpec]:
        marker = f"SIM-{self.config.seed}-{sequence}"
        key = synthetic_uuid(self.config.seed, sequence, "idempotency")
        fake_os = synthetic_uuid(self.config.seed, sequence, "os")
        if scenario == "chegada_cliente":
            return [RequestSpec("POST", "/api/v1/clientes", {
                "nome": f"Cliente Sintético {marker}", "documento": synthetic_cpf(self.config.seed, sequence),
                "telefone": "+5511999999999", "email": f"sim-{self.config.seed}-{sequence}@example.invalid",
            }, (201,), idempotency_key=key)]
        if scenario == "consulta_os":
            return [RequestSpec("GET", "/api/v1/ordens-servico?page=0&size=20", expected=(200,))]
        if scenario == "catalogo_estoque":
            return [RequestSpec("POST", "/api/v1/pecas", {
                "nome": f"Peça Sintética {marker}", "codigo": marker, "valorUnitario": 1.0,
            }, (201, 409), idempotency_key=key)]
        if scenario == "orcamento_os_inexistente":
            return [RequestSpec("POST", "/api/v1/orcamentos", {"ordemServicoId": fake_os}, (404,), idempotency_key=key)]
        if scenario == "chave_idempotente_divergente":
            first = {"nome": f"Cliente Idempotente {marker}",
                     "documento": synthetic_cpf(self.config.seed + 3, sequence),
                     "email": f"idempotente-{self.config.seed}-{sequence}@example.invalid"}
            second = dict(first, nome=f"Cliente Divergente {marker}")
            return [RequestSpec("POST", "/api/v1/clientes", first, (201,), idempotency_key=key),
                    RequestSpec("POST", "/api/v1/clientes", second, (409,), idempotency_key=key)]
        if scenario == "retry_idempotente":
            body = {"nome": f"Cliente Retry {marker}", "documento": synthetic_cpf(self.config.seed + 1, sequence),
                    "email": f"retry-{self.config.seed}-{sequence}@example.invalid"}
            spec = RequestSpec("POST", "/api/v1/clientes", body, (201,), idempotency_key=key)
            return [spec, spec]
        if scenario == "payload_invalido":
            return [RequestSpec("POST", "/api/v1/clientes", {"nome": ""}, (400,), idempotency_key=key)]
        if scenario == "operacao_nao_autorizada":
            return [RequestSpec("GET", "/api/v1/clientes?page=0&size=1", expected=(401,), token=False)]
        return [RequestSpec("POST", "/api/v1/usuarios", {
            "nome": f"Usuário Sintético {marker}", "documento": synthetic_cpf(self.config.seed + 2, sequence),
            "status": "ATIVO", "papeis": ["mecanico"],
        }, (201, 403), idempotency_key=key)]

    def response_id(self, body: Any, field: str, sequence: int) -> str:
        if isinstance(body, dict) and body.get(field):
            return str(body[field])
        return synthetic_uuid(self.config.seed, sequence, field)

    def execute_scenario(self, scenario: str, sequence: int) -> None:
        specs = self.specs_for(scenario, sequence)
        if scenario == "chegada_cliente":
            client_status, client = self.request(scenario, specs[0], sequence)
            if client_status != 201:
                return
            client_id = self.response_id(client, "clienteId", sequence)
            plate_number = (abs(self.config.seed) * 97 + sequence) % 10000
            vehicle_status, vehicle = self.request(scenario, RequestSpec("POST", f"/api/v1/clientes/{client_id}/veiculos", {
                "placa": f"SIM{plate_number:04d}", "marca": "Oficina SIM", "modelo": "Veículo Sintético", "ano": 2026,
            }, (201,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "vehicle-key")), sequence)
            if vehicle_status != 201:
                return
            vehicle_id = self.response_id(vehicle, "veiculoId", sequence)
            _, order = self.request(scenario, RequestSpec("POST", "/api/v1/ordens-servico", {
                "clienteId": client_id, "veiculoId": vehicle_id,
                "descricaoProblema": f"Atendimento sintético SIM-{self.config.seed}-{sequence}",
            }, (201,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "os-key")), sequence)
            order_id = self.response_id(order, "ordemServicoId", sequence)
            self.orders.append(order_id)
            _, order_view = self.request("capabilities_os", RequestSpec(
                "GET", f"/api/v1/ordens-servico/{order_id}", expected=(200,)), sequence)
            if isinstance(order_view, dict) and "INICIAR_EXECUCAO" in order_view.get("acoesPermitidas", []):
                self.results[-1].classification = "regression"
                self.results[-1].detail += " (INICIAR_EXECUCAO exposto indevidamente)"
            self.request("transicao_direta_bloqueada", RequestSpec(
                "PATCH", f"/api/v1/ordens-servico/{order_id}/estado",
                {"estado": "EM_EXECUCAO", "motivo": "Tentativa sintética de bypass da aprovação"},
                (409,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "direct-execution")), sequence)
            return
        if scenario == "catalogo_estoque":
            _, part = self.request(scenario, specs[0], sequence)
            part_id = self.response_id(part, "pecaId", sequence)
            self.request(scenario, RequestSpec("POST", "/api/v1/estoques/movimentos/entrada", {
                "pecaId": part_id, "quantidade": 2, "motivo": f"Carga sintética SIM-{self.config.seed}-{sequence}",
            }, (201,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "stock-in")), sequence)
            self.request(scenario, RequestSpec("POST", "/api/v1/estoques/movimentos/reserva", {
                "pecaId": part_id, "ordemServicoId": synthetic_uuid(self.config.seed, sequence, "stock-os"),
                "quantidade": 999999, "motivo": "Falha controlada: estoque insuficiente",
            }, (409, 422), idempotency_key=synthetic_uuid(self.config.seed, sequence, "stock-fail")), sequence)
            return
        if scenario == "usuario_operacional":
            status, user = self.request(scenario, specs[0], sequence)
            if status == 201:
                user_id = self.response_id(user, "usuarioId", sequence)
                document = synthetic_cpf(self.config.seed + 2, sequence)
                self.created.append(("usuario", user_id))
                self.request(scenario, RequestSpec("PUT", f"/api/v1/usuarios/{user_id}", {
                    "nome": f"Usuário Sintético SIM-{self.config.seed}-{sequence}", "documento": document,
                    "status": "BLOQUEADO", "papeis": ["mecanico"],
                }, (200,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "user-block")), sequence)
                self.request(scenario, RequestSpec("PUT", f"/api/v1/usuarios/{user_id}", {
                    "nome": f"Usuário Sintético SIM-{self.config.seed}-{sequence}", "documento": document,
                    "status": "ATIVO", "papeis": ["mecanico"],
                }, (200,), idempotency_key=synthetic_uuid(self.config.seed, sequence, "user-reactivate")), sequence)
                if self.config.cleanup:
                    self.request(scenario, RequestSpec(
                        "DELETE", f"/api/v1/usuarios/{user_id}", expected=(204,),
                        idempotency_key=synthetic_uuid(self.config.seed, sequence, "user-cleanup")), sequence)
            return
        for spec in specs:
            self.request(scenario, spec, sequence)

    def run(self) -> int:
        scenarios = self.select_scenarios()
        estimated_cost = len(scenarios) * 0.001
        if estimated_cost > self.config.max_cost_brl:
            raise ValueError(f"custo estimado R$ {estimated_cost:.3f} excede limite R$ {self.config.max_cost_brl:.2f}")
        self.output(f"Simulação seed={self.config.seed} profile={self.config.profile} events={len(scenarios)} "
                    f"dry_run={str(self.config.dry_run).lower()} custo_estimado=R${estimated_cost:.3f}")
        for sequence, scenario in enumerate(scenarios, 1):
            self.output(NARRATIVES[scenario])
            self.execute_scenario(scenario, sequence)
            if not self.config.dry_run and self.config.interval:
                time.sleep(self.config.interval)
        if self.config.async_wait and not self.config.dry_run:
            self.output(f"Aguardando {self.config.async_wait:.1f}s por efeitos assíncronos")
            time.sleep(self.config.async_wait)
        self.summary()
        return 1 if any(result.classification == "regression" for result in self.results) else 0

    def summary(self) -> None:
        totals = Counter(result.classification for result in self.results)
        scenarios = Counter(result.scenario for result in self.results)
        digest = hashlib.sha256("|".join(r.scenario for r in self.results).encode()).hexdigest()[:12]
        self.output("Resumo: " + " ".join([
            f"requests={len(self.results)}", f"approved={totals['approved']}",
            f"expected_rejections={totals['expected_rejection']}", f"regressions={totals['regression']}",
            f"digest={digest}", f"scenarios={json.dumps(dict(sorted(scenarios.items())), ensure_ascii=False)}",
        ]))


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("deve ser maior que zero")
    return parsed


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=os.getenv("OFICINA_SIM_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--duration", type=positive_int, default=1, help="janelas lógicas de execução")
    parser.add_argument("--intensity", type=positive_int, choices=range(1, 101), default=5, help="eventos por janela")
    parser.add_argument("--profile", choices=PROFILES, default="cotidiano")
    parser.add_argument("--seed", type=int, default=20260715)
    parser.add_argument("--max-events", type=positive_int, default=100)
    parser.add_argument("--max-cost-brl", type=float, default=1.0)
    parser.add_argument("--interval", type=float, default=0.0)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--async-wait", type=float, default=0.0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--cleanup", action="store_true", help="reservado a recursos que tenham exclusão segura no contrato")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    token = os.getenv("OFICINA_SIM_TOKEN")
    if not args.dry_run and not token:
        print("erro: OFICINA_SIM_TOKEN é obrigatório fora do dry-run", file=sys.stderr)
        return 2
    if args.max_cost_brl < 0 or args.interval < 0 or args.timeout <= 0 or args.async_wait < 0:
        print("erro: limites de custo/tempo inválidos", file=sys.stderr)
        return 2
    config = Config(args.base_url, token, args.duration, args.intensity, args.profile, args.seed,
                    args.dry_run, args.max_events, args.max_cost_brl, args.interval, args.timeout,
                    args.cleanup, args.async_wait)
    try:
        return Simulator(config).run()
    except (ValueError, urllib.error.URLError) as error:
        print(f"erro: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
