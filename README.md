# Shopport infrastructure

서울 리전의 dev, staging, prod 계정을 동일한 Terraform module로 구성한다. 각 계정은 독립 state, KMS, VPC, EKS, Aurora PostgreSQL, Redis, OpenSearch, SQS, S3, Lambda, CloudFront, WAF를 가진다.

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

`helm/shopport` chart는 API, worker, migration PreSync Job, HPA, PDB, topology spread, read-only/non-root security context, KEDA SQS scaling을 포함한다. `argocd/applications`는 환경 overlay를 추적한다. image tag는 tag가 아니라 ECR digest만 허용한다.

## 검사

```bash
terraform fmt -check -recursive
for stack in stacks/dev stacks/staging stacks/prod; do terraform -chdir="$stack" init -backend=false; terraform -chdir="$stack" validate; done
helm lint helm/shopport
helm template shopport helm/shopport --set image.api.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --set image.worker.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
```

GitHub Actions는 OIDC만 사용한다. `production` Environment reviewer가 승인한 뒤 prod overlay 변경을 허용한다. 실제 계정 ID, hosted zone, ACM ARN, Secrets Manager 값, Datadog key, Sentry auth token은 외부 입력이다.
