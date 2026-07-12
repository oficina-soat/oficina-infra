# Ambiente local integrado

Este ambiente facilita testes locais dos três microsserviços da suíte sem substituir o deploy canônico em AWS/EKS.

Ele complementa os contratos definidos no `oficina-platform` e materializa localmente:

- PostgreSQL com databases `oficina_os` e `oficina_billing`;
- DynamoDB Local com as tabelas do `oficina-execution-service`;
- LocalStack com SNS/SQS para os tópicos, filas e DLQs da mensageria;
- profile opcional para subir `oficina-os-service`, `oficina-billing-service` e `oficina-execution-service`.

## Pré-requisitos

- Docker com Docker Compose.

O bootstrap usa um container `amazon/aws-cli` definido no Compose. As credenciais usadas são locais e não acessam AWS real:

```bash
export AWS_ACCESS_KEY_ID=local
export AWS_SECRET_ACCESS_KEY=local
export AWS_REGION=us-east-1
```

## Subir dependências

```bash
docker compose -f compose.local.yml up -d postgres dynamodb localstack
scripts/local/bootstrap-local.sh
```

O PostgreSQL inicializa automaticamente os databases e usuários:

| Database | Usuário | Senha |
|---|---|---|
| `oficina_os` | `oficina_os_user` | `oficina_os_password` |
| `oficina_billing` | `oficina_billing_user` | `oficina_billing_password` |

## Rodar microsserviços pelo Compose

O profile `services` constrói e sobe os três microsserviços em portas distintas:

```bash
docker compose -f compose.local.yml --profile services up -d --build
```

Os containers usam explicitamente o profile Quarkus `dev` e `DEPLOYMENT_ENVIRONMENT=local`. Esse par identifica uma execução local deliberada, permite endpoints locais e evita confundir telemetria com o ambiente `lab`. PostgreSQL e DynamoDB continuam obrigatórios; não há fallback automático para stores em memória. A mensageria fica habilitada contra o LocalStack preparado pelo bootstrap.

Endpoints principais:

| Serviço | URL |
|---|---|
| `oficina-os-service` | `http://localhost:8081/api/v1/status` |
| `oficina-billing-service` | `http://localhost:8082/api/v1/status` |
| `oficina-execution-service` | `http://localhost:8083/api/v1/status` |

Swagger UI:

```text
http://localhost:8081/q/swagger-ui
http://localhost:8082/q/swagger-ui
http://localhost:8083/q/swagger-ui
```

## Chamadas mutáveis

Operações `POST` e `PATCH` exigem o header `X-Idempotency-Key`, conforme o contrato de idempotência da plataforma. Use um valor único por tentativa lógica da operação.

Na Swagger UI, abra a operação mutável, clique em `Try it out` e preencha o campo `X-Idempotency-Key` que aparece na seção de parâmetros. Qualquer valor único com pelo menos 8 caracteres serve para teste local, por exemplo `cliente-local-001`.

Exemplo para criar cliente no `oficina-os-service`:

```bash
curl -i -X POST http://localhost:8081/api/v1/clientes \
  -H 'Content-Type: application/json' \
  -H "X-Idempotency-Key: cliente-$(date +%s)" \
  -d '{
    "nome": "Cliente Local",
    "documento": "12345678909",
    "telefone": "+5511999999999",
    "email": "cliente.local@oficina.com"
  }'
```

Se esse campo não aparecer no Swagger UI, reconstrua os containers dos microsserviços:

```bash
docker compose -f compose.local.yml --profile services up -d --build
```

## Rodar microsserviços fora do Compose

Também é possível manter apenas as dependências no Compose e executar cada serviço via Maven:

```bash
export OFICINA_MESSAGING_ENABLED=true
export OFICINA_MESSAGING_ENDPOINT_OVERRIDE=http://localhost:4566
export AWS_ACCOUNT_ID=000000000000
```

```bash
cd ../oficina-os-service
./mvnw quarkus:dev -Ppostgresql -Dquarkus.http.port=8081

cd ../oficina-billing-service
./mvnw quarkus:dev -Ppostgresql -Dquarkus.http.port=8082

cd ../oficina-execution-service
./mvnw quarkus:dev -Pdynamodb -Dquarkus.http.port=8083
```

Para o `oficina-execution-service`, use:

```bash
export DYNAMODB_ENDPOINT_OVERRIDE=http://localhost:8000
export OFICINA_DYNAMODB_TABLE_PREFIX=oficina-execution-lab
```

## Mensageria local

O bootstrap cria tópicos, filas de consumidores e DLQs conforme o contrato de mensageria da plataforma.

Nos logs, o script mostra o nome lógico do contrato e o nome físico local. Como SNS/SQS aceitam apenas um subconjunto de caracteres no nome do recurso, o ambiente local troca `.` por `-` ao criar tópicos e filas. As assinaturas usam `RawMessageDelivery=true`, mantendo no SQS o envelope de domínio publicado pelo produtor, sem envelope adicional do SNS. A materialização definitiva em AWS/Terraform fica nos módulos de infraestrutura da Fase 4.

## Proteção contra configuração inválida

Nos profiles `prod` e `lab`, ou quando `DEPLOYMENT_ENVIRONMENT=lab`, cada microsserviço valida banco, tabelas DynamoDB, tópicos SNS, filas SQS e configuração de autenticação antes de concluir a inicialização. Endpoints locais e stores em memória são rejeitados nesses runtimes.

O Compose usa o profile `dev` para permitir deliberadamente PostgreSQL, DynamoDB Local e LocalStack. Não remova `QUARKUS_PROFILE=dev` nem reutilize essa configuração no ambiente compartilhado.

## Encerrar ambiente

```bash
docker compose -f compose.local.yml down
```

Para apagar volumes locais:

```bash
docker compose -f compose.local.yml down -v
```
