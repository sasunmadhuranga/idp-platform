# GitHub OIDC + IAM role setup

One-time, manual setup. So GitHub Actions can authenticate to AWS
without storing long-lived access keys as secrets. Run this once,
before your CI workflow's first real run.

## Files

- `trust-policy.json` — who's allowed to assume the role (GitHub
  Actions, scoped to `username/idp-platform`)
- `permissions-policy.json` — what the role is allowed to do once
  assumed (EKS describe, S3/DynamoDB state access)
- `setup-github-oidc.sh` — runs both steps via AWS CLI

## Run it

```bash
cd infra-bootstrap/iam-oidc-setup
./setup-github-oidc.sh
```

Copy the printed role ARN into your GitHub repo's `AWS_ROLE_ARN`
secret (Settings -> Secrets and variables -> Actions).

## Important: IAM role not equal Kubernetes access

An IAM role with `eks:DescribeCluster` can *see* the cluster exists,
but that's not the same as being allowed to act inside it via
`kubectl`/Terraform's Kubernetes provider. EKS clusters have their own
RBAC layer on top of IAM. The script prints the two follow-up commands
you need to run **after** `infra-bootstrap`'s cluster actually exists.

```bash
aws eks create-access-entry --cluster-name idp-demo \
  --principal-arn <ROLE_ARN>

aws eks associate-access-policy --cluster-name idp-demo \
  --principal-arn <ROLE_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=cluster
```

Skip this and CI's `terraform apply` will authenticate fine but fail
with a Kubernetes-level "Unauthorized" error the moment it tries to
touch a namespace or resource. A confusing failure mode if you do not
know to look for it.

