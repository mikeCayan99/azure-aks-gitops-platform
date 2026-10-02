# Initial local Kubernetes deployment

The application is now managed by the Helm release described in [the chart documentation](../../charts/demo-app/README.md). The deployment commands below document the earlier kubectl step. Do not apply these Deployment and Service manifests over the Helm release. The namespace manifest remains shared setup.

These manifests run one demo application replica in the existing `aks-gitops` kind cluster. They are applied directly with kubectl before introducing Helm or Argo CD. Do not manage these same resources with multiple deployment tools at once.

## Deploy

Run from the repository root in PowerShell:

```powershell
docker build -t aks-gitops-demo:0.1.0 .
kind load docker-image aks-gitops-demo:0.1.0 --name aks-gitops
kubectl --context kind-aks-gitops apply -f environments/local/namespace.yaml
kubectl --context kind-aks-gitops apply -f environments/local/deployment.yaml -f environments/local/service.yaml
kubectl --context kind-aks-gitops -n demo-app rollout status deployment/demo-app --timeout=60s
kubectl --context kind-aks-gitops -n demo-app get pods,services
```

The image must be loaded into kind before deployment because `imagePullPolicy: Never` disables registry pulls. Use a new image tag when changing application code and update the deployment accordingly; reusing a tag does not trigger a rollout.

Expect one `Running` pod with `1/1` ready containers and an internal `ClusterIP` service. The service selects pods using the `app.kubernetes.io/name` label.

## Access

```powershell
kubectl --context kind-aks-gitops -n demo-app port-forward --address 127.0.0.1 service/demo-app 8000:8000
```

Leave that terminal running and open `http://localhost:8000/version`, `/health/live`, or `/health/ready`. Stop the port-forward with Ctrl+C. It forwards traffic to a selected pod; it does not verify the service's internal ClusterIP network path.

## Health and resources

The startup probe allows approximately 60 seconds for startup before liveness and readiness checks begin. Repeated liveness failures restart the container. Readiness failures remove the pod from ready service endpoints without restarting it.

Requests are scheduling inputs: 100 millicores (0.1 CPU) and 64 MiB memory. Limits are 500 millicores (0.5 CPU) and 128 MiB memory. CPU can be throttled at its limit; exceeding the memory limit can result in termination. These are initial values, not load-tested sizing.

The namespace enforces the Kubernetes v1.37 restricted Pod Security Standard. The container uses UID/GID 10001, a read-only root filesystem, no added Linux capabilities, no privilege escalation, and the runtime default seccomp profile. The pod does not mount a Kubernetes API token. Namespace separation and these settings do not establish network isolation; no NetworkPolicy is included.

## Inspect

```powershell
kubectl --context kind-aks-gitops -n demo-app describe deployment demo-app
kubectl --context kind-aks-gitops -n demo-app logs deployment/demo-app
kubectl --context kind-aks-gitops -n demo-app get endpointslices -l kubernetes.io/service-name=demo-app
```

Logs show application startup and HTTP probe requests. EndpointSlices contain the pod addresses used by the service.

## Remove application resources

The following removes this application's namespace and all resources inside it. It does not remove the kind cluster.

```powershell
kubectl --context kind-aks-gitops delete namespace demo-app
```
