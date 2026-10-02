# Local security controls and validation

Validated on 2026-10-02 against kind Kubernetes v1.37.0 and Argo CD v3.5.3. These controls narrow application traffic and controller privileges; they do not establish complete host or cluster isolation.

## Application network policy

The Helm chart renders a NetworkPolicy when `networkPolicy.enabled` is true. The local values enable it. The policy selects the release's application pods, denies new outbound connections, and permits inbound TCP 8000 only from pods in the same namespace carrying `access: demo-app`.

The current application needs no DNS, Internet, or Kubernetes API access. Replies to allowed inbound connections remain permitted. Kubernetes node-originated health probes are not a test of pod-to-pod isolation. Port-forward uses a different path and is not evidence of NetworkPolicy enforcement.

The inspected network daemon was `kindest/kindnetd:v20260820-69b56db7`. Enforcement was established experimentally rather than inferred from the daemon name:

- An isolated test pod connected to the application service before an egress-deny policy, then timed out after the policy was installed.
- With the application policy applied temporarily, a labelled client received expected HTTP 200 JSON from all three endpoints through service DNS.
- An unlabelled client connected to the application Pod IP before the policy and timed out afterward.
- The application connected to the Kubernetes API service TCP port before the policy and timed out afterward. No credentials were sent.
- The application remained ready with zero restarts during inspection. Temporary client pods and validation policies were removed.

The permanent chart policy is prepared for deployment through a merged Git change and manual Argo CD sync. It was not left applied outside Git. The tests cover same-node IPv4 traffic in this cluster, not every CNI/version, host-originated traffic, established connections, or cross-node paths. Repeat validation in AKS. Anyone allowed to create or label pods in the namespace can select the permitted client label; this is a network selector, not an authenticated identity.

## Argo CD Kubernetes privileges

`gitops/local/rbac.yaml` grants the application-controller write access to Deployments, Services, ServiceAccounts, and NetworkPolicies only in `demo-app`. It grants read access to relevant runtime children there. The server has read access and pod-log access in that namespace, with no direct resource-write or exec permission there.

The two upstream ClusterRoles are replaced with narrow rules: get the named `demo-app` namespace, plus controller SelfSubjectAccessReview creation. Existing ClusterRoleBindings now refer to those reduced rules. A credential-free in-cluster registration restricts cache scope to `demo-app` with cluster-resource management disabled. `resource.respectRBAC: strict` tells the controller to skip resources it cannot list; Kubernetes RBAC is the enforcement boundary.

Existing roles in `argocd` remain necessary for managing Applications, AppProjects, configuration, and connection secrets. The server can still request synchronization through Application operations. The default admin account and other upstream components remain; this is not comprehensive Argo CD least-privilege hardening. A controller allowed to edit workloads can influence code running in `demo-app`, so the Pod Security controls and absence of privileged service-account grants still matter.

Observed authorization results:

| ServiceAccount | Action | Namespace | Result |
| --- | --- | --- | --- |
| application-controller | create Deployment | demo-app | allowed |
| application-controller | create Deployment | kube-system | denied |
| application-controller | create RoleBinding | demo-app | denied |
| application-controller | get Secret | demo-app | denied |
| server | get pod logs | demo-app | allowed |
| server | get Secret | kube-system | denied |

A subsequent manual sync of the existing merged revision completed with `Succeeded`; Argo CD remained `Synced` and `Healthy`. It validates reconciliation of the current Deployment, Service, and ServiceAccount, not every future chart resource or UI action. The NetworkPolicy permission was separately checked by schema and admission validation.

## Bootstrap and recovery

After installing the pinned upstream Argo CD manifest and provisioning both namespaces, apply:

```powershell
kubectl --context kind-aks-gitops apply -f gitops/local/rbac.yaml
kubectl --context kind-aks-gitops -n argocd patch configmap argocd-cm --type merge --patch-file gitops/local/rbac-config.patch.yaml
kubectl --context kind-aks-gitops apply -f gitops/local/project.yaml -f gitops/local/application.yaml
kubectl --context kind-aks-gitops -n argocd rollout restart statefulset/argocd-application-controller
kubectl --context kind-aks-gitops -n argocd rollout status statefulset/argocd-application-controller --timeout=60s
```

Reapplying the upstream installer restores its broad ClusterRole rules; always reapply this overlay afterward. It is maintained separately from the application chart and does not grant Argo CD permission to manage its own RBAC. A temporary local copy of the original non-secret ClusterRoles was saved before testing, for immediate recovery if required; it is not a credential backup or a repository artifact.

For future in-cluster HTTP checks, use a restricted temporary client pod with `access: demo-app`. Do not test service connectivity from the application pod itself: its egress is intentionally denied. Keep allowed-client selection and namespace scope explicit when adding an ingress controller or another caller.
