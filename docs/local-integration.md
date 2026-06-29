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

## Rodar microsserviços fora do Compose

Também é possível manter apenas as dependências no Compose e executar cada serviço via Maven:

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

Nos logs, o script mostra o nome lógico do contrato e o nome físico local. Como SNS/SQS aceitam apenas um subconjunto de caracteres no nome do recurso, o ambiente local troca `.` por `-` ao criar tópicos e filas. A materialização definitiva em AWS/Terraform deve continuar sendo tratada nos módulos de infraestrutura da Fase 4.

## Limitações atuais

O ambiente já prepara dependências para integração, mas o fluxo distribuído completo ainda depende da implementação dos publishers, consumers, Outbox e Saga nos microsserviços.

Até essa implementação estar completa, use o ambiente para:

- validar inicialização dos serviços;
- testar APIs isoladas;
- validar migrations e seeds locais;
- preparar os recursos de mensageria que serão usados pelos próximos incrementos.

## Encerrar ambiente

```bash
docker compose -f compose.local.yml down
```

Para apagar volumes locais:

```bash
docker compose -f compose.local.yml down -v
```
