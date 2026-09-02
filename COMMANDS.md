# Lab Commands

This file keeps the high-use lab commands separate from the main README.

## Build From Scratch

Use this when you want to build the Docker image, apply all app Kubernetes
manifests, update the deployment image, wait for rollouts, and apply the lab
Tetragon policies in one pass:

```bash
cd /home/tme/VulnerableApp_v2
USE_SUDO=1 ./scripts/build-from-scratch.sh
```

## Check Cisco Secure Workload Prereqs

Use this before reinstalling the Cisco/Tetration agent. It checks:

- kubeconfig path
- cluster access and basic RBAC
- Kubernetes version
- minikube `/tmp` mount and execution
- kubelet runtime and containerd `config_path`
- `busybox:1.33`
- current `tetration` namespace resources and pull secret wiring

```bash
cd /home/tme/VulnerableApp_v2
USE_SUDO=1 ./scripts/check-tetration-prereqs.sh
```

## Redeploy The App

Use the script:

```bash
cd /home/tme/VulnerableApp_v2
USE_SUDO=1 ./scripts/redeploy-app.sh
```

Or run the same flow manually:

```bash
cd /home/tme/VulnerableApp_v2
TAG=vulnerableapp:redeploy-$(date +%Y%m%d%H%M%S)
sudo docker build -t "$TAG" .
sudo minikube image load "$TAG"
sudo kubectl -n vulnerableapp set image deployment/vulnerableapp web="$TAG"
sudo kubectl -n vulnerableapp rollout status deployment/vulnerableapp
```

Verify the running pod has the latest files:

```bash
APP_POD=$(sudo kubectl -n vulnerableapp get pod -l app.kubernetes.io/name=vulnerableapp -o jsonpath='{.items[0].metadata.name}')
sudo kubectl -n vulnerableapp exec "$APP_POD" -- grep -n "Raw SQL mode" /app/personal_ai_assistant.py
sudo kubectl -n vulnerableapp exec "$APP_POD" -- grep -n 'placeholder=""' /app/public/index.html
```

## Port-Forward The App

Use `3001` if `3000` is already busy:

```bash
sudo kubectl -n vulnerableapp port-forward --address 0.0.0.0 service/vulnerableapp 3001:80
```

Open:

```text
http://<your-server-ip>:3001
```

## Apply Tetragon Policies

Unexpected network visibility outside normal app-to-PostgreSQL `:5432` traffic:

```bash
sudo kubectl apply -f k8s/40-tetragon-db-tracingpolicy.yaml
```

DB data directory filesystem activity and DB outbound TCP connectivity:

```bash
sudo kubectl apply -f k8s/43-tetragon-db-file-tracingpolicy.yaml
```

If the older DB command-exec policy was applied before the cleanup, remove the
stale cluster object once:

```bash
sudo kubectl -n vulnerableapp-db delete tracingpolicynamespaced vulnerableapp-postgres-command-exec --ignore-not-found
```

## Monitor App Events

All compact Tetragon events for the app namespace:

```bash
APP_NODE=$(sudo kubectl -n vulnerableapp get pod -l app.kubernetes.io/name=vulnerableapp -o jsonpath='{.items[0].spec.nodeName}'); TETRAGON_POD=$(sudo kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$APP_NODE -o jsonpath='{.items[0].metadata.name}'); sudo kubectl -n kube-system exec -it "$TETRAGON_POD" -c tetragon -- tetra getevents -o compact --namespace vulnerableapp
```

Helper equivalent:

```bash
USE_SUDO=1 ./scripts/watch-tetragon-app-db.sh app --all
```

## Monitor Database Events

All compact Tetragon events for the database namespace, including file-access
events and unexpected DB outbound TCP connects from the DB runtime policy:

```bash
DB_NODE=$(sudo kubectl -n vulnerableapp-db get pod -l app.kubernetes.io/name=vulnerableapp-postgres -o jsonpath='{.items[0].spec.nodeName}'); TETRAGON_POD=$(sudo kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$DB_NODE -o jsonpath='{.items[0].metadata.name}'); sudo kubectl -n kube-system exec -it "$TETRAGON_POD" -c tetragon -- tetra getevents -o compact --namespace vulnerableapp-db
```

Helper equivalent:

```bash
USE_SUDO=1 ./scripts/watch-tetragon-app-db.sh db --all
```

## Trigger Activity

App-to-DB traffic:

```bash
curl "http://localhost:3001/api/clients?q=Alice"
```

DB data directory access:

```bash
sudo kubectl -n vulnerableapp-db exec deployment/vulnerableapp-postgres -- sh -c 'ls -la /var/lib/postgresql/data >/dev/null'
```

## Remove Tetragon Policies

```bash
sudo kubectl delete -f k8s/43-tetragon-db-file-tracingpolicy.yaml
sudo kubectl delete -f k8s/40-tetragon-db-tracingpolicy.yaml
```
