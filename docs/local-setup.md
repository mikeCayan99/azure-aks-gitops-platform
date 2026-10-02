# Local Kubernetes, Helm, and Argo CD setup

Argo CD v3.5.3 uses the official non-HA installation in the existing `aks-gitops` kind cluster. The UI is accessed only through a loopback port-forward. No Azure resources or public application services are created.


This guide brings the Helm and Argo CD procedures together. Commands run from the repository root in PowerShell. The recorded kind environment was removed after validation; reconstruct it before using cluster commands below.

## Prerequisites and cluster

Docker Desktop, kind, kubectl, and Helm are required. Start Docker Desktop and create a dedicated cluster if it does not already exist:

```powershell
kind create cluster --name aks-gitops
kubectl --context kind-aks-gitops get nodes
```

Review the Kubernetes version selected by your kind release against Argo CD compatibility. The recorded validation used Kubernetes 1.37.0 and Argo CD 3.5.3; see the compatibility note below.

Before deploying the application, build and load the image that matches the local values. Follow [the image procedure](#update-the-local-application-image), including its source-revision requirement. For a new source revision, use a new image tag and merge the matching values change before Argo CD synchronization.

Use the Argo CD setup below for the GitOps path. The standalone Helm commands later in this guide describe the earlier validation stage and an alternative installation path. Manage each application resource with one deployment tool at a time.
## Install and bootstrap

From the repository root in PowerShell:

```powershell
kubectl --context kind-aks-gitops apply -f gitops/local/namespace.yaml
kubectl --context kind-aks-gitops apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml
kubectl --context kind-aks-gitops -n argocd wait --for=condition=Available deployment --all --timeout=120s
kubectl --context kind-aks-gitops -n argocd rollout status statefulset/argocd-application-controller --timeout=120s
kubectl --context kind-aks-gitops apply -f environments/local/namespace.yaml
kubectl --context kind-aks-gitops apply -f gitops/local/rbac.yaml
kubectl --context kind-aks-gitops -n argocd patch configmap argocd-cm --type merge --patch-file gitops/local/rbac-config.patch.yaml
kubectl --context kind-aks-gitops apply -f gitops/local/project.yaml -f gitops/local/application.yaml
```

The bootstrap files are applied explicitly with kubectl; Argo CD does not manage its own installation or Application definition in this setup. No vendored upstream installation manifest is committed.

The Application reads `charts/demo-app` from the public repository's `main` branch and uses `environments/local/values.yaml`. No Git credentials are required. Local uncommitted chart changes are not read by Argo CD. Keep the Application name and Helm rendering release name `demo-app` aligned with the chart's instance labels.

The AppProject permits only this repository, this cluster's `demo-app` namespace, and Deployment, Service, ServiceAccount, and NetworkPolicy resources. The namespace is provisioned separately; the project does not allow cluster-scoped resources.

## Access the UI

```powershell
kubectl --context kind-aks-gitops -n argocd port-forward --address 127.0.0.1 service/argocd-server 8080:443
```

Open `https://localhost:8080`. The default installation uses a self-signed TLS certificate, so the browser may show a certificate warning for this local address. Log in as `admin`. In a separate local terminal, retrieve the initial password:

```powershell
$argoInitialPassword = kubectl --context kind-aks-gitops -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($argoInitialPassword))
Remove-Variable argoInitialPassword
```

Keep the password out of repository files, screenshots, and logs. Change it through the user settings after login. Stop the port-forward with Ctrl+C; Argo CD continues running.

## Manual synchronization and ownership transition

Automatic sync, self-heal, and automatic pruning are disabled because no automated sync policy is configured. Refresh and inspect the Application before selecting Sync. A matching comparison alone is not proof that Argo CD has taken ownership or performed a deployment.

The initial local Helm release was removed before the first successful Argo CD sync. For a fresh migration, any existing `demo-app` Helm release must be removed before synchronization. Do not run Helm upgrades or apply the earlier kubectl Deployment/Service manifests after Argo CD takes over.

When ready for the transition, record the current Git revision, inspect the generated resources, and run:

```powershell
helm uninstall demo-app --kube-context kind-aks-gitops -n demo-app --wait --timeout 60s
```

This removes the application's Helm-managed resources but preserves its namespace. There is a brief application interruption. In the Argo CD UI, refresh `demo-app`, review the Deployment, Service, and ServiceAccount, then select Sync without enabling prune or force. Argo CD renders the chart and applies its resources; it does not create a Helm release or Helm history.

For recovery before a successful Argo CD sync, ensure no sync operation is running and no Argo-managed resources remain before reinstalling the Helm release. Never run both managers against the same resources.

## Update the local application image

The local values select `aks-gitops-demo:git-e1f3391`, built from Git revision `e1f3391` using the Alpine runtime. The application version remains `0.1.0`; an image build tag and the HTTP application version identify different things.

Build from the recorded source revision in a clean checkout and load the image before syncing:

```powershell
git rev-parse --short HEAD
docker build --pull -t aks-gitops-demo:git-e1f3391 .
kind load docker-image aks-gitops-demo:git-e1f3391 --name aks-gitops
```

The source checkout for these build commands must be revision `e1f3391`. Do not reuse this tag for a later build from different source; assign a new tag and update local values for subsequent changes. Package repositories and transitive Python dependencies are not fully locked, so this source tag is not an immutable image digest.

After the local-values change is merged into `main`, refresh the Argo CD Application and review the Deployment image change. Select a manual Sync without prune or force. The new image reference triggers a rolling update. Then check:

```powershell
kubectl --context kind-aks-gitops -n demo-app rollout status deployment/demo-app --timeout=60s
kubectl --context kind-aks-gitops -n demo-app get pods
kubectl --context kind-aks-gitops -n argocd get application demo-app
```

The Alpine image was validated in a temporary pod in the existing kind cluster with the Deployment's security settings, resources, and probes. It became ready without restarts; all three endpoints returned the expected HTTP 200 JSON. The test pod was removed. This evidence precedes the permanent Argo CD rollout and does not establish that the deployment already uses the new image.

## Inspect

```powershell
kubectl --context kind-aks-gitops -n argocd get application demo-app
kubectl --context kind-aks-gitops -n argocd get pods
kubectl --context kind-aks-gitops -n demo-app get pods,services
```

`Synced` means the compared resources match Git; `Healthy` describes their runtime health. These are separate states. The Git revision being compared is available in the Application status. A new image alone does not change Git or trigger a deployment.

## Limits

The official installation grants broad Kubernetes cluster permissions to Argo CD. The [local security overlay](local-security.md) narrows controller writes to the demo-app namespace and server access to read-only application inspection. Apply the overlay after the upstream installation. AppProject restrictions are additional policy and do not replace Kubernetes RBAC. The local default admin account is used initially; SSO and production hardening are not implemented.

Argo CD 3.5's documented test matrix includes Kubernetes 1.33 through 1.36. This existing kind cluster uses Kubernetes 1.37, so successful local checks do not establish officially tested compatibility. The application NetworkPolicy has been tested on the existing kind network; see [the results and boundaries](local-security.md). Upstream Argo CD policies were not individually validated.

Automatic synchronization, drift/self-heal testing, and Azure deployment remain unverified. A subsequent manual version update and Git-revert rollback are documented in [the validation evidence](gitops-validation.md).

## Validation evidence

The local bootstrap was checked with Argo CD v3.5.3 on kind Kubernetes v1.37.0. All Argo CD pods became ready. Server-side dry runs accepted the AppProject and Application. The controller successfully read and rendered Git revision `2139fc0401784cb87407fc79ed92cc60923eba4f`, reporting `Healthy` and `OutOfSync` while the original Helm release remained deployed. The UI returned HTTP 200 through a temporary loopback HTTPS port-forward.

A subsequent ownership transition removed the Helm release and requested one manual Argo CD sync to Git revision `2139fc0401784cb87407fc79ed92cc60923eba4f`. The operation completed with `Succeeded`; the Application reported `Synced` and `Healthy`. The replacement pod was `1/1 Ready` with zero restarts. All three endpoints returned expected HTTP 200 responses through service DNS/ClusterIP, non-root execution and absence of the API token were confirmed, and `helm list` showed no application release. Automatic sync, self-heal, and pruning remain disabled.

The subsequent Alpine deployment and version rollback completed successfully; see [the recorded revisions, results, and limits](gitops-validation.md).

## Helm chart reference

This chart renders a Deployment, a ClusterIP Service, a dedicated ServiceAccount, and an optional NetworkPolicy. The namespace and its Pod Security labels are managed separately. No Helm release is installed by the validation commands below.

### Configuration

| Value | Purpose | Default |
| --- | --- | --- |
| `replicaCount` | Desired pod count | `1` |
| `image.repository` | Container image repository | `aks-gitops-demo` |
| `image.tag` | Container image tag | `0.1.0` |
| `image.pullPolicy` | Registry pull behavior | `IfNotPresent` |
| `appVersion` | Value exposed through `APP_VERSION` | `0.1.0` |
| `resources` | CPU and memory requests and limits | Initial values from the local manifests |

`environments/local/values.yaml` selects the tested image tag `git-e1f3391` and overrides the image pull policy to `Never` for images loaded directly into kind. See [the local image update procedure](#update-the-local-application-image). A future AKS configuration must supply a registry image; no AKS configuration is included yet.

`Chart.yaml` version identifies the chart package. Its `appVersion` field documents the application version; it does not select the image or set `APP_VERSION`. Those settings are explicit values above.

Resource names use the release name. Deployment and Service selectors include the release instance label so separate releases do not select each other's pods. HTTP port 8000, health probes, and container security settings remain fixed for this application.

### Validate without installing

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

### Existing local deployment

The manifests in `environments/local/deployment.yaml` and `service.yaml` preserve the initial kubectl deployment step. A Helm release was used to validate this chart locally, then removed during the transition to [Argo CD](#install-and-bootstrap). The local application is now managed by Argo CD. Do not install or upgrade a Helm release against those same resources, or apply the old kubectl manifests over them.

A Helm installation requires an explicit transition: remove the old application Deployment and Service, keep the namespace, and install the chart as a Helm release. This causes a brief interruption with a single replica. The chart changes the Deployment selector to include the release instance; that selector cannot be changed in place. Adoption of the existing resources is not used.

Local validation covered chart linting, rendering, server-side dry runs, Helm installation, pod readiness, all three endpoints through the internal service, non-root execution, and absence of a mounted API token. Helm upgrade and rollback remain unverified. No load testing or failure scenarios are included.

### Standalone Helm installation into an empty application namespace

After creating the namespace with `environments/local/namespace.yaml` and loading the image into kind, install only if no conflicting application Deployment or Service exists:

```powershell
helm install demo-app charts/demo-app --kube-context kind-aks-gitops --namespace demo-app -f environments/local/values.yaml --wait --timeout 60s --rollback-on-failure
```

These flags use Helm 4.3.0. `--wait` waits for readiness; `--rollback-on-failure` removes the failed installation. This does not restore resources that were removed before installation.

### Inspect a standalone Helm release

```powershell
helm status demo-app --kube-context kind-aks-gitops -n demo-app
helm history demo-app --kube-context kind-aks-gitops -n demo-app
kubectl --context kind-aks-gitops -n demo-app get pods,services,serviceaccounts
kubectl --context kind-aks-gitops -n demo-app port-forward --address 127.0.0.1 service/demo-app 8000:8000
```

A successful initial installation reports `deployed` and revision `1`. Stop port-forward with Ctrl+C; the release continues running.

### Network isolation

The optional NetworkPolicy is disabled by default and enabled in local values. It denies application egress and permits TCP 8000 only from same-namespace pods labelled `access: demo-app`. A policy-capable network is required; see [local enforcement tests and limitations](local-security.md). Other environments must enable and test the policy explicitly.
