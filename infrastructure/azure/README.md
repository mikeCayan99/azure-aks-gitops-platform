# Temporary Azure integration infrastructure

This root configuration defines a dedicated resource group, an AKS Free-tier cluster with two system nodes, an ACR Basic registry, and cluster-scoped operator and registry-pull role assignments. It is prepared for a short integration session, not a continuously running environment.

## Validation status

Terraform 1.15.6 on Windows validated the configuration with AzureRM 5.8.0. Formatting and provider-schema validation passed; the provider lockfile covers Windows and Linux amd64. An Azure-authenticated plan on 2026-10-02 succeeded: six creates, zero changes, and zero deletions, using Kubernetes 1.36.3 and two Standard_E4bs_v5 nodes in West Europe. No apply, destroy, connectivity check, image publishing, or AKS application deployment has been performed. The local kind environment remains separate. The CI workflow includes a Terraform formatting, backend-free initialization, and validation job without Azure authentication; the Terraform CI job has passed on GitHub.

## Design and boundaries

- Two system nodes, no autoscaling, managed 64 GiB OS disks. The reusable default is `Standard_D4s_v5`; the successful plan used `Standard_E4bs_v5` because the selected subscription had no DSv5-family quota. Current [AKS system-pool requirements](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) specify at least two nodes and four vCPUs per node. SKU availability and quota require preflight checks.
- AKS [Free tier](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers) removes the cluster-management fee; nodes, disks, outbound load balancer/public IP, registry, storage, and network traffic remain chargeable. No estimate has yet been established for this subscription and region.
- Managed control-plane identity; `AcrPull` is scoped to the registry and assigned to the kubelet identity. Registry permission mode is explicitly legacy RBAC, matching this role. Registry admin credentials are disabled.
- Entra authentication and Azure Kubernetes RBAC; local admin accounts and AKS Run Command disabled. The named operator receives cluster-user credential access and Kubernetes cluster-admin authorization on this cluster only. kubelogin is needed for Entra-based kubectl access. These permissions are intentionally broad inside this temporary cluster for bootstrap; workload-specific delegation is not implemented.
- Public Kubernetes API restricted to explicit operator IPv4 /32 CIDRs. The Basic registry has a public authenticated endpoint; private registry networking is not implemented.
- Azure CNI overlay with Cilium. This selects a policy-capable data plane; application NetworkPolicies must still be written and tested. No network-isolation claim is made.
- AKS OIDC issuer and workload identity are enabled for potential in-cluster workloads. This is independent of GitHub authentication: no GitHub federated credential or publishing identity is provisioned. Terraform is executed locally with the operator's Azure CLI identity; see the [execution workflow](../../docs/azure-workflow.md).
- Provider auto-registration disabled. Confirm Microsoft.ContainerService, Microsoft.ContainerRegistry, Microsoft.Compute, Microsoft.Network, and Microsoft.ManagedIdentity are registered before planning. Registration is a separate subscription operation.
- Local state is used for this single-operator session. State and plans can contain sensitive data and must remain outside Git. Keep state until destroy completes. No kubeconfig is exported through Terraform outputs.

## Prepare and plan

Copy `terraform.tfvars.example` to the ignored `terraform.tfvars` and replace every placeholder. Confirm the intended subscription, tenant, operator object ID, globally unique registry name, public operator IP, region, exact available GA Kubernetes patch version, and cleanup deadline. Do not commit real input files or credential outputs.

Use a clean, dedicated resource group and node resource group. Do not import or reuse unrelated resources. Before a cloud plan, verify login and subscription, supported Kubernetes versions, regional SKU restrictions, vCPU quota, and the current hourly price of every billable component. Reserve enough budget and time for creation, testing, and deletion. The project expenditure target is approximately EUR 20; no spending cap or automatic deletion is configured.

From the repository root:

```powershell
terraform -chdir=infrastructure/azure init -lockfile=readonly
terraform -chdir=infrastructure/azure fmt -check
terraform -chdir=infrastructure/azure validate
terraform -chdir=infrastructure/azure plan -out=integration.tfplan
```

Read the full plan and confirm only the intended project resources are created. A plan does not create the resources, but uses Azure authentication and reads provider data. Review the costs and deletion procedure before any apply. Applying is a separate, explicit approval step:

```powershell
terraform -chdir=infrastructure/azure apply integration.tfplan
```

Image publishing, AKS credentials, Argo CD bootstrap, application values, and deployment are subsequent steps; this configuration alone does not deploy the demo application.

## Destroy and verify before ending the session

The `CleanupDeadline` tag is informational. Neither tags nor Azure budgets delete resources or stop charges. Stopping Docker or closing a terminal does not stop Azure resources.

Keep the same state, input values, and subscription. Record the two project resource-group names before deletion:

```powershell
$platformGroup = terraform -chdir=infrastructure/azure output -raw resource_group_name
$nodeGroup = terraform -chdir=infrastructure/azure output -raw node_resource_group_name
terraform -chdir=infrastructure/azure plan -destroy -out=destroy.tfplan
terraform -chdir=infrastructure/azure apply destroy.tfplan
terraform -chdir=infrastructure/azure state list
az group exists --name $platformGroup --subscription YOUR_SUBSCRIPTION_ID
az group exists --name $nodeGroup --subscription YOUR_SUBSCRIPTION_ID
```

Review the destroy plan before applying it. Expect empty Terraform state and `false` for both group-existence checks. Command or authentication failures are not evidence of deletion. Inspect any retained disks, public IPs, registry resources, or other project resources if deletion fails or groups remain. Do not delete the state or declare cleanup complete while Azure resources remain. Cost reporting may arrive after deletion for usage already incurred.

Only after verified cloud cleanup, remove temporary kubeconfig entries/files, saved plans, local kind resources, and project images as appropriate. Preserve repository source and validation documentation for reconstruction. Check active port-forwards and local containers before finishing. Local cleanup is separate from Azure destroy.
