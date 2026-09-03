#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="$ROOT_DIR/k8s/tetragon-values.yaml"
POLICY_FILE="$ROOT_DIR/k8s/43-tetragon-db-file-tracingpolicy.yaml"

if [[ "${USE_SUDO:-0}" == "1" ]]; then
  KUBECTL=(sudo kubectl)
  HELM=(sudo helm)
else
  KUBECTL=(kubectl)
  HELM=(helm)
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not installed. Install Helm 3, then rerun this script." >&2
  exit 1
fi

"${HELM[@]}" repo add cilium https://helm.cilium.io --force-update
"${HELM[@]}" repo update

"${HELM[@]}" upgrade --install tetragon cilium/tetragon \
  --namespace kube-system \
  --create-namespace \
  --values "$VALUES_FILE"

"${KUBECTL[@]}" -n kube-system rollout status deployment/tetragon-operator --timeout=180s
"${KUBECTL[@]}" -n kube-system rollout status ds/tetragon --timeout=180s

"${KUBECTL[@]}" apply -f "$POLICY_FILE"

echo
echo "Tetragon was upgraded with explicit tracing-policy settings."
echo
echo "Then watch database-side Tetragon events:"
echo "  USE_SUDO=${USE_SUDO:-0} ./scripts/watch-tetragon-app-db.sh db --all"
