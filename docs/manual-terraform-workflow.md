# Manual Azure Terraform workflow

`.github/workflows/terraform-manual.yaml` is separate from CI. It has only a `workflow_dispatch` trigger and runs only on `main` when the repository variable `TERRAFORM_DISPATCH_ENABLED` equals `true`. Leave that variable unset until the prerequisites below have been reviewed and configured. No Azure deployment has been validated yet.

## Prerequisites before enabling

- Explicitly approve the Azure subscription, expected costs, identity permissions, and same-day cleanup window. A budget sends alerts and is not a spending cap.
- Create a dedicated Azure identity and federated OIDC credentials for both GitHub environments: `repo:mikeCayan99/azure-aks-gitops-platform:environment:azure-plan` and `repo:mikeCayan99/azure-aks-gitops-platform:environment:azure-change`. No client secret is used.
- Review least-privilege Azure permissions for creating the dedicated project resource groups, managing AKS/ACR, and creating the configured role assignments. Contributor alone does not grant role-assignment permissions. Do not grant subscription-wide Owner as a shortcut. Provider registration, regional quota, and Kubernetes version availability require separate checks.
- Bootstrap a dedicated Azure Blob state backend with public access disabled, TLS required, appropriate network controls, and Blob data access for the workflow identity. Record its resource group separately: it is outside this Terraform state and must be removed after project destruction and verification. Backend storage can incur costs.
- Create GitHub environments `azure-plan` and `azure-change`, restricted to `main`. Configure **required reviewers** on `azure-change` before enabling the workflow. If the repository cannot enforce this protection, keep the workflow disabled. Merely naming an environment in YAML does not require approval. Disable protection bypass where supported. With prevent-self-review enabled, a different reviewer must approve.
- Create repository secret `TF_PLAN_ENCRYPTION_KEY` containing a randomly generated strong key of at least 32 characters. Keep it available throughout an apply/destroy run; rotating it between jobs prevents decryption. Saved plans can contain sensitive data: only an encrypted archive is uploaded, retained for one day.

Repository variables required by both jobs:

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | Dedicated workflow identity client ID |
| `AZURE_TENANT_ID` | Approved tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Approved subscription ID |
| `TF_STATE_ACCOUNT`, `TF_STATE_CONTAINER`, `TF_STATE_KEY` | Dedicated backend account, container, and state blob name |
| `TF_OPERATOR_OBJECT_ID` | Approved operator object ID |
| `TF_REGISTRY_NAME` | Globally unique registry name |
| `TF_KUBERNETES_VERSION` | Available exact Kubernetes patch version |
| `TF_API_AUTHORIZED_IP_RANGES` | JSON array of approved public IPv4 /32 CIDRs |
| `TF_NAME_PREFIX` | Project naming prefix, for example `aksgitopsdemo` |
| `TF_LOCATION` | Approved region, for example `westeurope` |
| `TF_NODE_VM_SIZE` | Approved node size, baseline `Standard_D4s_v5` |
| `TERRAFORM_DISPATCH_ENABLED` | Set to `true` only after completing the prerequisites |

## Operations

1. Start the workflow manually from Actions on `main`. Select `plan`, `apply`, or `destroy`. Supply an ISO-8601 UTC cleanup deadline. For apply/destroy also type the exact configured naming prefix as confirmation.
2. `plan` authenticates to Azure and displays the proposed changes without applying them. It still needs the backend and reads Azure. It does not upload a saved plan artifact.
3. `apply` and `destroy` first create and display their respective plans. Inspect that run's plan before approving the waiting `azure-change` environment job. Reject unexpected changes, resource scope, or costs.
4. The approved job decrypts the archive, checks its hash and source commit, and applies that exact saved plan. It does not regenerate a plan after approval. Terraform backend locking and workflow concurrency serialize state changes. If the state changed, generate a new reviewed plan instead of overriding the failure.
5. `destroy` additionally verifies that Terraform state is empty and both the project and AKS node resource groups are absent. A failed run or timeout is not proof of cleanup: investigate and finish deletion before stopping.

Rerun the entire workflow after a failure, rather than only the apply job: artifact names include the run attempt. A separate plan-only run is not reused by a subsequent apply operation; inspect the new plan in the apply run.

The cleanup deadline is a resource tag, **not an automatic deletion timer**. Finish destruction on the same day, then separately remove backend/bootstrap resources and check for any remaining project resources and costs. This workflow does not publish application images or install Argo CD into Azure.

## Local validation

Workflow syntax and inline commands passed actionlint 1.7.12; helper scripts passed ShellCheck. A dummy plan encryption/decryption round trip passed, and an incorrect key and source revision both caused failure. These checks used local containers without Azure credentials. Azure OIDC, backend access, environment approvals, provisioning, and destruction remain untested.
