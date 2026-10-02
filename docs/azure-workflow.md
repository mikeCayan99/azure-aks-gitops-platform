# Azure execution workflow

## Current validation status

The application, Helm deployment, Argo CD manual synchronization, version rollout, rollback, and local security controls have been tested in kind. The Azure Terraform configuration has passed formatting and provider-schema validation, including GitHub CI. No Azure-authenticated plan, apply, image publishing, or application deployment on AKS has been performed.

## Responsibilities

| Component | Execution location and responsibility |
| --- | --- |
| Terraform | Runs on the operator's computer using their Azure CLI login; manages Azure infrastructure and resource permissions. |
| GitHub | Stores application code, Terraform, Helm configuration, and validation evidence. |
| GitHub Actions | Runs four CI jobs: application/image, Helm, secret scan, and Terraform validation. No Azure authentication or deployment. |
| Container image publishing | For an approved Azure test, the operator builds the image locally and uploads it to ACR using their Azure CLI login. This step is not yet validated. |
| Argo CD | Runs in the target Kubernetes cluster, reads the repository, and deploys the application after manual synchronization. Tested in kind; not yet installed on AKS. |
| Application | Runs in kind today; an approved Azure integration would run it on AKS. |

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

Detailed Terraform commands and cleanup checks are in the [existing infrastructure runbook](../infrastructure/azure/README.md). No automatic deletion is configured. The cleanup deadline tag is informational, and the approximately EUR 20 target is not a spending cap. Local kind cleanup and Azure deletion are separate operations.

If the Azure test is not performed, retain the explicit validation limitation above. Do not describe the infrastructure as deployed or runtime-tested on Azure based only on CI validation.
