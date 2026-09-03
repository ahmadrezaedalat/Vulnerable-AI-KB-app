---
name: install-vulnerableapp-kubernetes
description: Install, resume, or verify the VulnerableApp single-node Kubernetes lab on Ubuntu by executing installation_readme.md in dependency order with mandatory success gates. Use when an AI agent must build the kubeadm/containerd/Calico cluster, configure storage and secrets, build and import the image, deploy with kubectl, expose and test the web app, and install and validate Tetragon with its Splunk HEC integration.
---

# Install VulnerableApp Kubernetes

Treat `installation_readme.md` as the authoritative command and configuration
reference. Orchestrate it like an idempotent installation program: inspect,
execute one phase, validate its postconditions, record the result, then continue.

## Load the source instructions

1. Resolve the repository root as two directories above this `SKILL.md`.
2. Read `<repo-root>/installation_readme.md` completely before changing the
   host or cluster.
3. Confirm that the referenced `k8s/`, `Dockerfile`, and application files exist.
4. If the README is absent or internally inconsistent, stop and report the
   exact issue. Do not reconstruct missing installation instructions from
   memory.

Use the README's current versions and commands. Do not substitute Minikube,
kind, MicroK8s, Docker Desktop Kubernetes, or another distribution. `kubeadm`
creates the cluster; `kubectl` manages it.

## Execution contract

- Maintain a checklist containing `phase`, `status`, `evidence`, and `next
  action`.
- Allow only these statuses: `pending`, `running`, `passed`, `failed`,
  `skipped-optional`, and `deferred-user-action`.
- Run phases in the order below. Never have more than one phase marked
  `running`.
- Do not mark a phase `passed` merely because its commands returned zero.
  Check every listed postcondition.
- Do not begin the next phase while a required postcondition is false.
- On failure, capture the relevant command output, diagnose with the README's
  troubleshooting section, make only an in-scope repair, and repeat the failed
  validation.
- Preserve unrelated workloads, files, firewall rules, container images, and
  cluster objects.
- Prefer idempotent commands (`apply`, `upgrade --install`, existence checks)
  when repeating work.
- Never run `kubeadm reset`, delete namespaces/PVs, erase PostgreSQL data, or
  execute the README removal section during installation.
- Never reboot automatically. Validate reboot persistence statically and tell
  the user when an actual reboot test remains.
- Provide concise progress updates after every phase and whenever an operation
  takes longer than one minute.

## Privilege and secret rules

- Determine which commands require `sudo`. Request normal execution approval
  through the host tool when available.
- Never ask the user to send a sudo password, HEC token, OpenAI key, Microsoft
  credential, or other secret in chat.
- If sudo requires an interactive password, give the user the exact minimal
  command to run locally, pause that phase, and resume by validating its result.
- Do not echo, log, summarize, or include secret values in tool output or the
  final report.
- Require the PostgreSQL password fields in `k8s/10-postgres.yaml` and
  `k8s/20-app.yaml` to be non-placeholder and identical before the first
  PostgreSQL deployment.
- Treat all credentials shipped in a training copy of the repository as
  compromised placeholders. Require replacement or explicit removal.
- Leave optional integrations empty when they are not configured. A normal AI
  assistant request requires a valid OpenAI key; Cisco and Microsoft 365 remain
  optional.
- Store the Splunk HEC token only in the Kubernetes Secret described by the
  README. Never place it in a Helm values file or shell history.

## Preflight and resume decision

Perform read-only discovery before installation:

- Identify Ubuntu release, architecture, hostname, IP addresses, CPU, memory,
  disk space, routes, active swap, firewall status, and internet/DNS access.
- Locate the repository root and check required files.
- Check for `containerd`, Docker, `kubeadm`, kubelet, `kubectl`, Helm, an
  existing kubeconfig, and an active Kubernetes API.
- Inspect existing Kubernetes nodes, namespaces, PVs, PVCs, deployments, and
  services when the API is reachable.
- Check whether ports `6443` and `3000` are already owned by other processes.

Classify the host:

- **Fresh**: no initialized kubeadm cluster. Begin Phase 1.
- **Partial**: some prerequisites or cluster components exist. Resume at the
  first phase whose postconditions are not satisfied.
- **Already installed**: validate all phases without reinstalling healthy
  components.
- **Conflicting**: another cluster, overlapping pod CIDR, claimed PV, unrelated
  port listener, or materially different runtime exists. Stop and ask before
  replacing or reconfiguring it.

Do not infer permission to destroy an existing cluster from a request to
install this application.

## Phase 1: Validate prerequisites and network plan

Follow README Sections 1 and 2.

Before passing:

- Ubuntu release and architecture are supported by the README.
- Required CPU, memory, disk, sudo access, DNS, and internet connectivity are
  available.
- The selected pod CIDR does not overlap a host, LAN, VPN, or existing route.
- The host has a stable address or the user acknowledges address changes.
- Required ports have no unexplained conflicts.
- Swap is inactive and active swap entries in `/etc/fstab` are disabled.
- `overlay` and `br_netfilter` are loaded and configured for reboot.
- IPv4 forwarding and bridge netfilter sysctls match the README.

If editing `/etc/fstab`, resolve exact swap entries first and preserve all
unrelated mounts.

## Phase 2: Validate the container runtime and image builder

Follow README Section 3.

Before passing:

- `containerd` and Docker are installed, enabled, and active.
- Containerd CRI is enabled.
- Containerd uses `SystemdCgroup = true`.
- Containerd responds through its configured socket.
- Docker can report both client and server versions.

Restart only services whose configuration changed. If Docker is used only for
image building, do not change the Kubernetes runtime away from containerd.

## Phase 3: Install Kubernetes tools

Follow README Section 4.

Before passing:

- The Kubernetes package repository and signing key match the README.
- kubelet, kubeadm, and kubectl are installed on the same supported minor
  release.
- Package holds are present.
- All three version commands succeed.

An inactive/restarting kubelet is acceptable only before kubeadm initialization.

## Phase 4: Initialize or validate kubeadm

Follow README Section 5.

- Run `kubeadm init` only when read-only checks prove that the host has not
  already been initialized.
- Use the validated pod CIDR.
- Configure the current non-root user's kubeconfig with restrictive file
  permissions.

Before passing:

- `kubectl cluster-info` reaches the intended local API server.
- Control-plane static pods are running.
- `kubectl get nodes` returns the local node.
- The node's temporary `NotReady` status is caused only by the not-yet-installed
  CNI.

Preserve the join command location in the report without exposing bootstrap
tokens.

## Phase 5: Install and validate Calico

Follow README Section 6 using the same pod CIDR chosen in Phase 1.

Before passing:

- Calico CRDs, operator, installation resources, and node agent are healthy.
- CoreDNS is running.
- The node is `Ready`.
- The single control-plane node is schedulable for lab workloads.
- NetworkPolicy resources are supported.

Do not remove the control-plane taint on a multi-node cluster with dedicated
workers unless the user explicitly requests scheduling there.

## Phase 6: Provision local database storage

Follow README Section 7.

Before creating the PV, check for an existing default StorageClass, matching
PV, claimed PV, or existing PostgreSQL host data. Do not overwrite or bind
unrelated storage.

Before passing:

- `vulnerableapp-postgres-local-pv` exists with the expected capacity,
  access mode, empty storage class, `Retain` policy, and explicit host path; or
  a user-approved equivalent storage provider satisfies the claim.
- The PV is `Available` before deployment or `Bound` to only the intended PVC
  after deployment.

## Phase 7: Configure application credentials

Follow README Section 8 before creating either application namespace.

Before passing:

- Database passwords are replaced, non-placeholder, and equal without printing
  them.
- Optional credentials are validly configured or empty.
- No credential is newly committed to source control.
- File permissions do not make newly supplied secrets broadly readable.

If the user must populate secrets manually, mark this phase
`deferred-user-action`, provide field names without values, and resume only
after validation succeeds.

## Phase 8: Build and import the application image

Follow README Section 9 from the repository root.

Before passing:

- The Docker build completes successfully.
- The image is imported into containerd's `k8s.io` namespace.
- The exact normalized tag expected by `k8s/20-app.yaml` exists.
- The imported image digest corresponds to the new build.
- The temporary archive is removed only after successful import.

On multiple schedulable nodes, require the image on every possible target node
or use a user-approved registry.

## Phase 9: Deploy in manifest order

Follow README Section 10 exactly:

1. Namespaces.
2. PostgreSQL resources.
3. Application resources.
4. Database NetworkPolicy.

Wait for the database rollout before the app rollout.

Before passing:

- PostgreSQL has one ready pod and zero unexpected restarts.
- Its PVC is `Bound` to the intended PV.
- The PostgreSQL Service has a ready endpoint on port `5432`.
- The app has one ready pod using the newly imported image.
- The app Service has a ready endpoint on port `3000`.
- `allow-app-to-postgres` exists in `vulnerableapp-db`.
- Pod events contain no unresolved scheduling, image, mount, probe, or network
  errors.

## Phase 10: Verify application behavior

Follow README Section 11.

Run in-cluster or temporary local checks before exposing the LAN listener.

Before passing:

- `/healthz` returns `{"status":"ok"}`.
- `/readyz` returns `{"status":"ready"}`.
- The Alice lookup returns the expected synthetic record from PostgreSQL.
- The running app reports the expected cross-namespace DB host and port.
- The UI loads over HTTP.
- If a valid OpenAI key was configured, a normal assistant request returns an
  answer. If it was intentionally omitted, report the assistant as disabled,
  not as a base installation failure.

## Phase 11: Expose the requested access path

Determine whether the user needs host-only or trusted-LAN access.

- For host-only access, bind the port-forward to localhost.
- For LAN access, bind it explicitly to `0.0.0.0` as documented.
- Never expose this intentionally vulnerable lab to the public internet.
- Add only a narrowly scoped firewall allowance for the trusted source network
  when required.

Before passing LAN access:

- `ss` shows `0.0.0.0:3000`, not only `127.0.0.1:3000` or `[::1]:3000`.
- Health and readiness succeed through the host's LAN IP.
- If local LAN-IP checks work but a remote client fails, diagnose UFW and
  upstream firewalls without replacing healthy Kubernetes resources.

If replacing an old listener, resolve its exact PID and command before stopping
only that `kubectl port-forward` process. Record that port-forward is temporary
and must be restarted after a pod replacement, terminal exit, or reboot.

## Phase 12: Validate maintenance and reboot readiness

Use README Sections 12 and 13 as validation/reference. Do not rebuild unchanged
source or reboot automatically.

Before passing:

- Swap is configured to remain disabled.
- Containerd and kubelet are enabled at boot.
- Persistent host storage uses the intended path and Retain policy.
- The user receives the unique-tag rebuild procedure.
- The user is told that port-forward is not persistent.

Mark an actual reboot test `deferred-user-action` unless explicitly authorized.

## Phase 13: Tetragon and Splunk integration

README Section 15 is part of the installation setup.

- Install and validate Tetragon on every setup when the kernel, BTF, privilege,
  image-pull, and Helm prerequisites pass.
- Treat Hubble Enterprise's Splunk HEC export as a required setup step after the
  user supplies a reachable HEC endpoint, index, and token. If those external
  inputs are not available, mark this phase `deferred-user-action` and name the
  missing inputs; do not silently skip the integration.
- Never place the HEC token in a values file, source file, shell history, or
  report. Store it only in the Kubernetes Secret described by the README.
- Use Isovalent Hubble Enterprise release `1.12.22` with the `export` block in
  `hubble-enterprise-values.yaml`, `mode: fluentd`, and the
  `export-fluentd` container. Do not substitute the Splunk OpenTelemetry
  Collector for this integration path.
- Before installing Hubble Enterprise, inspect rendered resources for overlap
  with the existing standalone `tetragon` Helm release. Stop and request a
  migration decision before uninstalling or replacing overlapping Tetragon
  resources.
- Never treat a missing external Splunk system or HEC token as a failure of the
  base application; it is a blocking prerequisite for completing this phase.

For Tetragon, require:

- One ready agent per node and a healthy operator.
- `k8s/43-tetragon-db-file-tracingpolicy.yaml` is the only repository tracing
  policy applied for this setup; the removed `k8s/40-tetragon-db-tracingpolicy.yaml`
  must not be recreated.
- The live database network rule evaluates `sockaddr` argument `index: 1` with
  `NotSAddr`, allowing only the configured application Service/pod IPs.
- The database pod's application-IP allowlist is refreshed after an application
  pod replacement.
- `export-stdout` emits JSON events.
- Local `tetra getevents` works.

For Hubble Enterprise/Splunk, require:

- The HEC token is stored only in the named Kubernetes Secret.
- The Hubble Enterprise DaemonSet and `export-fluentd` container are ready.
- Fluentd logs contain `fluentd worker is now running` and no HEC
  authentication, TLS, queue, or export failures.
- A newly generated Tetragon event appears in the intended Splunk index.

Do not claim Splunk success solely because the Hubble Enterprise pod is
running. Event arrival in Splunk is the terminal postcondition.

## Failure handling

For any failed phase:

1. Stop progression.
2. State the failed postcondition, not merely the failed command.
3. Gather the smallest relevant diagnostics from README Section 14 or 15.11.
4. Distinguish permission, host prerequisite, Kubernetes control plane, CNI,
   storage, image, database, app, listener, Tetragon, and Splunk failures.
5. Apply a reversible repair within the installation scope.
6. Re-run the phase validation.
7. After three failed repair attempts for the same cause, report the evidence
   and request the missing decision or host action.

Never skip a red validation to make later phases appear successful.

## Completion report

Return a compact installation report containing:

- Hostname, LAN IP, Ubuntu version, Kubernetes version, and node readiness.
- Passed and deferred phases.
- App and database pod readiness, service endpoints, and PVC/PV state.
- Image tag and digest, without registry credentials.
- Health, readiness, database lookup, UI, and assistant test results.
- Access URL and listener binding.
- Tetragon and Splunk event-delivery status.
- Any manual reboot, firewall, port-forward, secret rotation, or persistence
  action still required.

Do not include passwords, API keys, HEC tokens, kubeadm bootstrap tokens, or
Secret contents.
