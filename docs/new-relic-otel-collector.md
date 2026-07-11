# New Relic OpenTelemetry Collector no EKS lab

O backend canônico de observabilidade da Fase 4 é o New Relic. No cluster `eks-lab`, a coleta deve ser feita pelo New Relic OpenTelemetry Collector instalado via Helm, com logs de pods, métricas Kubernetes/Prometheus e traces via OTLP/gRPC.

O collector roda dentro do cluster, mas a conta New Relic e a license key continuam externas. A chave não deve ser versionada neste repositório; ela deve ser informada por secret do GitHub ou variável local no momento do deploy.

## Artefatos

- [../k8s/components/new-relic-otel-collector/values.lab.yaml](../k8s/components/new-relic-otel-collector/values.lab.yaml) define os valores Helm do ambiente `lab`.
- [../scripts/manual/install-new-relic-otel-collector.sh](../scripts/manual/install-new-relic-otel-collector.sh) instala ou atualiza o release Helm `nr-k8s-otel-collector`.
- [../scripts/actions/ci-deploy.sh](../scripts/actions/ci-deploy.sh) instala o collector automaticamente no modo `INSTALL_NEW_RELIC_OTEL_COLLECTOR=auto` quando `NEW_RELIC_LICENSE_KEY` está disponível.

## Variáveis

| Nome | Obrigatória | Padrão | Uso |
|---|---|---|---|
| `NEW_RELIC_LICENSE_KEY` | Sim, quando `UPSERT_NEW_RELIC_SECRET=true` | vazio | License key criada no New Relic e gravada no Secret Kubernetes `new-relic-license-key`. |
| `NEW_RELIC_NAMESPACE` | Não | `newrelic` | Namespace Kubernetes do collector. |
| `NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE` | Não | `nr-k8s-otel-collector` | Nome do release Helm. |
| `NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME` | Não | `nr-k8s-otel-collector-gateway` | Nome do Service interno usado pelos microsserviços para OTLP/gRPC. |
| `NEW_RELIC_LICENSE_KEY_SECRET_NAME` | Não | `new-relic-license-key` | Nome do Secret Kubernetes com a license key. |
| `NEW_RELIC_LICENSE_KEY_SECRET_KEY` | Não | `licenseKey` | Chave dentro do Secret Kubernetes. |
| `NEW_RELIC_CLUSTER_NAME` | Não | valor de `EKS_CLUSTER_NAME` | Nome do cluster reportado ao New Relic. |
| `NEW_RELIC_REGION` | Não | `US` | Região da conta New Relic usada pelo chart. Valores aceitos pelo chart: `US`, `EU`, `JP`, `GOV`, `STG` ou `DEV`. |
| `NEW_RELIC_OTLP_ENDPOINT` | Não | `https://otlp.nr-data.net` | Endpoint OTLP externo do New Relic. Alterar quando a conta usar outra região. |
| `INSTALL_NEW_RELIC_OTEL_COLLECTOR` | Não | `auto` | Controla a instalação no deploy automatizado. `auto` instala quando `NEW_RELIC_LICENSE_KEY` está presente, `true` força a instalação e `false` desabilita. |
| `UPSERT_NEW_RELIC_SECRET` | Não | `true` | Cria ou atualiza o Secret Kubernetes a partir de `NEW_RELIC_LICENSE_KEY`. |
| `SKIP_KUBECONFIG_UPDATE` | Não | `false` | Evita atualizar o kubeconfig quando o deploy já fez isso. |

## Instalação local

```bash
export NEW_RELIC_LICENSE_KEY=<license-key>
scripts/manual/install-new-relic-otel-collector.sh
```

Para reutilizar um Secret Kubernetes já existente:

```bash
UPSERT_NEW_RELIC_SECRET=false scripts/manual/install-new-relic-otel-collector.sh
```

## Deploy automatizado

No repositório ou na organização GitHub, configure:

- secret `NEW_RELIC_LICENSE_KEY`;
- variável `NEW_RELIC_REGION`, se a conta não for da região padrão `US`;
- variável `NEW_RELIC_OTLP_ENDPOINT`, se a conta não usar o endpoint padrão `https://otlp.nr-data.net`.

O workflow de deploy usa `INSTALL_NEW_RELIC_OTEL_COLLECTOR=auto` por padrão. Com a secret `NEW_RELIC_LICENSE_KEY` configurada, ele executa o Terraform, aplica o overlay Kubernetes compartilhado e instala ou atualiza o collector via Helm. Para desabilitar explicitamente a etapa, configure `INSTALL_NEW_RELIC_OTEL_COLLECTOR=false`; para exigir a instalação mesmo reutilizando um Secret Kubernetes existente, configure `INSTALL_NEW_RELIC_OTEL_COLLECTOR=true` e `UPSERT_NEW_RELIC_SECRET=false`.

## Endpoint OTLP interno

Com os valores padrão, os microsserviços devem usar:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://nr-k8s-otel-collector-gateway.newrelic.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

O Service interno `nr-k8s-otel-collector-gateway` expõe OTLP/gRPC em `4317` e OTLP/HTTP em `4318`.

## Pré-requisito dos nodes EKS

O DaemonSet do chart usa o processor `resourcedetection/cloudproviders` para identificar o cluster como `aws_eks`. Em nodes EC2, esse processor precisa acessar IMDS a partir do pod; por isso, os nodes do `eks-lab` devem manter `HttpPutResponseHopLimit=2` ou usar uma configuração equivalente de identidade suportada pelo chart.

O módulo [terraform/modules/eks/main.tf](../terraform/modules/eks/main.tf) versiona esse requisito por launch template do managed node group. Para nodes já criados antes dessa configuração, aplique o ajuste pontual na instância EC2 antes de recriar o pod do DaemonSet:

```bash
aws ec2 modify-instance-metadata-options \
  --region us-east-1 \
  --instance-id <instance-id> \
  --http-put-response-hop-limit 2
```

## Coleta esperada

- Logs: coletados dos pods pelo receiver `filelog`.
- Métricas Prometheus e Kubernetes: coletadas pelos receivers `prometheus`, `hostmetrics`, `kubeletstats`, `k8s_events` e `kube-state-metrics`.
- Métricas Prometheus dos microsserviços: o Deployment do collector adiciona o receiver `prometheus/oficina-microservices`, que descobre pods `oficina-os-service`, `oficina-billing-service` e `oficina-execution-service` no namespace `default` e raspa `/q/metrics` na porta `http`.
- Traces: recebidos por OTLP/gRPC no Service interno `nr-k8s-otel-collector-gateway` e enviados pela pipeline `traces/oficina-microservices`.
- Logs de eventos/Outbox: os microsserviços emitem `eventType` no JSON do stdout. Como `eventType` é reservado na ingestão do New Relic, as imagens dos microsserviços também devem emitir os aliases `domainEventType` e `event.type`, mantendo o campo original no log do pod e fornecendo atributos consultáveis por NRQL.

Depois da instalação no `eks-lab`, valide:

```bash
kubectl -n newrelic get pods
kubectl -n newrelic get svc nr-k8s-otel-collector-gateway
kubectl -n newrelic logs -l app.kubernetes.io/name=nr-k8s-otel-collector --tail=100
kubectl -n newrelic logs deploy/nr-k8s-otel-collector-deployment --tail=100 | grep oficina-microservices
```

No New Relic, o chart envia os dados para `Metric`, `OtlpInfrastructureEvent` e `Log`. Consultas mínimas esperadas após alguns ciclos de scrape:

```nrql
FROM Metric SELECT keyset() WHERE k8s.cluster.name = 'eks-lab' SINCE 30 minutes ago
```

```nrql
FROM Metric SELECT keyset() WHERE service.namespace = 'oficina' SINCE 30 minutes ago
```

```nrql
FROM Span SELECT count(*) WHERE service.namespace = 'oficina' SINCE 30 minutes ago FACET service.name
```

```nrql
FROM Log SELECT count(*) WHERE service.namespace = 'oficina' AND domainEventType IS NOT NULL SINCE 30 minutes ago FACET service.name, domainEventType
```

As evidências finais de logs, métricas, traces, dashboards e alertas devem ser registradas no [checklist final da Fase 4](../../oficina-platform/docs/phase-4-delivery-checklist.md).
