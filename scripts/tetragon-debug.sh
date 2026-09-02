#!/usr/bin/env bash
set -euo pipefail

if [[ "${USE_SUDO:-0}" == "1" ]]; then
  KUBECTL=(sudo kubectl)
else
  KUBECTL=(kubectl)
fi

section() {
  printf '\n== %s ==\n' "$1"
}

section "Cluster"
"${KUBECTL[@]}" get nodes -o wide

section "Workloads"
"${KUBECTL[@]}" -n vulnerableapp get pods -o wide --show-labels
"${KUBECTL[@]}" -n vulnerableapp-db get pods -o wide --show-labels
"${KUBECTL[@]}" -n kube-system get pods -l app.kubernetes.io/name=tetragon -o wide

section "Tetragon CRDs"
"${KUBECTL[@]}" api-resources | grep -i tetragon || true
"${KUBECTL[@]}" api-resources | grep -i tracing || true

section "Tracing Policies"
"${KUBECTL[@]}" get tracingpolicy -A 2>/dev/null || true
"${KUBECTL[@]}" get tracingpolicynamespaced -A 2>/dev/null || true
"${KUBECTL[@]}" -n vulnerableapp describe tracingpolicynamespaced vulnerableapp-postgres-client-network 2>/dev/null || true
"${KUBECTL[@]}" -n vulnerableapp-db describe tracingpolicynamespaced vulnerableapp-postgres-server-network 2>/dev/null || true
"${KUBECTL[@]}" -n vulnerableapp-db describe tracingpolicynamespaced vulnerableapp-postgres-data-file-access 2>/dev/null || true

TETRAGON_POD="$("${KUBECTL[@]}" -n kube-system get pod \
  -l app.kubernetes.io/name=tetragon \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [[ -n "$TETRAGON_POD" ]]; then
  section "Tetragon Loaded Policies"
  "${KUBECTL[@]}" -n kube-system exec "$TETRAGON_POD" -c tetragon -- \
    tetra tracingpolicy list 2>/dev/null || true

  section "Kernel Hook Symbols"
  "${KUBECTL[@]}" -n kube-system exec "$TETRAGON_POD" -c tetragon -- \
    sh -c "grep -E '(^| )(tcp_v4_connect|tcp_v6_connect|security_file_permission|security_mmap_file|security_path_truncate|security_file_truncate)$' /proc/kallsyms | head -50" 2>/dev/null || true

  section "Connect Tracepoints"
  "${KUBECTL[@]}" -n kube-system exec "$TETRAGON_POD" -c tetragon -- \
    sh -c "ls -d /sys/kernel/tracing/events/syscalls/sys_enter_connect /sys/kernel/tracing/events/syscalls/sys_exit_connect 2>/dev/null" 2>/dev/null || true
fi

section "Tetragon Logs"
"${KUBECTL[@]}" -n kube-system logs -l app.kubernetes.io/name=tetragon -c tetragon --tail=200 |
  grep -Ei 'error|warn|policy|sensor|tcp_v4_connect|tcp_v6_connect|security_file_permission|security_mmap_file|security_path_truncate|security_file_truncate|vulnerableapp' || true

section "Tetragon Operator Logs"
"${KUBECTL[@]}" -n kube-system logs -l app.kubernetes.io/name=tetragon-operator --tail=120 2>/dev/null |
  grep -Ei 'error|warn|policy|crd|tracing' || true

section "App Ready Check"
"${KUBECTL[@]}" -n vulnerableapp get endpoints vulnerableapp -o wide
"${KUBECTL[@]}" -n vulnerableapp-db get endpoints vulnerableapp-postgres -o wide

cat <<'EOF'

Next high-signal test:

1. Apply the runtime policies:
     sudo kubectl apply -f k8s/40-tetragon-db-tracingpolicy.yaml
     sudo kubectl apply -f k8s/43-tetragon-db-file-tracingpolicy.yaml

2. In one terminal, watch DB events:
     USE_SUDO=1 ./scripts/watch-tetragon-app-db.sh db --all

3. In another terminal, trigger DB data directory access:
     sudo kubectl -n vulnerableapp-db exec deployment/vulnerableapp-postgres -- sh -c 'ls -la /var/lib/postgresql/data >/dev/null'
EOF
