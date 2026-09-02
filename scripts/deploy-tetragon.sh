#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_FILE="$ROOT_DIR/k8s/40-tetragon-db-tracingpolicy.yaml"

if [[ "${USE_SUDO:-0}" == "1" ]]; then
  KUBECTL=(sudo kubectl)
  HELM=(sudo helm)
else
  KUBECTL=(kubectl)
  HELM=(helm)
fi

if ! command -v helm >/dev/null 2>&1; then
  cat >&2 <<'EOF'
helm is not installed.

Install Helm 3 first:

  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh

Then rerun this script.
EOF
  exit 1
fi

"${KUBECTL[@]}" get nodes

"${HELM[@]}" repo add cilium https://helm.cilium.io --force-update
"${HELM[@]}" repo update
"${HELM[@]}" upgrade --install tetragon cilium/tetragon \
  --namespace kube-system \
  --create-namespace

"${KUBECTL[@]}" rollout status -n kube-system ds/tetragon -w
"${KUBECTL[@]}" apply -f "$POLICY_FILE"

echo
echo "Tetragon is deployed and the vulnerableapp unexpected-network tracing policy is applied."
echo
echo "Watch unexpected app network events:"
echo "  USE_SUDO=${USE_SUDO:-0} ./scripts/watch-tetragon-app-db.sh app --all"
echo
echo "Normal app-to-DB :5432 traffic is suppressed by the policy. Trigger app activity:"
echo "  curl http://localhost:3000/readyz"
echo "  curl \"http://localhost:3000/api/clients?q=Alice\""
