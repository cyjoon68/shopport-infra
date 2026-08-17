# Runtime contracts and migration

## Application runtime

The runtime Secrets Manager payload exposes `RAW_ASSET_BUCKET`, `NORMALIZED_ASSET_BUCKET`, `ARCHIVE_BUCKET`, `SQS_ASSET_RESULT_URL`, and `OPENSEARCH_URL`. `ASSET_BUCKET` remains an alias of `RAW_ASSET_BUCKET` for the expand/contract migration and must be removed only after every application deployment reads `RAW_ASSET_BUCKET`.

The image processor is invoked only by `ObjectCreated` events from the raw asset bucket. It receives `SQS_ASSET_RESULT_URL` and `NORMALIZED_ASSET_BUCKET`. `lambda_image_uri` accepts only `shopport/image-processor` ECR image URIs pinned by a `sha256` digest.

## Credentials bootstrap

Terraform creates the `shopport-ENV/credentials` secret container. Every environment requires an operator-supplied `AWSCURRENT` JSON payload through the approved secret-management process before deployment.

Supply credentials before the first Argo sync. Every environment requires `COMMAND_CODE_API_KEY` in the credentials secret. The non-secret `COMMAND_CODE_MODEL` is pinned to `gpt-5.4-mini` by Helm. Do not put credential values in Terraform variables, Helm values, CI logs, or this repository.

## Queue migration

The former `shopport-ENV-image` queue is replaced by `shopport-ENV-asset-result`. Before applying, pause image ingestion and drain or redrive messages from the old queue. Apply Terraform, confirm the runtime secret contains the new queue URL, then sync the worker deployment and resume ingestion. The legacy Terraform output names remain temporarily as aliases, while new consumers should use `asset_result_queue_url` and `asset_result_queue_arn`.

The Wave 1 Aurora outbox is polled directly by the baseline worker replica, so `worker.minReplicas` must remain at least 1. The SQS outbox queue is retained only as a future relay migration placeholder. It is not a KEDA activation source and is not exposed to the application or workload role until an SQS relay and consumer with idempotency are implemented.

## Follow-ups outside this repository

The workload role remains shared by API, worker, and migration because splitting it requires coordinated application and deployment changes. A follow-up should create dedicated service accounts and roles, then reduce S3, SQS, OpenSearch, and Secrets Manager permissions per component.

The backend image-publish workflow is owned by `cyjoon68/shopport-be` and cannot be changed in this infrastructure-only change. Its follow-up must build the main runtime artifact once, push the same manifest to `shopport/api` and `shopport/worker`, verify both immutable digests, and build and scan the Lambda artifact separately in `shopport/image-processor`. Hyphenated ECR repository names must not be used.
