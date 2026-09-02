#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${USE_SUDO:-1}" == "1" ]]; then
  KUBECTL=(sudo kubectl)
  MINIKUBE=(sudo minikube)
else
  KUBECTL=(kubectl)
  MINIKUBE=(minikube)
fi

KUBECONFIG_FILE="${1:-${KUBECONFIG_FILE:-}}"
if [[ -z "$KUBECONFIG_FILE" ]]; then
  if [[ -f /tmp/secure-workload-kubeconfig.yaml ]]; then
    KUBECONFIG_FILE=/tmp/secure-workload-kubeconfig.yaml
  elif [[ -f "$HOME/.kube/config" ]]; then
    KUBECONFIG_FILE="$HOME/.kube/config"
  fi
fi

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
}

info() {
  printf '[INFO] %s\n' "$1"
}

run_cmd() {
  local __var_name="$1"
  shift
  local __output
  if __output="$("$@" 2>&1)"; then
    printf -v "$__var_name" '%s' "$__output"
    return 0
  fi
  printf -v "$__var_name" '%s' "$__output"
  return 1
}

version_ok() {
  local version="$1"
  if [[ ! "$version" =~ ^v?([0-9]+)\.([0-9]+) ]]; then
    return 1
  fi

  local major="${BASH_REMATCH[1]}"
  local minor="${BASH_REMATCH[2]}"

  if (( major > 1 )); then
    return 0
  fi

  (( major == 1 && minor >= 27 ))
}

echo "== Cisco Secure Workload Kubernetes Prereq Check =="
echo "Repo: $ROOT_DIR"
echo "USE_SUDO=${USE_SUDO:-1}"
echo

if [[ -n "$KUBECONFIG_FILE" && -f "$KUBECONFIG_FILE" ]]; then
  pass "Kubeconfig file present: $KUBECONFIG_FILE"
else
  fail "No kubeconfig file found at the installer default ($HOME/.kube/config) or /tmp/secure-workload-kubeconfig.yaml"
  info "Export one with: sudo kubectl config view --raw > /tmp/secure-workload-kubeconfig.yaml"
fi

echo
echo "== Cluster access =="

cluster_ok=0
if run_cmd nodes_out "${KUBECTL[@]}" get nodes -o wide; then
  cluster_ok=1
  pass "kubectl can reach the cluster"
  printf '%s\n' "$nodes_out"
else
  fail "kubectl could not reach the cluster"
  printf '%s\n' "$nodes_out"
fi

if (( cluster_ok )); then
  if run_cmd version_out "${KUBECTL[@]}" version; then
    server_version="$(printf '%s\n' "$version_out" | sed -n 's/^Server Version: //p' | head -n1)"
    if [[ -n "$server_version" ]]; then
      if version_ok "$server_version"; then
        pass "Kubernetes server version is supported: $server_version"
      else
        fail "Kubernetes server version appears too old: $server_version"
      fi
    else
      warn "Could not parse Kubernetes server version from kubectl output"
      printf '%s\n' "$version_out"
    fi
  else
    warn "Could not read Kubernetes server version"
    printf '%s\n' "$version_out"
  fi

  if run_cmd auth_ns "${KUBECTL[@]}" auth can-i create namespace; then
    [[ "$auth_ns" == "yes" ]] && pass "Current credentials can create namespaces" || fail "Current credentials cannot create namespaces"
  fi
  if run_cmd auth_ds "${KUBECTL[@]}" auth can-i create daemonsets.apps -n tetration; then
    [[ "$auth_ds" == "yes" ]] && pass "Current credentials can create daemonsets in namespace tetration" || fail "Current credentials cannot create daemonsets in namespace tetration"
  fi
  if run_cmd auth_cr "${KUBECTL[@]}" auth can-i create clusterroles.rbac.authorization.k8s.io; then
    [[ "$auth_cr" == "yes" ]] && pass "Current credentials can create cluster roles" || fail "Current credentials cannot create cluster roles"
  fi

  if run_cmd node_os "${KUBECTL[@]}" get nodes -L kubernetes.io/os --no-headers; then
    if printf '%s\n' "$node_os" | awk '{print $NF}' | grep -q '^windows$'; then
      warn "Windows nodes detected; the Windows-specific Secure Workload requirements apply"
    else
      pass "All visible nodes are Linux; Windows-specific requirements do not apply"
    fi
  fi

  if run_cmd taints_out "${KUBECTL[@]}" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.taints[*]}{.key}{":"}{.effect}{","}{end}{"\n"}{end}'; then
    if printf '%s\n' "$taints_out" | grep -Eq 'node-role.kubernetes.io/(control-plane|master):NoSchedule'; then
      warn "Control-plane NoSchedule taints detected; install with --toleration if the agent must run there"
      printf '%s\n' "$taints_out"
    else
      pass "No control-plane NoSchedule taint detected in node taints"
    fi
  fi

  echo
  echo "== Existing tetration resources =="
  if run_cmd ns_out "${KUBECTL[@]}" get ns tetration; then
    pass "Namespace tetration exists"
    printf '%s\n' "$ns_out"

    if run_cmd pod_out "${KUBECTL[@]}" -n tetration get pods -o wide; then
      printf '%s\n' "$pod_out"
    fi

    if run_cmd sa_out "${KUBECTL[@]}" -n tetration get sa tetration-agent -o jsonpath='{.imagePullSecrets[*].name}'; then
      if [[ "$sa_out" == *tetration-imagepullsecret* ]]; then
        pass "Service account tetration-agent references tetration-imagepullsecret"
      else
        warn "Service account tetration-agent does not list tetration-imagepullsecret"
      fi
    fi

    if run_cmd secret_out "${KUBECTL[@]}" -n tetration get secret tetration-imagepullsecret; then
      pass "Image pull secret tetration-imagepullsecret exists"
    else
      warn "Image pull secret tetration-imagepullsecret is missing"
      printf '%s\n' "$secret_out"
    fi
  else
    warn "Namespace tetration does not exist yet; agent resources have not been installed"
  fi
fi

echo
echo "== Minikube node checks =="

if run_cmd profile_out "${MINIKUBE[@]}" profile list; then
  pass "minikube is installed and has a profile"
  printf '%s\n' "$profile_out"
else
  fail "minikube profile information could not be read"
  printf '%s\n' "$profile_out"
fi

if run_cmd mount_out "${MINIKUBE[@]}" ssh -- 'findmnt -no OPTIONS /tmp || mount | awk '"'"'$3=="/tmp"{print $6}'"'"''; then
  if [[ "$mount_out" == *noexec* ]]; then
    fail "Node /tmp is mounted noexec: $mount_out"
  else
    pass "Node /tmp mount options do not show noexec: ${mount_out:-<unknown>}"
  fi
else
  warn "Could not read node /tmp mount options"
  printf '%s\n' "$mount_out"
fi

if run_cmd tmp_exec_out "${MINIKUBE[@]}" ssh -- 'f=$(mktemp /tmp/tet.XXXXXX); printf "#!/bin/sh\necho ok\n" > "$f"; chmod +x "$f"; "$f"; rc=$?; rm -f "$f"; exit $rc'; then
  pass "Node can execute a temporary script from /tmp"
  printf '%s\n' "$tmp_exec_out"
else
  fail "Node cannot execute a temporary script from /tmp"
  printf '%s\n' "$tmp_exec_out"
  info "Cisco's createuser init container copies busybox into host /tmp and executes it with nsenter, so this check matters."
fi

if run_cmd runtime_out "${MINIKUBE[@]}" ssh -- 'pid=$(pgrep kubelet | head -n1); if [ -n "$pid" ]; then xargs -0 < /proc/$pid/cmdline | tr " " "\n" | grep "^--container-runtime-endpoint=" || true; fi'; then
  runtime_endpoint="${runtime_out#--container-runtime-endpoint=}"
  if [[ -n "$runtime_endpoint" ]]; then
    info "Kubelet runtime endpoint: $runtime_endpoint"
  else
    warn "Could not determine kubelet runtime endpoint"
  fi
else
  warn "Could not inspect kubelet runtime endpoint"
  printf '%s\n' "$runtime_out"
fi

if [[ "${runtime_endpoint:-}" == *containerd.sock* ]]; then
  if run_cmd cfg_out "${MINIKUBE[@]}" ssh -- 'grep -n "config_path *= *\"/etc/containerd/certs.d\"" /etc/containerd/config.toml'; then
    pass "containerd config_path is set to /etc/containerd/certs.d"
    printf '%s\n' "$cfg_out"
  else
    fail "containerd config_path is not set to /etc/containerd/certs.d"
    printf '%s\n' "$cfg_out"
  fi
else
  info "containerd-specific config_path check skipped because kubelet did not advertise containerd"
fi

if run_cmd busybox_out "${MINIKUBE[@]}" ssh -- 'crictl images 2>/dev/null | grep -E "(^|/)busybox[[:space:]]+1\.33(\.0)?([[:space:]]|$)" || ctr -n k8s.io images ls 2>/dev/null | grep -E "busybox:1\.33(\.0)?([[:space:]]|$)"'; then
  pass "busybox 1.33 is present on the node"
  printf '%s\n' "$busybox_out"
else
  warn "busybox 1.33 was not found in local image listings; it still may be pullable from Docker Hub"
fi

echo
echo "== Installer notes =="
info "The Cisco wrapper script defaults to \$HOME/.kube/config if --kubeconfig is not passed."
info "The same wrapper unpacks itself into /tmp/tetrationhelm.XXXXXX before running installer.sh."
info "The chart's createuser init container mounts host /tmp and executes a copied busybox there."
