# Runtime contracts and migration

## Application runtime

The runtime Secrets Manager payload exposes `RAW_ASSET_BUCKET`, `NORMALIZED_ASSET_BUCKET`, `ARCHIVE_BUCKET`, `SQS_ASSET_RESULT_URL`, and `OPENSEARCH_URL`. `ASSET_BUCKET` remains an alias of `RAW_ASSET_BUCKET` for the expand/contract migration and must be removed only after every application deployment reads `RAW_ASSET_BUCKET`.

The image processor is invoked only by `ObjectCreated` events from the raw asset bucket. It receives `SQS_ASSET_RESULT_URL` and `NORMALIZED_ASSET_BUCKET`. `lambda_image_uri` accepts only `shopport/image-processor` ECR image URIs pinned by a `sha256` digest.

## Credentials bootstrap

Terraform creates the `shopport-ENV/credentials` secret container. Every environment requires an operator-supplied `AWSCURRENT` JSON payload through the approved secret-management process before deployment.

Supply credentials before the first Argo sync. Every environment requires `PROVIDER_API_KEY` in the credentials secret. The non-secret `PROVIDER_MODEL` is pinned to `gpt-5.4-mini` by Helm. Do not put credential values in Terraform variables, Helm values, CI logs, or this repository.

## Queue migration

The former `shopport-ENV-image` queue is replaced by `shopport-ENV-asset-result`. Before applying, pause image ingestion and drain or redrive messages from the old queue. Apply Terraform, confirm the runtime secret contains the new queue URL, then sync the worker deployment and resume ingestion. The legacy Terraform output names remain temporarily as aliases, while new consumers should use `asset_result_queue_url` and `asset_result_queue_arn`.

The Aurora outbox has a dedicated static dispatcher: one replica in dev/staging and two in prod. It alone uses PostgreSQL `LISTEN` for commit-time wakeups, claims rows with `FOR UPDATE SKIP LOCKED`, and falls back to timed polling. Do not put `LISTEN` in the KEDA-scaled worker: PostgreSQL `LISTEN` pins an RDS Proxy client session and a queue-scale-out would create a notification herd. The regular worker continues asset consumption, archival, and retention work. The SQS outbox queue remains a future relay placeholder and is not a KEDA activation source or an application secret.

## PostgreSQL runtime rollout

Runtime workloads use the `shopport_app` database role. The migration Job alone receives the admin connection URL and `DATABASE_APP_PASSWORD`; it creates or rotates the runtime role and grants only application DML privileges. Keep the admin Proxy secret attached during bootstrap, then let the PreSync Job create `shopport_app` before any runtime workload connects with its matching Proxy secret.

`pg_stat_statements` requires `shared_preload_libraries`, which Aurora applies only after a restart. Before syncing an image that contains the migration, apply the parameter-group change, perform the approved Aurora reboot/failover, and verify both `SHOW shared_preload_libraries` and `SELECT count(*) FROM pg_stat_statements`. Only then allow the PreSync migration Job to run.

## Follow-ups outside this repository

The workload role remains shared by API, worker, and migration because splitting it requires coordinated application and deployment changes. A follow-up should create dedicated service accounts and roles, then reduce S3, SQS, OpenSearch, and Secrets Manager permissions per component.

The backend image-publish workflow is owned by `cyjoon68/shopport-be` and cannot be changed in this infrastructure-only change. Its follow-up must build the main runtime artifact once, push the same manifest to `shopport/api` and `shopport/worker`, verify both immutable digests, and build and scan the Lambda artifact separately in `shopport/image-processor`. Hyphenated ECR repository names must not be used.
