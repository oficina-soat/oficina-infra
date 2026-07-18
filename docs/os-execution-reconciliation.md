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

## Limites de segurança

- O JWT é obrigatório, permanece somente em memória e nunca é impresso.
- O modo de escrita trata `201` como criação e confirma um eventual `409` por meio da consulta da associação atual.
- OS em `EM_DIAGNOSTICO`, `AGUARDANDO_APROVACAO`, `EM_EXECUCAO` ou `FINALIZADA` não são reconciliadas automaticamente. A API pública cria toda execução em `CRIADA`; portanto, avançar a execução para acompanhar uma OS histórica exigiria uma decisão de negócio e comandos que podem produzir eventos.
- O código `0` indica ausência de divergências, `2` indica divergências ainda abertas e outros códigos indicam falha de configuração ou comunicação.

O monitor complementa o [simulador de operação da oficina](workshop-simulator.md). A associação normal continua sendo criada pelo consumo idempotente de `ordemDeServicoCriada`; o script é um mecanismo de detecção e recuperação controlada, não um segundo fluxo de domínio.
