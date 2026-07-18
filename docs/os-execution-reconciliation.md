# Reconciliação entre OS e execução

O monitor [reconcile-os-executions.sh](../scripts/manual/reconcile-os-executions.sh) compara todas as Ordens de Serviço operacionais com as execuções do `oficina-execution-service`. Uma OS é considerada operacional enquanto não estiver em `ENTREGUE`.

O modo padrão é somente leitura e retorna código `2` quando encontra divergências, permitindo integração com um monitor operacional sem registrar credenciais ou alterar estado de negócio:

```bash
OFICINA_API_BASE_URL="https://<api-id>.execute-api.us-east-1.amazonaws.com/api/v1" \
OFICINA_AUTH_TOKEN="<jwt-operacional>" \
scripts/manual/reconcile-os-executions.sh
```

Para uma OS ainda em `RECEBIDA`, o script pode criar a execução ausente em `CRIADA` com uma chave de idempotência derivada do identificador da OS. Essa operação não altera o estado da OS:

```bash
OFICINA_API_BASE_URL="https://<api-id>.execute-api.us-east-1.amazonaws.com/api/v1" \
OFICINA_AUTH_TOKEN="<jwt-operacional>" \
scripts/manual/reconcile-os-executions.sh --reconcile-received
```

Para registros históricos do `lab` em estados avançados, a política aprovada cria diretamente na tabela canônica uma execução compatível com o estado atual da OS e um único registro de histórico de backfill:

| Estado da OS | Estado criado na execução |
|---|---|
| `EM_DIAGNOSTICO` | `EM_DIAGNOSTICO` |
| `AGUARDANDO_APROVACAO` | `DIAGNOSTICO_CONCLUIDO` |
| `EM_EXECUCAO` | `EM_REPARO` |
| `FINALIZADA` | `REPARO_CONCLUIDO` |

O modo exige credenciais AWS autorizadas para o DynamoDB e aceita exclusivamente a tabela `oficina-execution-lab-execucoes`:

```bash
OFICINA_API_BASE_URL="https://<api-id>.execute-api.us-east-1.amazonaws.com/api/v1" \
OFICINA_AUTH_TOKEN="<jwt-operacional>" \
scripts/manual/reconcile-os-executions.sh --backfill-historical
```

O identificador da execução e o identificador do histórico são derivados deterministicamente da OS. Snapshot e histórico são gravados na mesma transação com condição de ausência; uma repetição confirma a associação existente em vez de criar outra execução.

## Limites de segurança

- O JWT é obrigatório, permanece somente em memória e nunca é impresso.
- O modo de escrita trata `201` como criação e confirma um eventual `409` por meio da consulta da associação atual.
- O backfill histórico não usa comandos de domínio, não publica eventos retroativos, não cria Outbox e não altera estado da OS. Ele materializa somente o snapshot técnico compatível e um histórico que identifica explicitamente a reparação operacional.
- O backfill não é habilitado por padrão, rejeita qualquer nome de tabela diferente de `oficina-execution-lab-execucoes` e não se aplica a novos ambientes nem à produção.
- A associação normal continua sendo criada por `ordemDeServicoCriada`; o backfill não deve ser usado como fluxo alternativo para novas OS.
- O código `0` indica ausência de divergências, `2` indica divergências ainda abertas e outros códigos indicam falha de configuração ou comunicação.

O monitor complementa o [simulador de operação da oficina](workshop-simulator.md). A associação normal continua sendo criada pelo consumo idempotente de `ordemDeServicoCriada`; o script é um mecanismo de detecção e recuperação controlada, não um segundo fluxo de domínio.
