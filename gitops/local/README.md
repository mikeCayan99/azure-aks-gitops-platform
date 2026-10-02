# Local Argo CD bootstrap

Argo CD v3.5.3 uses the official non-HA installation in the existing `aks-gitops` kind cluster. The UI is accessed only through a loopback port-forward. No Azure resources or public application services are created.

## Install and bootstrap

From the repository root in PowerShell:

```powershell
kubectl --context kind-aks-gitops apply -f gitops/local/namespace.yaml
kubectl --context kind-aks-gitops apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml
kubectl --context kind-aks-gitops -n argocd wait --for=condition=Available deployment --all --timeout=120s
kubectl --context kind-aks-gitops -n argocd rollout status statefulset/argocd-application-controller --timeout=120s
kubectl --context kind-aks-gitops apply -f gitops/local/project.yaml -f gitops/local/application.yaml
```

The bootstrap files are applied explicitly with kubectl; Argo CD does not manage its own installation or Application definition in this setup. No vendored upstream installation manifest is committed.

The Application reads `charts/demo-app` from the public repository's `main` branch and uses `environments/local/values.yaml`. No Git credentials are required. Local uncommitted chart changes are not read by Argo CD. Keep the Application name and Helm rendering release name `demo-app` aligned with the chart's instance labels.

The AppProject permits only this repository, this cluster's `demo-app` namespace, and Deployment, Service, and ServiceAccount resources. The namespace is provisioned separately; the project does not allow cluster-scoped resources.

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

The official installation grants broad Kubernetes cluster permissions to Argo CD. AppProject restrictions narrow application destinations and resource types but are not a replacement for least-privilege Kubernetes RBAC. The local default admin account is used initially; SSO and production hardening are not implemented.

Argo CD 3.5's documented test matrix includes Kubernetes 1.33 through 1.36. This existing kind cluster uses Kubernetes 1.37, so successful local checks do not establish officially tested compatibility. The upstream installation includes NetworkPolicies, but enforcement has not been verified on the default kind network.

Automatic synchronization, drift/self-heal testing, and Azure deployment remain unverified. A subsequent manual version update and Git-revert rollback are documented in [the validation evidence](../../docs/gitops-validation.md).

## Validation evidence

The local bootstrap was checked with Argo CD v3.5.3 on kind Kubernetes v1.37.0. All Argo CD pods became ready. Server-side dry runs accepted the AppProject and Application. The controller successfully read and rendered Git revision `2139fc0401784cb87407fc79ed92cc60923eba4f`, reporting `Healthy` and `OutOfSync` while the original Helm release remained deployed. The UI returned HTTP 200 through a temporary loopback HTTPS port-forward.

A subsequent ownership transition removed the Helm release and requested one manual Argo CD sync to Git revision `2139fc0401784cb87407fc79ed92cc60923eba4f`. The operation completed with `Succeeded`; the Application reported `Synced` and `Healthy`. The replacement pod was `1/1 Ready` with zero restarts. All three endpoints returned expected HTTP 200 responses through service DNS/ClusterIP, non-root execution and absence of the API token were confirmed, and `helm list` showed no application release. Automatic sync, self-heal, and pruning remain disabled.

The subsequent Alpine deployment and version rollback completed successfully; see [the recorded revisions, results, and limits](../../docs/gitops-validation.md).
