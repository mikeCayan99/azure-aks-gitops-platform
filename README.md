# Azure AKS GitOps Platform

Reproducible Azure Kubernetes infrastructure and GitOps application delivery with Terraform, Helm, and Argo CD.

## Status

Implemented and locally validated: a containerized FastAPI application, Kubernetes Deployment and Service manifests, and a Helm chart deployed in kind with health probes and restricted container settings. Argo CD was installed locally and a manual synchronization completed with `Synced` and `Healthy`; see [the local GitOps setup](gitops/local/README.md). See [the Helm chart documentation](charts/demo-app/README.md) for commands and validation limits. A [CI workflow](docs/ci.md) has been prepared and locally validated; its image scan currently fails on identified vulnerabilities and no GitHub Actions run has been verified yet. Azure infrastructure, image publishing, and automated synchronization remain planned.

## Planned architecture

- Terraform provisions Azure infrastructure and resource permissions.
- GitHub Actions validates changes, scans container images, and publishes approved images to Azure Container Registry using OIDC authentication.
- Helm defines application resources and environment-specific configuration.
- Reviewed Git changes specify the desired image digest and application configuration.
- Argo CD reconciles Kubernetes resources with the desired state in Git.

Local validation uses kind with Docker Desktop. Azure integration uses temporary AKS deployments.

## Security and cost controls

Planned controls include narrowly scoped Azure identities, Kubernetes RBAC, non-root containers, resource requests and limits, health probes, enforced network policies, and container scanning.

Azure resources will be provisioned for scheduled integration checks and removed afterward. The target total Azure expenditure is approximately EUR 20. Azure budgets provide alerts, not a spending cap.

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
