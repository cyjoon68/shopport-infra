# Shopport Infrastructure

Shopport의 로컬 실행 환경과 AWS 배포 구성을 관리합니다. Terraform, Helm, Argo CD, 관측 설정이 같은 runtime contract를 따르도록 구성합니다.

## 역할

서울 리전의 dev, staging, prod 계정은 같은 Terraform module을 사용합니다. 각 환경은 독립 state, KMS, VPC, EKS, Aurora PostgreSQL, OpenSearch, SQS, S3, Lambda, CloudFront, WAF를 가집니다.

## 로컬 개발 환경

이 저장소의 .env는 상위 통합 저장소 Compose 포트를 관리합니다.

~~~bash
cp .env.example .env
~~~

그다음 [통합 워크스페이스](https://github.com/cyjoon68/shopport-app)에서 필요한 범위를 실행합니다.

~~~bash
make dev-core
make dev
~~~

make dev-core는 기본 서비스와 API·worker를, make dev는 OpenSearch를 포함한 full profile을 실행합니다.

## 클라우드 환경

bootstrap은 환경별 Terraform state backend를 준비하고, stacks/dev, stacks/staging, stacks/prod는 platform module을 적용합니다. helm/shopport는 API, KEDA worker, outbox dispatcher, migration PreSync Job, HPA, PDB, topology spread, read-only/non-root security context를 포함합니다. argocd/applications는 환경별 overlay를 추적합니다.

## 배포 흐름

~~~bash
cd bootstrap
terraform init
terraform apply -var='environment=dev' -var='state_bucket_name=shopport-dev-tfstate-ACCOUNT_ID'

cd ../stacks/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
~~~

배포 이미지는 tag가 아닌 ECR digest만 사용합니다. production Environment reviewer가 승인한 뒤에만 prod overlay 변경을 허용합니다.

## 보안과 상태 관리

backend.hcl, terraform.tfvars, state, credential은 커밋하지 않습니다. S3 backend는 DynamoDB 없이 native use_lockfile = true를 사용합니다. GitHub Actions는 AWS OIDC만 사용하며 static AWS key를 저장하지 않습니다.

실제 account ID, hosted zone, ACM ARN, Secrets Manager 값, Datadog key, Sentry auth token은 외부 입력입니다. 런타임 계약과 적용 전 수동 절차는 [runtime contracts](docs/runtime-contracts.md)에 정리되어 있습니다.

## 검사

~~~bash
terraform fmt -check -recursive
for stack in dev staging prod; do terraform -chdir="stacks/$stack" init -backend=false; terraform -chdir="stacks/$stack" validate; tflint --chdir="stacks/$stack" --recursive; done
checkov --directory . --config-file .checkov.yaml
for environment in dev staging prod; do helm lint helm/shopport --values "helm/shopport/values-$environment.yaml" --set image.api.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --set image.worker.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; helm template shopport helm/shopport --namespace shopport --values "helm/shopport/values-$environment.yaml" --set image.api.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --set image.worker.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb > "rendered-$environment.yaml"; kubeconform -strict -summary -ignore-missing-schemas "rendered-$environment.yaml"; done
ruby -e 'require "yaml"; Dir["{.github,argocd,helm/shopport}/**/*.{yaml,yml}"].reject { |file| file.include?("/templates/") }.each { |file| YAML.load_stream(File.read(file)) }'
jq empty observability/datadog/*.json
~~~

## 관련 문서

- [통합 워크스페이스](https://github.com/cyjoon68/shopport-app)
- [Runtime contracts](docs/runtime-contracts.md)
- [Security exceptions](docs/security-exceptions.md)
