# infra-bootstrap — demo cluster for idp-platform

A minimal, cheap EKS cluster with ArgoCD pre-installed, sized purely
to demo `idp-platform`. This is **not** meant to run continuously —
spin it up, run the demo/record video, then destroy it, the same way
the `gitops-pipeline` and `bluegreen-argo-rollouts` clusters were torn
down after their projects were done.

Kept as a separate Terraform state from the root `idp-platform`
module so you can destroy the cluster without touching the
namespace-provisioning state, and vice versa.

## What it creates

- A VPC with 2 public + 2 private subnets, single NAT gateway (cost
  optimization — not multi-AZ HA, this is a demo cluster)
- An EKS cluster (v1.29) with one managed node group, SPOT instances,
  t3.small, 2 nodes by default
- ArgoCD installed via Helm (single replica, no HA)
- IRSA (IAM Roles for Service Accounts) enabled, which also gives you
  the OIDC provider needed for `idp-platform`'s GitHub Actions to
  authenticate against this cluster

## Usage

```bash
cd infra-bootstrap
terraform init
terraform apply -var="cluster_name=idp-demo"

# point kubectl at it
aws eks update-kubeconfig --name idp-demo --region us-east-1

# get the ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# now go run idp-platform's own terraform apply against this cluster,
# open PRs against environments/requests/, record your demo, etc.
```

## When you're done

```bash
# tear down idp-platform's own resources first (namespaces etc.)
cd ../
terraform destroy -var="eks_cluster_name=idp-demo"

# then tear down the cluster itself
cd infra-bootstrap
terraform destroy -var="cluster_name=idp-demo"
```

Destroying in this order avoids Terraform trying to delete a
Kubernetes namespace on a cluster that no longer exists.

## Cost awareness

Even at this minimal size, an EKS cluster costs real money per hour
(cluster control plane + EC2 nodes + NAT gateway). Don't leave this
running — the whole point of separating it from `idp-platform`'s
state is so it's trivial to `destroy` right after recording your
demo, same pattern you used for the earlier two projects.
