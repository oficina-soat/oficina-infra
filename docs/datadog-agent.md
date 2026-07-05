# Datadog Agent no EKS lab

O backend canônico de observabilidade da Fase 4 é o Datadog. No cluster `eks-lab`, a coleta deve ser feita pelo Datadog Agent instalado via Helm, com logs de pods, métricas Kubernetes/Prometheus e traces via OTLP/gRPC.

O Agent roda dentro do cluster, mas a conta Datadog e a API key continuam externas. A chave não deve ser versionada neste repositório; ela deve ser informada por secret do GitHub ou variável local no momento do deploy.

## Artefatos

- [../k8s/components/datadog-agent/values.lab.yaml](../k8s/components/datadog-agent/values.lab.yaml) define os valores Helm do ambiente `lab`.
- [../scripts/manual/install-datadog-agent.sh](../scripts/manual/install-datadog-agent.sh) instala ou atualiza o release Helm `datadog-agent`.
- [../scripts/actions/ci-deploy.sh](../scripts/actions/ci-deploy.sh) pode instalar o Agent automaticamente quando `INSTALL_DATADOG_AGENT=true`.

## Variáveis

| Nome | Obrigatória | Padrão | Uso |
|---|---|---|---|
| `DATADOG_API_KEY` | Sim, quando `UPSERT_DATADOG_SECRET=true` | vazio | Chave de API criada no Datadog e gravada no Secret Kubernetes `datadog-secret`. |
| `DATADOG_SITE` | Não | `datadoghq.com` | Site Datadog, por exemplo `datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com` ou outro valor da conta. |
| `DATADOG_NAMESPACE` | Não | `datadog` | Namespace Kubernetes do Agent. |
| `DATADOG_HELM_RELEASE` | Não | `datadog-agent` | Nome do release Helm. |
| `DATADOG_API_KEY_SECRET_NAME` | Não | `datadog-secret` | Nome do Secret Kubernetes com a chave `api-key`, esperada pelo chart. |
| `DATADOG_API_KEY_SECRET_KEY` | Não | `api-key` | Chave dentro do Secret Kubernetes. Deve permanecer `api-key` para compatibilidade com o chart. |
| `DATADOG_LOCAL_SERVICE_NAME` | Não | `datadog-agent` | Nome do Service interno usado pelos microsserviços para OTLP/gRPC. |
| `INSTALL_DATADOG_AGENT` | Não | `false` | Habilita a instalação no deploy automatizado. |
| `UPSERT_DATADOG_SECRET` | Não | `true` | Cria ou atualiza o Secret Kubernetes a partir de `DATADOG_API_KEY`. |
| `SKIP_KUBECONFIG_UPDATE` | Não | `false` | Evita atualizar o kubeconfig quando o deploy já fez isso. |

## Instalação local

```bash
export DATADOG_API_KEY=<api-key>
export DATADOG_SITE=datadoghq.com
scripts/manual/install-datadog-agent.sh
```

Para reutilizar um Secret Kubernetes já existente:

```bash
UPSERT_DATADOG_SECRET=false scripts/manual/install-datadog-agent.sh
```

## Deploy automatizado

No GitHub Environment `lab`, configure:

- secret `DATADOG_API_KEY`;
- variável `INSTALL_DATADOG_AGENT=true`;
- variável `DATADOG_SITE`, se a conta não usar o site padrão `datadoghq.com`.

O workflow de deploy executa o Terraform, aplica o overlay Kubernetes compartilhado e, quando habilitado, instala ou atualiza o Agent via Helm.

## Endpoint OTLP interno

Com os valores padrão, os microsserviços devem usar:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://datadog-agent.datadog.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

O Service interno usa `internalTrafficPolicy: Local` quando suportado pelo cluster, mantendo o envio para o Agent no mesmo node. O endpoint HTTP OTLP fica desabilitado por padrão.

## Coleta esperada

- Logs: `datadog.logs.enabled=true` e `containerCollectAll=true`, coletando logs dos pods.
- Métricas Prometheus: `datadog.prometheusScrape.enabled=true` e `serviceEndpoints=true`; os Services dos microsserviços devem expor `/q/metrics` com anotações compatíveis quando forem materializados.
- Traces: `datadog.otlp.receiver.protocols.grpc.enabled=true` em `0.0.0.0:4317`, acessível pelo Service interno.

Depois da instalação no `eks-lab`, valide:

```bash
kubectl -n datadog get pods
kubectl -n datadog get svc datadog-agent
kubectl -n datadog logs -l app=datadog-agent --tail=100
```

As evidências finais de logs, métricas, traces, dashboards e monitores devem ser registradas no [checklist final da Fase 4](../../oficina-platform/docs/phase-4-delivery-checklist.md).
