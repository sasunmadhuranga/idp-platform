set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="idp-platform-github-actions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Account ID: ${ACCOUNT_ID}"
echo "Region: ${REGION}"

EXISTING_PROVIDER=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

if [ -z "${EXISTING_PROVIDER}" ]; then
  echo "Creating GitHub OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
else
  echo "GitHub OIDC provider already exists: ${EXISTING_PROVIDER}"
fi

TRUST_POLICY_TMP="${SCRIPT_DIR}/.trust-policy-filled.json"
PERMISSIONS_POLICY_TMP="${SCRIPT_DIR}/.permissions-policy-filled.json"

sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "${SCRIPT_DIR}/trust-policy.json" > "${TRUST_POLICY_TMP}"

echo "Creating IAM role: ${ROLE_NAME}..."
aws iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document "$(cat "${TRUST_POLICY_TMP}")" \
  --description "Assumed by GitHub Actions CI for idp-platform"

sed -e "s/ACCOUNT_ID/${ACCOUNT_ID}/g" -e "s/REGION/${REGION}/g" \
  "${SCRIPT_DIR}/permissions-policy.json" > "${PERMISSIONS_POLICY_TMP}"

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "idp-platform-ci-permissions" \
  --policy-document "$(cat "${PERMISSIONS_POLICY_TMP}")"

ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)

echo ""
echo "Done. Add this as the AWS_ROLE_ARN secret in your GitHub repo:"
echo "  ${ROLE_ARN}"
echo ""
echo "IMPORTANT: this role also needs to be granted access to the EKS"
echo "cluster's Kubernetes RBAC (IAM permissions alone aren't enough"
echo "for kubectl/terraform to act inside the cluster). After your"
echo "cluster exists, run:"
echo ""
echo "  aws eks create-access-entry --cluster-name idp-demo \\"
echo "    --principal-arn ${ROLE_ARN} --region ${REGION}"
echo ""
echo "  aws eks associate-access-policy --cluster-name idp-demo \\"
echo "    --principal-arn ${ROLE_ARN} \\"
echo "    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \\"
echo "    --access-scope type=cluster --region ${REGION}"

rm -f "${TRUST_POLICY_TMP}" "${PERMISSIONS_POLICY_TMP}"
