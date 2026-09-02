#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-vulnerableapp:redeploy-$(date +%Y%m%d%H%M%S)}"

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

echo "Building app image: $TAG"
"${DOCKER[@]}" build -t "$TAG" .

echo "Loading image into minikube: $TAG"
"${MINIKUBE[@]}" image load "$TAG"

echo "Updating vulnerableapp deployment image"
"${KUBECTL[@]}" -n vulnerableapp set image deployment/vulnerableapp "web=$TAG"
"${KUBECTL[@]}" -n vulnerableapp rollout status deployment/vulnerableapp

APP_POD="$("${KUBECTL[@]}" -n vulnerableapp get pod \
  -l app.kubernetes.io/name=vulnerableapp \
  -o jsonpath='{.items[0].metadata.name}')"

echo
echo "Current app pod: $APP_POD"
echo "Verifying updated assistant code and UI placeholder:"
"${KUBECTL[@]}" -n vulnerableapp exec "$APP_POD" -- \
  grep -n "Raw SQL mode" /app/personal_ai_assistant.py
"${KUBECTL[@]}" -n vulnerableapp exec "$APP_POD" -- \
  grep -n 'placeholder=""' /app/public/index.html

echo
echo "Redeploy complete."
echo
echo "Port-forward with:"
echo "  ${KUBECTL[*]} -n vulnerableapp port-forward --address 0.0.0.0 service/vulnerableapp 3001:80"
