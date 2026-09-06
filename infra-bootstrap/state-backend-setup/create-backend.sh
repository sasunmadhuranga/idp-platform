set -euo pipefail

ACCOUNT_ID_FOR_DEFAULT=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${1:-idp-platform-tfstate-${ACCOUNT_ID_FOR_DEFAULT}}"
REGION="${2:-us-east-1}"
LOCK_TABLE="idp-platform-tf-locks"

echo "Bucket: ${BUCKET_NAME}"
echo "Region: ${REGION}"
echo "Lock table: ${LOCK_TABLE}"
echo ""

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists, skipping creation."
else
  echo "Creating S3 bucket..."
  if [ "${REGION}" = "us-east-1" ]; then
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
