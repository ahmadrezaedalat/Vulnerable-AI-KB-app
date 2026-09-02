#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-app}"
MODE="${2:-tcp}"

if [[ "${USE_SUDO:-0}" == "1" ]]; then
  KUBECTL=(sudo kubectl)
else
  KUBECTL=(kubectl)
fi

case "$TARGET" in
  app)
    TARGET_NAMESPACE="vulnerableapp"
    TARGET_SELECTOR="app.kubernetes.io/name=vulnerableapp"
    ;;
  db|postgres)
    TARGET_NAMESPACE="vulnerableapp-db"
    TARGET_SELECTOR="app.kubernetes.io/name=vulnerableapp-postgres"
    ;;
  *)
    echo "Usage: USE_SUDO=1 $0 [app|db] [tcp|--all]" >&2
    exit 2
    ;;
esac

TARGET_NODE="$("${KUBECTL[@]}" -n "$TARGET_NAMESPACE" get pod \
  -l "$TARGET_SELECTOR" \
  -o jsonpath='{.items[0].spec.nodeName}')"

if [[ -z "$TARGET_NODE" ]]; then
  echo "Could not find target pod for selector $TARGET_SELECTOR in namespace $TARGET_NAMESPACE" >&2
  exit 1
fi

TETRAGON_POD="$("${KUBECTL[@]}" -n kube-system get pod \
  -l app.kubernetes.io/name=tetragon \
  --field-selector "spec.nodeName=$TARGET_NODE" \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$TETRAGON_POD" ]]; then
  echo "Could not find a Tetragon pod on node $TARGET_NODE" >&2
  exit 1
fi

echo "Watching $TARGET_NAMESPACE on node $TARGET_NODE via $TETRAGON_POD"
if [[ "$MODE" == "--all" || "$MODE" == "all" ]]; then
  echo "Showing all compact Tetragon events for this namespace."
else
  echo "Showing compact network/process events. Normal app-to-DB :5432 traffic may be suppressed by policy."
fi
echo

if [[ "$MODE" == "--all" || "$MODE" == "all" ]]; then
  "${KUBECTL[@]}" -n kube-system exec -it "$TETRAGON_POD" -c tetragon -- \
    tetra getevents -o compact --namespace "$TARGET_NAMESPACE"
else
  "${KUBECTL[@]}" -n kube-system exec -it "$TETRAGON_POD" -c tetragon -- \
    tetra getevents -o compact --namespace "$TARGET_NAMESPACE" |
    grep --line-buffered -E 'connect|network|unexpected|tcp|file|mmap|truncate|permission|/var/lib/postgresql/data'
fi
