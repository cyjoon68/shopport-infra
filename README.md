# Shopport infrastructure

서울 리전의 dev, staging, prod 계정을 동일한 Terraform module로 구성한다. 각 계정은 독립 state, KMS, VPC, EKS, Aurora PostgreSQL, OpenSearch, SQS, S3, Lambda, CloudFront, WAF를 가진다.

상위 저장소의 로컬 Compose 포트는 이 저장소 루트의 `.env`에서 관리한다. `.env.example`을 `.env`로 복사한 뒤 상위 저장소에서 `make dev-core`를 실행한다.

## 배포 순서

```bash
cd bootstrap
terraform init
terraform apply -var='environment=dev' -var='state_bucket_name=shopport-dev-tfstate-ACCOUNT_ID'

cd ../stacks/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
```

`backend.hcl`, `terraform.tfvars`, state, credential은 커밋하지 않는다. S3 backend는 DynamoDB 없이 native `use_lockfile = true`를 사용한다.

## Kubernetes

`helm/shopport` chart는 API, worker, migration PreSync Job, HPA, PDB, topology spread, read-only/non-root security context, KEDA SQS scaling을 포함한다. `argocd/applications`는 환경 overlay를 추적한다. image tag는 tag가 아니라 ECR digest만 허용한다. worker는 DB outbox dispatcher를 유지하기 위해 모든 환경에서 최소 1개 replica를 실행한다.

런타임 계약과 적용 전 수동 절차는 [`docs/runtime-contracts.md`](docs/runtime-contracts.md)에 정리되어 있다.

## 검사

```bash
terraform fmt -check -recursive
for stack in dev staging prod; do terraform -chdir="stacks/$stack" init -backend=false; terraform -chdir="stacks/$stack" validate; tflint --chdir="stacks/$stack" --recursive; done
checkov --directory . --config-file .checkov.yaml
for environment in dev staging prod; do helm lint helm/shopport --values "helm/shopport/values-$environment.yaml" --set image.api.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --set image.worker.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; helm template shopport helm/shopport --namespace shopport --values "helm/shopport/values-$environment.yaml" --set image.api.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --set image.worker.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb > "rendered-$environment.yaml"; kubeconform -strict -summary -ignore-missing-schemas "rendered-$environment.yaml"; done
ruby -e 'require "yaml"; Dir["{.github,argocd,helm/shopport}/**/*.{yaml,yml}"].reject { |file| file.include?("/templates/") }.each { |file| YAML.load_stream(File.read(file)) }'
jq empty observability/datadog/*.json
```

GitHub Actions는 OIDC만 사용한다. `production` Environment reviewer가 승인한 뒤 prod overlay 변경을 허용한다. 실제 계정 ID, hosted zone, ACM ARN, Secrets Manager 값, Datadog key, Sentry auth token은 외부 입력이다.
