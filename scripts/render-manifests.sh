#!/usr/bin/env bash
#
# render-manifests.sh
#
# Bridges Terraform-provisioned Kubernetes resources into plain YAML
# manifests that ArgoCD's ApplicationSet can sync from. ArgoCD cannot
# read Terraform state directly, so after `terraform apply` we export
# the live state of each provisioned namespace as manifests under
# environments/rendered/<team>-<environment>/, and commit them.
#
# This intentionally does NOT re-invent what Terraform already created —
# it just mirrors the *result* to a Git-trackable, ArgoCD-syncable form,
# so ArgoCD's job stays "sync what's in Git" rather than needing to
# understand Terraform.
#
# Usage: ./scripts/render-manifests.sh
# Requires: kubectl (configured against the target cluster), yq (optional,
# for tidying output)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUESTS_DIR="${ROOT_DIR}/environments/requests"
RENDERED_DIR="${ROOT_DIR}/environments/rendered"

if ! command -v kubectl &> /dev/null; then
  echo "kubectl not found on PATH — required to export live manifests." >&2
  exit 1
fi

for request_file in "${REQUESTS_DIR}"/*.yaml; do
  [ -e "${request_file}" ] || continue

  team_name=$(grep -E '^team_name:' "${request_file}" | awk '{print $2}')
  environment=$(grep -E '^environment:' "${request_file}" | awk '{print $2}' || echo "dev")
  environment="${environment:-dev}"
  namespace="${team_name}-${environment}"

  if [ -z "${team_name}" ]; then
    echo "Skipping ${request_file}: could not parse team_name" >&2
    continue
  fi

  out_dir="${RENDERED_DIR}/${namespace}"
  mkdir -p "${out_dir}"

  echo "Rendering manifests for namespace: ${namespace}"

  # Export each resource type Terraform provisions for this namespace,
  # stripped of cluster-generated/mutable fields so diffs stay clean
  # and ArgoCD doesn't fight Terraform over ownership metadata.
  for kind in namespace resourcequota limitrange networkpolicy serviceaccount role rolebinding; do
    resource_file="${out_dir}/${kind}.yaml"

    if [ "${kind}" = "namespace" ]; then
      kubectl get namespace "${namespace}" -o yaml 2>/dev/null \
        | yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields, .status)' - \
        > "${resource_file}" 2>/dev/null || echo "  (skip) namespace ${namespace} not found yet"
    else
      kubectl get "${kind}" -n "${namespace}" -o yaml 2>/dev/null \
        | yq eval 'del(.items[].metadata.resourceVersion, .items[].metadata.uid, .items[].metadata.creationTimestamp, .items[].metadata.managedFields, .items[].status)' - \
        > "${resource_file}" 2>/dev/null || echo "  (skip) no ${kind} found in ${namespace} yet"
    fi

    # Remove empty/failed exports so we don't commit noise
    [ -s "${resource_file}" ] || rm -f "${resource_file}"
  done

  echo "  -> wrote manifests to ${out_dir}"
done

echo "Done. Review environments/rendered/ before committing."
