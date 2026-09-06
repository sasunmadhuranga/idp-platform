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

    [ -s "${resource_file}" ] || rm -f "${resource_file}"
  done

  echo "  -> wrote manifests to ${out_dir}"
done

echo "Done. Review environments/rendered/ before committing."
