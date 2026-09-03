#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-vulnerableapp:fresh-$(date +%Y%m%d%H%M%S)}"

if [[ "${USE_SUDO:-1}" == "1" ]]; then
  DOCKER=(sudo docker)
  MINIKUBE=(sudo minikube)
  KUBECTL=(sudo kubectl)
else
  DOCKER=(docker)
  MINIKUBE=(minikube)
  KUBECTL=(kubectl)
fi

cd "$ROOT_DIR"

echo "== Kubernetes context =="
"${KUBECTL[@]}" config current-context || true
"${KUBECTL[@]}" get nodes

echo
echo "== Build app image =="
echo "Image tag: $TAG"
"${DOCKER[@]}" build -t "$TAG" .

echo
echo "== Load image into minikube =="
"${MINIKUBE[@]}" image load "$TAG"

echo
echo "== Apply base Kubernetes manifests =="
"${KUBECTL[@]}" apply -f k8s/00-namespaces.yaml
"${KUBECTL[@]}" apply -f k8s/10-postgres.yaml
"${KUBECTL[@]}" apply -f k8s/20-app.yaml
"${KUBECTL[@]}" apply -f k8s/30-db-networkpolicy.yaml

echo
echo "== Set deployment image to fresh build =="
"${KUBECTL[@]}" -n vulnerableapp set image deployment/vulnerableapp "web=$TAG"

echo
echo "== Wait for rollouts =="
"${KUBECTL[@]}" -n vulnerableapp-db rollout status deployment/vulnerableapp-postgres --timeout=180s
"${KUBECTL[@]}" -n vulnerableapp rollout status deployment/vulnerableapp --timeout=180s

echo
echo "== Apply Tetragon lab policies =="
"${KUBECTL[@]}" apply -f k8s/43-tetragon-db-file-tracingpolicy.yaml
"${KUBECTL[@]}" -n vulnerableapp-db delete tracingpolicynamespaced vulnerableapp-postgres-command-exec --ignore-not-found

APP_POD="$("${KUBECTL[@]}" -n vulnerableapp get pod \
  -l app.kubernetes.io/name=vulnerableapp \
  -o jsonpath='{.items[0].metadata.name}')"

echo
echo "== Verify app files in running pod =="
"${KUBECTL[@]}" -n vulnerableapp exec "$APP_POD" -- grep -n "Raw SQL mode" /app/personal_ai_assistant.py
"${KUBECTL[@]}" -n vulnerableapp exec "$APP_POD" -- grep -n 'placeholder=""' /app/public/index.html

echo
echo "== Done =="
echo "App pod: $APP_POD"
echo
echo "Port-forward the app:"
echo "  ${KUBECTL[*]} -n vulnerableapp port-forward --address 0.0.0.0 service/vulnerableapp 3001:80"
echo
echo "Watch app Tetragon events:"
echo "  USE_SUDO=${USE_SUDO:-1} ./scripts/watch-tetragon-app-db.sh app --all"
echo
echo "Watch DB Tetragon events:"
echo "  USE_SUDO=${USE_SUDO:-1} ./scripts/watch-tetragon-app-db.sh db --all"
