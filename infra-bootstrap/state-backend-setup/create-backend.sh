#!/usr/bin/env bash
#
# create-backend.sh
#
# One-time setup: creates the S3 bucket + DynamoDB table used for
# Terraform remote state locking by BOTH infra-bootstrap (the EKS
# cluster) and idp-platform (the namespaces).
#
# Design choice: one bucket, two keys — not two buckets. The two
# Terraform states (cluster vs. namespaces) are kept independent by
# using different `key` values within the same bucket, which is
# simpler to manage and cheaper than two buckets, while still keeping
# the two states fully separate from Terraform's point of view.
#
#   s3://idp-platform-tfstate/infra-bootstrap/terraform.tfstate
#   s3://idp-platform-tfstate/idp-platform/terraform.tfstate
#
# This must be run with plain AWS CLI, not Terraform — you can't use
# a Terraform S3 backend to create the very bucket that backend
# depends on.
#
# Usage: ./create-backend.sh [bucket-name] [region]

set -euo pipefail

BUCKET_NAME="${1:-idp-platform-tfstate}"
REGION="${2:-us-east-1}"
LOCK_TABLE="idp-platform-tf-locks"

echo "Bucket: ${BUCKET_NAME}"
echo "Region: ${REGION}"
echo "Lock table: ${LOCK_TABLE}"
echo ""

# --- S3 bucket ---
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists, skipping creation."
else
  echo "Creating S3 bucket..."
  if [ "${REGION}" = "us-east-1" ]; then
    # us-east-1 is the one region where you must NOT pass a
    # LocationConstraint, or bucket creation fails.
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
fi

echo "Enabling versioning (protects state history, lets you recover from a bad apply)..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "Enabling default encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "Blocking all public access (state files can contain sensitive values)..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# --- DynamoDB lock table ---
# Both states share ONE lock table. Terraform namespaces locks by the
# `key` in each backend config, so a shared table is safe and normal —
# it does not risk one project's apply locking the other's.
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" &>/dev/null; then
  echo "DynamoDB table ${LOCK_TABLE} already exists, skipping creation."
else
  echo "Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${REGION}"
fi

echo ""
echo "Done. Backend configs to use:"
echo ""
echo "--- infra-bootstrap/backend.hcl ---"
echo "bucket         = \"${BUCKET_NAME}\""
echo "key            = \"infra-bootstrap/terraform.tfstate\""
echo "region         = \"${REGION}\""
echo "dynamodb_table = \"${LOCK_TABLE}\""
echo "encrypt        = true"
echo ""
echo "--- backend.hcl (idp-platform root) ---"
echo "bucket         = \"${BUCKET_NAME}\""
echo "key            = \"idp-platform/terraform.tfstate\""
echo "region         = \"${REGION}\""
echo "dynamodb_table = \"${LOCK_TABLE}\""
echo "encrypt        = true"
