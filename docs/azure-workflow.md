# Azure execution workflow

## Current validation status

The application, Helm deployment, Argo CD manual synchronization, version rollout, rollback, and local security controls have been tested in kind. The Azure Terraform configuration has passed formatting and provider-schema validation, including GitHub CI. On 2026-10-02, an Azure-authenticated plan completed successfully with six resources to create, zero changes, and zero deletions. It selected Kubernetes 1.36.3 and two Standard_E4bs_v5 nodes in West Europe, with AKS Run Command disabled. No apply, destroy, image publishing, or application deployment on AKS has been performed.

## Responsibilities

| Component | Execution location and responsibility |
| --- | --- |
| Terraform | Runs on the operator's computer using their Azure CLI login; manages Azure infrastructure and resource permissions. |
| GitHub | Stores application code, Terraform, Helm configuration, and validation evidence. |
| GitHub Actions | Runs four CI jobs: application/image, Helm, secret scan, and Terraform validation. No Azure authentication or deployment. |
| Container image publishing | For an approved Azure test, the operator builds the image locally and uploads it to ACR using their Azure CLI login. This step is not yet validated. |
| Argo CD | Runs in the target Kubernetes cluster, reads the repository, and deploys the application after manual synchronization. Tested in kind; not yet installed on AKS. |
| Application | Validated in kind; an approved Azure integration would run it on AKS. |

Starting Terraform locally does not make AKS local: applying the configuration provisions resources in Azure. GitHub does not execute infrastructure changes in this model. The previous manual Terraform deployment workflow and its helper scripts have been removed to keep one execution path.

## Credentials and state

No GitHub Azure secrets, variables, OIDC trust, or deployment environments are needed for the current CI workflow. The operator authenticates locally through Azure CLI and explicitly selects the intended tenant and subscription before any Azure plan. Local login permissions must cover the intended resource operations and role assignments; Contributor alone does not grant role-assignment permissions. Review permissions before execution rather than granting broad roles automatically.

Copy the existing example inputs to the ignored `infrastructure/azure/terraform.tfvars`, then fill in the approved identifiers, naming, public IP, region, supported Kubernetes patch version, and cleanup deadline. Do not put passwords or client secrets in this file. State and saved plans can contain sensitive information: keep them locally protected and outside Git. Preserve state until destruction has completed and deletion is verified.

AKS managed identities, its OIDC issuer, and workload identity are independent of GitHub OIDC. The existing Terraform configuration retains these AKS settings and grants the kubelet identity registry-scoped AcrPull access. It does not create a GitHub publishing identity.

## Optional Azure integration session

1. Review expected costs, available time, subscription, regional Kubernetes version, VM availability, quota, and provider registrations. Do not start a paid deployment without time to finish cleanup.
2. Authenticate locally, prepare ignored input values, and create a saved Terraform plan. Review resources, role assignments, scope, and the deletion procedure before applying.
3. Apply the reviewed plan locally only after explicit approval. Build and upload the application image, configure restricted AKS access, install Argo CD, and select Azure-specific Helm values. Those deployment steps still require implementation and testing; the local values file must not be reused without review.
4. Test endpoints, Argo CD synchronization, and the intended security controls. Record results and revision identifiers without credentials.
5. Generate and review a destroy plan, apply it locally, then confirm empty Terraform state and absence of both project resource groups. A failure or closed terminal is not proof of deletion.

The configuration details, Terraform commands, and verified-cleanup procedure follow below. The cleanup deadline tag is informational; local kind cleanup and Azure deletion are separate operations.

If the Azure test is not performed, retain the explicit validation limitation above. Do not describe the infrastructure as deployed or runtime-tested on Azure based only on CI validation.

## Design and boundaries

- Two system nodes, no autoscaling, managed 64 GiB OS disks. The reusable default is `Standard_D4s_v5`; the successful plan used `Standard_E4bs_v5` because the selected subscription had no DSv5-family quota. Current [AKS system-pool requirements](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) specify at least two nodes and four vCPUs per node. SKU availability and quota require preflight checks.
- AKS [Free tier](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers) removes the cluster-management fee; nodes, disks, outbound load balancer/public IP, registry, storage, and network traffic remain chargeable. The planning session compared public VM prices; review all billable components before applying.
- Managed control-plane identity; `AcrPull` is scoped to the registry and assigned to the kubelet identity. Registry permission mode is explicitly legacy RBAC, matching this role. Registry admin credentials are disabled.
- Entra authentication and Azure Kubernetes RBAC; local admin accounts and AKS Run Command disabled. The named operator receives cluster-user credential access and Kubernetes cluster-admin authorization on this cluster only. kubelogin is needed for Entra-based kubectl access. These permissions are intentionally broad inside this temporary cluster for bootstrap; workload-specific delegation is not implemented.
- Public Kubernetes API restricted to explicit operator IPv4 /32 CIDRs. The Basic registry has a public authenticated endpoint; private registry networking is not implemented.
- Azure CNI overlay with Cilium. This selects a policy-capable data plane; application NetworkPolicies must still be written and tested. No network-isolation claim is made.
- AKS OIDC issuer and workload identity are enabled for potential in-cluster workloads. This is independent of GitHub authentication: no GitHub federated credential or publishing identity is provisioned. Terraform is executed locally with the operator's Azure CLI identity; see the [execution workflow](#responsibilities).
- Provider auto-registration disabled. Confirm Microsoft.ContainerService, Microsoft.ContainerRegistry, Microsoft.Compute, Microsoft.Network, and Microsoft.ManagedIdentity are registered before planning. Registration is a separate subscription operation.
- Local state is used for this single-operator session. State and plans can contain sensitive data and must remain outside Git. Keep state until destroy completes. No kubeconfig is exported through Terraform outputs.

## Prepare and plan

Copy `terraform.tfvars.example` to the ignored `terraform.tfvars` and replace every placeholder. Confirm the intended subscription, tenant, operator object ID, globally unique registry name, public operator IP, region, exact available GA Kubernetes patch version, and cleanup deadline. Do not commit real input files or credential outputs.

Use a clean, dedicated resource group and node resource group. Do not import or reuse unrelated resources. Before a cloud plan, verify login and subscription, supported Kubernetes versions, regional SKU restrictions, vCPU quota, and the current hourly price of every billable component. Reserve enough budget and time for creation, testing, and deletion. No spending cap or automatic deletion is configured.

From the repository root:

```powershell
terraform '-chdir=infrastructure/azure' init -lockfile=readonly
terraform '-chdir=infrastructure/azure' fmt -check
terraform '-chdir=infrastructure/azure' validate
terraform '-chdir=infrastructure/azure' plan '-out=integration.tfplan'
```

Read the full plan and confirm only the intended project resources are created. A plan does not create the resources, but uses Azure authentication and reads provider data. Review the costs and deletion procedure before any apply. Applying is a separate, explicit approval step:

```powershell
terraform '-chdir=infrastructure/azure' apply integration.tfplan
```

Image publishing, AKS credentials, Argo CD bootstrap, application values, and deployment are subsequent steps; this configuration alone does not deploy the demo application.

## Destroy and verify before ending the session

The `CleanupDeadline` tag is informational. Neither tags nor Azure budgets delete resources or stop charges. Stopping Docker or closing a terminal does not stop Azure resources.

Keep the same state, input values, and subscription. Record the two project resource-group names before deletion:

```powershell
$platformGroup = terraform '-chdir=infrastructure/azure' output -raw resource_group_name
$nodeGroup = terraform '-chdir=infrastructure/azure' output -raw node_resource_group_name
terraform '-chdir=infrastructure/azure' plan -destroy '-out=destroy.tfplan'
terraform '-chdir=infrastructure/azure' apply destroy.tfplan
terraform '-chdir=infrastructure/azure' state list
az group exists --name $platformGroup --subscription YOUR_SUBSCRIPTION_ID
az group exists --name $nodeGroup --subscription YOUR_SUBSCRIPTION_ID
```

Review the destroy plan before applying it. Expect empty Terraform state and `false` for both group-existence checks. Command or authentication failures are not evidence of deletion. Inspect any retained disks, public IPs, registry resources, or other project resources if deletion fails or groups remain. Do not delete the state or declare cleanup complete while Azure resources remain. Cost reporting may arrive after deletion for usage already incurred.

Only after verified cloud cleanup, remove temporary kubeconfig entries/files, saved plans, local kind resources, and project images as appropriate. Preserve repository source and validation documentation for reconstruction. Check active port-forwards and local containers before finishing. Local cleanup is separate from Azure destroy.
