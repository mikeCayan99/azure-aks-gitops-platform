# Demo application Helm chart

This chart renders a Deployment, a ClusterIP Service, and a dedicated ServiceAccount. The namespace and its Pod Security labels are managed separately. No Helm release is installed by the validation commands below.

## Configuration

| Value | Purpose | Default |
| --- | --- | --- |
| `replicaCount` | Desired pod count | `1` |
| `image.repository` | Container image repository | `aks-gitops-demo` |
| `image.tag` | Container image tag | `0.1.0` |
| `image.pullPolicy` | Registry pull behavior | `IfNotPresent` |
| `appVersion` | Value exposed through `APP_VERSION` | `0.1.0` |
| `resources` | CPU and memory requests and limits | Initial values from the local manifests |

`environments/local/values.yaml` selects the tested image tag `git-e1f3391` and overrides the image pull policy to `Never` for images loaded directly into kind. See [the local image update procedure](../../gitops/local/README.md#update-the-local-application-image). A future AKS configuration must supply a registry image; no AKS configuration is included yet.

`Chart.yaml` version identifies the chart package. Its `appVersion` field documents the application version; it does not select the image or set `APP_VERSION`. Those settings are explicit values above.

Resource names use the release name. Deployment and Service selectors include the release instance label so separate releases do not select each other's pods. HTTP port 8000, health probes, and container security settings remain fixed for this application.

## Validate without installing

From the repository root:

```powershell
helm lint charts/demo-app --strict
helm lint charts/demo-app --strict -f environments/local/values.yaml
helm template demo-app charts/demo-app --namespace demo-app -f environments/local/values.yaml
```

`helm lint` checks chart structure and rendering. `helm template` prints the generated Kubernetes YAML without changing the cluster.

For validation against the existing local cluster, use a distinct release name to avoid the existing Deployment's immutable selector:

```powershell
helm template demo-app-check charts/demo-app --namespace demo-app -f environments/local/values.yaml | kubectl --context kind-aks-gitops apply --dry-run=server --validate=strict -f -
```

The existing `demo-app` namespace must already exist. Server dry-run validates resources and admission policy without storing them; it does not establish runtime health.

## Existing local deployment

The manifests in `environments/local/deployment.yaml` and `service.yaml` preserve the initial kubectl deployment step. A Helm release was used to validate this chart locally, then removed during the transition to [Argo CD](../../gitops/local/README.md). The local application is now managed by Argo CD. Do not install or upgrade a Helm release against those same resources, or apply the old kubectl manifests over them.

A Helm installation requires an explicit transition: remove the old application Deployment and Service, keep the namespace, and install the chart as a Helm release. This causes a brief interruption with a single replica. The chart changes the Deployment selector to include the release instance; that selector cannot be changed in place. Adoption of the existing resources is not used.

Local validation covered chart linting, rendering, server-side dry runs, Helm installation, pod readiness, all three endpoints through the internal service, non-root execution, and absence of a mounted API token. Helm upgrade and rollback remain unverified. No load testing or failure scenarios are included.

## Standalone Helm installation into an empty application namespace

After creating the namespace with `environments/local/namespace.yaml` and loading the image into kind, install only if no conflicting application Deployment or Service exists:

```powershell
helm install demo-app charts/demo-app --kube-context kind-aks-gitops --namespace demo-app -f environments/local/values.yaml --wait --timeout 60s --rollback-on-failure
```

These flags use Helm 4.3.0. `--wait` waits for readiness; `--rollback-on-failure` removes the failed installation. This does not restore resources that were removed before installation.

## Inspect a standalone Helm release

```powershell
helm status demo-app --kube-context kind-aks-gitops -n demo-app
helm history demo-app --kube-context kind-aks-gitops -n demo-app
kubectl --context kind-aks-gitops -n demo-app get pods,services,serviceaccounts
kubectl --context kind-aks-gitops -n demo-app port-forward --address 127.0.0.1 service/demo-app 8000:8000
```

A successful initial installation reports `deployed` and revision `1`. Stop port-forward with Ctrl+C; the release continues running.
