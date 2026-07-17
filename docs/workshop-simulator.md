# Simulador de operação da oficina

O simulador gera tráfego sintético reproduzível nas APIs públicas dos serviços em ambientes não produtivos. Ele usa somente a biblioteca padrão do Python 3, não registra o bearer token e retorna código diferente de zero quando uma resposta diverge do resultado esperado.

## Execução segura

Comece sempre pelo planejamento sem chamadas HTTP:

```bash
scripts/manual/simulate-workshop.py --dry-run --profile cotidiano --duration 2 --intensity 5 --seed 20260715
```

Para uma execução controlada, forneça a URL pública e o token apenas por variáveis de ambiente:

```bash
export OFICINA_SIM_BASE_URL="https://<api-id>.execute-api.us-east-1.amazonaws.com"
export OFICINA_SIM_TOKEN="<token-administrativo>"
scripts/manual/simulate-workshop.py --profile cotidiano --duration 1 --intensity 3 --max-events 3 --max-cost-brl 0.01 --async-wait 5
unset OFICINA_SIM_TOKEN
```

O token nunca aparece no console. `--max-events` limita o volume, enquanto `--max-cost-brl` aplica uma trava conservadora de custo estimado antes da primeira chamada. O simulador recusa execução real sem `OFICINA_SIM_TOKEN`.

## Perfis e cenários

- `cotidiano`: prioriza chegada de clientes, veículos e consulta de ordens de serviço;
- `pico`: aumenta o peso dos fluxos predominantes;
- `falhas`: aumenta falhas controladas e retries para diagnóstico.

O catálogo inclui cliente → veículo → OS, consulta das capacidades da OS recém-criada, bloqueio da tentativa de iniciar execução diretamente, consulta da fila de OS, peça → entrada → reserva com estoque insuficiente, criação de orçamento para OS inexistente, replay idempotente, conflito quando a mesma chave idempotente recebe outro payload, payload inválido, chamada sem autorização e usuário operacional com bloqueio/reativação. A combinação de `profile` e `seed` gera sempre o mesmo plano.

A recusa autenticada criada diretamente pelo simulador foi removida: o fluxo canônico atual gera o orçamento após o diagnóstico e a decisão do cliente ocorre pelos links públicos de uso único. Aprovação, recusa, expiração e reuso desses links dependem da captura segura da mensagem entregue e permanecem no roteiro de homologação do lab, não neste gerador genérico de tráfego HTTP. Eventos fora de ordem continuam cobertos nos testes de integração dos serviços, pois não devem ser publicados pela API pública.

Dados mutáveis recebem `SIM-<seed>-<sequência>` no nome, código, descrição ou e-mail com domínio reservado `example.invalid`. Com `--cleanup`, somente usuários criados pela própria sessão são inativados; clientes, veículos, OS, peças e movimentos são preservados porque seus contratos não oferecem exclusão segura. O simulador nunca remove dados preexistentes.

## Classificação e diagnóstico

Cada request registra timestamp UTC, cenário, status HTTP e `correlationId` mascarado. O resumo separa:

- `approved`: resposta de sucesso esperada;
- `expected_rejection`: falha controlada esperada, como HTTP 400, 401 ou 404;
- `regression`: qualquer divergência do contrato esperado, fazendo o processo retornar código `1`.

`--async-wait` aguarda efeitos de Outbox/mensageria depois das ações. O resumo contém um digest do plano e contagem por cenário para comparação entre execuções, sem persistir credenciais.

## Validação

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/manual/simulate-workshop.py --dry-run --profile falhas --duration 2 --intensity 5 --seed 20260715
```

Em 2026-07-15, uma execução controlada no `lab` com `seed=4`, um evento e custo estimado de `R$ 0,001` criou cliente, veículo e OS sintéticos com três respostas HTTP `201`, sem regressões. Tentativas diagnósticas anteriores também demonstraram que colisões de placa e de chave idempotente são classificadas como regressão e resultam em código de saída `1`.
