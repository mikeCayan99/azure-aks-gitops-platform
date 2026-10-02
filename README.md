# Azure AKS GitOps Platform

Locally validated GitOps platform with FastAPI, Helm, Argo CD, and automated security checks. Azure AKS infrastructure is defined in Terraform and checked through a successful Azure-authenticated plan.

## Delivered capabilities

- Containerized FastAPI application with version, liveness, and readiness endpoints.
- Kubernetes manifests and a Helm chart with health probes, resource limits, and restricted container settings.
- Manual Argo CD synchronization with verified version rollout and Git-revert rollback in kind.
- Tested application network isolation and a namespace-scoped local Argo CD RBAC overlay.
- Four GitHub Actions jobs covering application/image tests and vulnerability scanning, Helm validation, secret scanning, and Terraform validation.
- Terraform configuration for AKS, ACR, managed identities, and scoped role assignments; an Azure-authenticated plan completed successfully.

## Architecture and execution model

| Component | Responsibility |
| --- | --- |
| Terraform on the operator's computer | Defines and, when explicitly applied, creates or destroys Azure infrastructure. |
| GitHub | Stores application code, Terraform, Helm configuration, and validation evidence. |
| GitHub Actions | Validates changes without Azure access or image publishing. |
| Argo CD in the Kubernetes cluster | Reads the Helm configuration from Git and deploys it after a manual sync. |
| Application | Runs in the local kind environment used for validation; AKS deployment is prepared separately. |

For a future Azure integration, the operator would upload the image to ACR using their own Azure CLI identity. No GitHub Azure credentials or GitHub OIDC integration are required by the current workflow. See the [Azure execution workflow](docs/azure-workflow.md).

## Validation evidence

Local deployment, synchronization, version change, and rollback are documented in [GitOps validation](docs/gitops-validation.md). The local application image passed the strict HIGH/CRITICAL vulnerability gate and HTTP tests. Scan results describe the database snapshot at test time, not a permanent vulnerability-free guarantee. See [CI checks and image investigation](docs/ci.md) and [local security validation](docs/local-security.md).

On 2026-10-02, Terraform produced a successful Azure-authenticated plan in West Europe: six resources to create, zero changes, and zero deletions. The plan included Kubernetes 1.36.3, two Standard_E4bs_v5 system nodes, ACR Basic, and scoped operator and image-pull role assignments. AKS Run Command was explicitly disabled. The plan and local input file are excluded from Git.

Validation boundaries: application deployment and runtime security were tested in kind. Azure apply/destroy, image publishing to ACR, and application deployment on AKS have not been performed. Successful planning does not prove Azure capacity, creation permissions, or runtime integration.

## Reproduce and review

Use the [local GitOps setup](gitops/local/README.md), [Helm chart instructions](charts/demo-app/README.md), and [Terraform runbook](infrastructure/azure/README.md) to reconstruct the environment. Choose current supported versions and review permissions and costs before any Azure deployment. Changes use feature branches, pull requests, and the four CI checks before merging into main.

Credentials, kubeconfig files, Terraform inputs, state, and saved plans must remain outside Git. The checked-in Terraform example contains placeholders only.

## Security and cost controls

Local validation covers non-root containers, dropped capabilities, read-only root filesystems, resource limits, probes, network policies, and reduced Argo CD workload permissions. Azure settings include Entra authentication, disabled local cluster accounts and Run Command, an operator IP allowlist, and registry-scoped AcrPull. Azure runtime behavior remains unverified.

AKS Free tier removes the cluster-management fee; compute, disks, registry, and networking can still incur charges. Any future Azure test needs a reviewed plan, a defined cleanup window, and verified deletion. The approximately EUR 20 expenditure target is not a spending cap. The cleanup deadline tag does not delete resources automatically. This project has not created Azure resources.

## Optional extensions

Prometheus/Grafana metrics, HTTP availability and latency probes, and a tested alert would extend observability. Current health endpoints and Kubernetes probes provide health checking; they are not a complete monitoring stack. Azure runtime validation and automated image publishing are also possible extensions.
