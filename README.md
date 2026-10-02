# Azure AKS GitOps Platform

Reproducible Azure Kubernetes infrastructure and GitOps application delivery with Terraform, Helm, and Argo CD.

## Status

Implemented and locally validated: a containerized FastAPI application, Kubernetes Deployment and Service manifests, and a Helm chart deployed in kind with health probes and restricted container settings. Argo CD was installed locally and a manual synchronization completed with `Synced` and `Healthy`; see [the local GitOps setup](gitops/local/README.md). See [the Helm chart documentation](charts/demo-app/README.md) for commands and validation limits. The first [CI run](docs/ci.md) passed application, Helm, and secret checks but failed the Debian image scan. The revised Alpine runtime passed GitHub Actions validation, including the strict HIGH/CRITICAL scan, and was deployed locally through Argo CD. A version update and Git-revert rollback were verified; see [the validation evidence](docs/gitops-validation.md). An [Azure Terraform baseline](infrastructure/azure/README.md) is prepared and locally schema-validated; no Azure plan or deployment has been performed. Infrastructure operations are performed locally using the operator's Azure CLI identity; see the [Azure execution workflow](docs/azure-workflow.md). Azure image publishing and deployment remain untested; Argo CD synchronization is manual.

## Architecture and execution model

- Terraform is executed on the operator's computer to provision and destroy Azure infrastructure and resource permissions.
- GitHub Actions validates changes and scans container images without Azure access. For Azure integration, the operator builds and uploads the image to Azure Container Registry using their own Azure CLI identity.
- Helm defines application resources and environment-specific configuration.
- Reviewed Git changes specify the desired image digest and application configuration.
- Argo CD runs inside the Kubernetes cluster and applies the desired state from Git after a manual synchronization.

Local validation uses kind with Docker Desktop. Azure integration uses temporary AKS deployments.

## Security and cost controls

Local controls include non-root containers, resource limits, health probes, strict container scanning, and tested application network isolation. A local Argo CD RBAC overlay restricts workload management to the demo-app namespace; see [security validation and limits](docs/local-security.md). Azure identity and networking controls remain unverified until deployment.

Any Azure deployment is a separately approved, temporary integration session, followed by verified deletion before ending the session. The target total Azure expenditure is approximately EUR 20. Azure budgets provide alerts, not a spending cap.

Credentials, kubeconfig files, Terraform state, and plan files must not be committed.

## Development workflow

Changes follow a branch and pull request workflow with local validation, CI checks, and review before merging into main. The initial repository baseline is reviewed before its first commit.

## Planned milestones

1. Repository baseline and local prerequisites.
2. Application deployment and Kubernetes fundamentals.
3. Helm chart and release validation.
4. Argo CD reconciliation and GitOps recovery.
5. Security controls and CI validation.
6. Terraform infrastructure and Azure integration checks.
7. Operational runbooks, deployment evidence, and cost review.
