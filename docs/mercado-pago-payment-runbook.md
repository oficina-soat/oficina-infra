# Runbook da integração Mercado Pago

## Escopo

Este runbook cobre a criação e reconciliação de orders PIX pelo `oficina-billing-service`, além da compatibilidade temporária com payments legados. O API Gateway expõe o webhook do Mercado Pago sem JWT porque a chamada parte do provedor; o Billing exige e valida `x-signature`, o `x-request-id` original, `data.id` e a janela temporal antes de consultar a API do Mercado Pago. Nenhuma action ou status recebido no corpo do webhook é aceito como evidência financeira.

## Configuração

Configure no executor do deploy, sem persistir os valores no Git:

- `OFICINA_MERCADO_PAGO_ENABLED=true`;
- `OFICINA_MERCADO_PAGO_ACCESS_TOKEN` com o token do ambiente correspondente;
- `OFICINA_MERCADO_PAGO_WEBHOOK_SECRET` com o secret da aplicação no Mercado Pago, distinto do token;
- `OFICINA_MERCADO_PAGO_API_MODE=orders`;
- no `lab`, `OFICINA_MERCADO_PAGO_PAYER_EMAIL=test_user_br@testuser.com` e `OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME=APRO` para o cenário de aprovação automática;
- opcionalmente `OFICINA_MERCADO_PAGO_API_URL` quando o endpoint oficial precisar ser sobrescrito.

O script [apply-microservices.sh](../scripts/manual/apply-microservices.sh) materializa esses valores no secret Kubernetes `oficina-billing-service-mercado-pago-env`. O valor do secret, a assinatura, o código PIX, o QR Code e o token não devem aparecer em logs, métricas, traces ou evidências.

O API Gateway deve preservar o `x-request-id` enviado pelo Mercado Pago nessa rota. Esse valor participa do manifesto HMAC junto com `data.id` e `ts`; substituí-lo pelo identificador interno do API Gateway invalida toda notificação legítima. A correlação interna continua em `X-Correlation-Id` e nos campos sanitizados de observabilidade.

No painel do Mercado Pago, configure o evento **Order (Mercado Pago)** para:

```text
https://<api-gateway>/api/v1/integracoes/mercado-pago/webhooks
```

Durante a janela de compatibilidade, mantenha também o evento **Pagamentos** para cobranças `PAYMENT` ainda pendentes. Use credenciais e aplicação de teste no `lab`; produção deve usar aplicação, token e secret próprios e nunca deve receber `APRO`.

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
4. Para pagamento pendente, use a ação autenticada **Atualizar situação** na UI; ela consulta `GET /v1/orders/{id}` para `ORDER` e `GET /v1/payments/{id}` para referência legada `PAYMENT`.
5. Se o provedor estiver indisponível, preserve o estado `CRIADO`, não confirme manualmente e aguarde recuperação.

Webhooks duplicados, atrasados ou concorrentes são esperados. A transição condicional do Billing deve produzir no máximo um evento financeiro terminal.

## Rotação e recuperação

Ao rotacionar o webhook secret, atualize primeiro a aplicação do Mercado Pago e imediatamente o secret do deploy, então faça rollout do Billing. Confirme que o novo pod está pronto e envie uma notificação de teste. Em caso de divergência, restaure temporariamente o valor anterior no secret Kubernetes e repita o rollout; não desabilite a validação de assinatura.

Após recuperação, reconcilie pagamentos ainda `CRIADO` pela UI. Não reprocesse manualmente `pagamentoConfirmado` e não altere o banco para antecipar a entrega da OS.

## Rollout e rollback

Antes do rollout, publique a imagem do Billing `1.9.0`, confirme que a migration V9 classificará referências Mercado Pago existentes como `PAYMENT` e configure **Order (Mercado Pago)** no painel. Depois do rollout, novas cobranças devem persistir `ORDER`; acompanhe falhas, latência e pagamentos presos em `CRIADO` sem registrar IDs ou conteúdo PIX em métricas.

Se a criação em Orders falhar antes de gerar uma cobrança, altere temporariamente `OFICINA_MERCADO_PAGO_API_MODE=payments` e faça novo rollout. Não reverta o Billing para `1.8.0`: essa versão não conhece referências `ORDER` e deixaria orders já criadas sem reconciliação. Mesmo em modo de criação `payments`, o Billing `1.9.0` continua consultando cada cobrança pelo tipo persistido.

A remoção de Payments só pode ocorrer após inventário sem referências `PAYMENT` pendentes e confirmação de que notificações `type=payment` não são mais necessárias.
