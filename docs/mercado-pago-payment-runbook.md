# Runbook da integração Mercado Pago

## Escopo

Este runbook cobre a criação e reconciliação de pagamentos PIX pelo `oficina-billing-service`. O API Gateway expõe o webhook do Mercado Pago sem JWT porque a chamada parte do provedor; o Billing exige e valida `x-signature`, `x-request-id`, `data.id` e a janela temporal antes de consultar a API do Mercado Pago. Nenhum status recebido no corpo do webhook é aceito como evidência financeira.

## Configuração

Configure no executor do deploy, sem persistir os valores no Git:

- `OFICINA_MERCADO_PAGO_ENABLED=true`;
- `OFICINA_MERCADO_PAGO_ACCESS_TOKEN` com o token do ambiente correspondente;
- `OFICINA_MERCADO_PAGO_WEBHOOK_SECRET` com o secret da aplicação no Mercado Pago, distinto do token;
- opcionalmente `OFICINA_MERCADO_PAGO_PAYER_EMAIL` e `OFICINA_MERCADO_PAGO_API_URL`.

O script [apply-microservices.sh](../scripts/manual/apply-microservices.sh) materializa esses valores no secret Kubernetes `oficina-billing-service-mercado-pago-env`. O valor do secret, a assinatura, o código PIX, o QR Code e o token não devem aparecer em logs, métricas, traces ou evidências.

No painel do Mercado Pago, configure a notificação de pagamentos para:

```text
https://<api-gateway>/api/v1/integracoes/mercado-pago/webhooks
```

Use credenciais e aplicação de teste no `lab`; produção deve usar aplicação, token e secret próprios.

## Sinais e alertas

O collector descrito em [New Relic OpenTelemetry Collector](new-relic-otel-collector.md) coleta as métricas do Billing. Crie alertas separados por ambiente para:

- crescimento de `payment.provider.failures.count` ou `payment.provider.unavailable.count` por 5 minutos;
- p95 de `payment.provider.request.duration` acima de 10 segundos por 5 minutos;
- respostas `5xx` da rota do webhook no API Gateway;
- pagamento em `CRIADO` com `provedor=mercado-pago` além do vencimento ou por mais de 30 minutos.

Nunca use `pagamentoId`, `transacaoExternaId`, código PIX ou e-mail como tag de métrica.

## Diagnóstico

1. Confirme saúde do Billing em `/api/v1/status/ready`.
2. Verifique erros agregados do webhook por código HTTP, sem inspecionar ou copiar assinatura e payload em evidências.
3. Confirme conectividade do Billing com `https://api.mercadopago.com` e a presença das duas chaves no secret Kubernetes, exibindo somente seus nomes.
4. Para pagamento pendente, use a ação autenticada **Atualizar situação** na UI; ela consulta `GET /v1/payments/{id}` no provedor.
5. Se o provedor estiver indisponível, preserve o estado `CRIADO`, não confirme manualmente e aguarde recuperação.

Webhooks duplicados, atrasados ou concorrentes são esperados. A transição condicional do Billing deve produzir no máximo um evento financeiro terminal.

## Rotação e recuperação

Ao rotacionar o webhook secret, atualize primeiro a aplicação do Mercado Pago e imediatamente o secret do deploy, então faça rollout do Billing. Confirme que o novo pod está pronto e envie uma notificação de teste. Em caso de divergência, restaure temporariamente o valor anterior no secret Kubernetes e repita o rollout; não desabilite a validação de assinatura.

Após recuperação, reconcilie pagamentos ainda `CRIADO` pela UI. Não reprocesse manualmente `pagamentoConfirmado` e não altere o banco para antecipar a entrega da OS.
