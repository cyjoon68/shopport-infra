# Checkov security exceptions

이 목록은 CI에서 숨기는 임의 예외가 아니라 v1 설계 결정과 scanner 한계의 기록이다. 분기별로 재검토한다.

| Check | 범위 | 통제와 종료 조건 |
|---|---|---|
| `CKV_AWS_18` | S3 access logging | raw, normalized, archive와 CloudFront는 중앙 access-log bucket에 기록한다. state와 log bucket의 재귀 logging만 제외한다. |
| `CKV_AWS_68`, `CKV2_AWS_47` | asset CloudFront WAF | signed GET/HEAD 전용 private OAC origin이다. API ALB에는 WAF managed rules와 rate limit을 적용한다. asset edge 위협 모델 변경 시 CloudFront-scope WAF를 추가한다. |
| `CKV_AWS_70`, `CKV2_AWS_6`, `CKV_AWS_21`, `CKV_AWS_145` | `for_each` S3 scanner relation | 모든 application bucket에 deny-insecure policy, public access block, versioning, KMS encryption이 Terraform으로 연결되어 있다. Checkov가 dynamic key 관계를 결합하지 못한다. |
| `CKV_AWS_144` | cross-region replication | v1은 서울 단일 리전으로 고정됐다. cross-region DR 단계에서 제거한다. |
| `CKV_AWS_174`, `CKV2_AWS_42` | CloudFront certificate conditional | dev의 AWS default domain만 예외다. prod lifecycle precondition은 custom domain, us-east-1 ACM certificate, signing public key를 강제한다. |
| `CKV_AWS_272` | Lambda code signing | Lambda container image에는 Lambda code-signing config를 적용할 수 없다. CI에서 SBOM, Trivy, immutable ECR digest와 promotion을 검증한다. |
| `CKV_AWS_288`, `CKV_AWS_290`, `CKV_AWS_355` | Karpenter/ALB controller IAM | AWS resource ID가 runtime에 생성되는 controller 동작이다. role은 전용 Pod Identity이고 workload role과 분리된다. AWS 공식 policy 변경 시 동기화한다. |
| `CKV_AWS_305`, `CKV_AWS_310` | asset CDN root/failover | HTML root object가 없는 signed asset CDN이고 v1 다중 리전은 제외됐다. multi-region 단계에서 origin group을 추가한다. |
| `CKV_AWS_338` | log retention | application audit/flow/search logs는 30일, Datadog 장기 지표는 SLO 기간에 맞춰 유지한다. 개인정보 최소 수집 원칙상 1년 원문 로그를 금지한다. |
| `CKV_AWS_339` | EKS version catalog | Terraform은 EKS `1.34`로 고정했다. 사용한 Checkov catalog가 해당 지원 버전을 아직 인식하지 못한다. AWS 지원 종료 전에 갱신한다. |
| `CKV2_AWS_31` | WAF request logging | WAF log redaction API는 body를 완전히 제거하지 못한다. prompt 비수집 요구가 우선이므로 sampled request와 request log를 끄고 CloudWatch metrics만 사용한다. |
| `CKV2_AWS_38`, `CKV2_AWS_39` | delegated Route 53 zones | domain/registrar와 prod root zone이 외부 입력이다. 실제 domain 제공 시 DNSSEC DS 등록과 query-log destination을 출시 게이트에서 검증한다. |
| `CKV2_AWS_57` | Secrets Manager rotation | DB, signing/provider credential의 service별 rotation 절차와 maintenance window가 필요하다. credentials 제공 시 90일 rotation runbook을 실행하고 자동화한다. |
| `CKV2_AWS_62` | S3 event notifications | raw bucket만 Lambda event source다. normalized/archive/state/log bucket은 event-driven processing 대상이 아니다. |
| `CKV2_AWS_61` | dynamic S3 lifecycle relation | raw는 24시간 삭제, normalized/archive는 multipart abort와 noncurrent transition, state는 history transition을 가진다. Checkov가 filtered `for_each` 연결을 결합하지 못한다. |
| `CKV2_AWS_65` | log delivery ACL | CloudFront와 S3 standard access log 전송용 bucket만 `BucketOwnerPreferred`와 `log-delivery-write` ACL이 필요하다. public ACL은 별도 public-access block으로 차단한다. |
| `CKV_K8S_43` | rendered image tag scanner | Helm helper가 `sha256:<64 hex>`가 아니면 render를 실패시킨다. scanner는 template helper를 tag로 오인한다. |
