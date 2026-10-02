# Continuous integration

The workflow in `.github/workflows/ci.yaml` runs on pull requests and pushes to `main`. It validates changes without publishing images, deploying resources, or accessing Azure.

## Checks

- Application and image: build the Docker image (including Python dependency compatibility verification in a separate build stage), and run two HTTP test scenarios covering all three endpoints with both the default version and an explicit `APP_VERSION`. Tests run inside the non-root image with no external network, a read-only root filesystem, dropped capabilities, and no privilege escalation.
- Image scan: export the built image to an archive and scan operating system and Python packages with Trivy 0.75.0. Any HIGH or CRITICAL finding fails the job, including findings without an available fix. No ignore list or failure suppression is configured. The scanner reads the archive without access to the Docker socket.
- Helm: download Helm 4.3.0, verify its archive against a fixed SHA-256 checksum, lint chart defaults and local values, and render both configurations. These checks do not create a cluster or validate runtime Kubernetes behavior.
- Secret scan: Gitleaks 8.30.1 scans all fetched Git history and checked-out files. Output is redacted; any finding fails the job. A successful scan is not proof that every possible secret has been excluded.

- Terraform: install pinned Terraform 1.15.6, check formatting, initialize the locked providers with backend disabled, and validate the configuration. This job does not authenticate to Azure, register resource providers, run plan/apply/destroy, or validate subscription quotas and regional availability.

## Permissions and dependencies

Jobs run on GitHub-hosted Ubuntu 24.04 runners with `contents: read`. Checkout does not persist credentials. There is no `pull_request_target` trigger, registry login, Azure login, or repository secret passed to application code. Full history is fetched only for the secret scan.

The checkout action is pinned to a full commit SHA. Scanner images are pinned to immutable digests. Review these pins when updating tool versions. Helm's archive checksum is fixed in the workflow. The Python base image is pinned to a digest. Operating system package updates and transitive application dependencies are not fully locked, and vulnerability databases change over time.

Timeouts bound job runtime and newer runs cancel older runs for the same ref. CI status checks do not prevent merging until repository branch protection or rulesets require them; that configuration is not included here.

## Local validation

The first GitHub Actions run for pull request #5 passed the container build, both HTTP test scenarios, Helm validation, and secret scans. The image scan completed and failed the strict gate with 44 HIGH Debian package findings and zero CRITICAL or Python-package findings.

The subsequent Alpine runtime image passed the same HTTP tests and strict Trivy gate locally: zero HIGH and CRITICAL findings across 29 operating system packages and 14 Python application packages. The revised image subsequently passed all three GitHub Actions jobs and was deployed through Argo CD in the local kind cluster; see [the deployment and rollback evidence](gitops-validation.md). Scan results are a dated database snapshot, not a guarantee of vulnerability-free software.

## Run the HTTP tests locally

From the repository root in PowerShell:

```powershell
docker build --pull --tag demo-app:ci .
$ciTestsDirectory = Join-Path (Get-Location).Path 'tests'
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$ciTestsDirectory,target=/tests,readonly" --entrypoint python demo-app:ci -m unittest discover -s /tests -v
```

The tests use Python's standard library; no test dependency is installed into the production image. Test files are mounted for execution and remain outside the Docker build context.

## Image investigation

Initial comparison images were built from temporary Dockerfiles. The tested Trixie image improvement was used for the first CI run and subsequently replaced by the Alpine runtime described below. The running Kubernetes workload was not changed.

| Candidate | HIGH/CRITICAL package findings | CRITICAL | Python findings | Findings with a fixed version |
| --- | ---: | ---: | ---: | ---: |
| Existing Python 3.13 slim Bookworm image | 67 | 5 | 4 | 4 |
| Python 3.13 slim Trixie | 49 | 0 | 4 | 5 |
| Trixie with available package updates and pip removed after installation | 44 | 0 | 0 | 0 |

The last candidate passed both HTTP test scenarios under the same restricted container settings. Dependency compatibility was checked during the build before pip was uninstalled. Removing pip eliminates unneeded packaging code from runtime; application dependencies remain installed. The Trixie Dockerfile ran `pip check` during the build; the workflow no longer invokes pip in the runtime container.

The original 67 package findings represent 27 unique vulnerability IDs. The final 44 findings represent eight unique IDs repeated across affected binary packages: CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410, CVE-2026-54369, CVE-2025-69720, CVE-2026-16742, and CVE-2026-9538. The scanned database lists no fix version for these remaining Trixie findings; this is not proof of application exploitability or a reason to suppress them automatically.

Debian's tracker confirms that the investigated SQLite [CVE-2025-7458](https://security-tracker.debian.org/tracker/CVE-2025-7458) and Perl [CVE-2026-13221](https://security-tracker.debian.org/tracker/CVE-2026-13221) are fixed in Trixie. It also documents that the Bookworm zlib [CVE-2023-45853](https://security-tracker.debian.org/tracker/CVE-2023-45853) report concerns MiniZip code not built by that source package; package-level scanner severity alone does not establish runtime exposure.

The Trixie base resolved to digest `sha256:bb2988715db2cf7ace7b53f38f3cffbef7c7046a656bee66245eb0ed386e2e81`. Only libpcre2-8-0 required an available Debian update during the final comparison build, upgrading to `10.46-1~deb13u3`. The strict HIGH/CRITICAL gate remained unchanged and failed for the Debian comparison images. The Trixie image was rebuilt and retested: HTTP tests and dependency compatibility passed; UID 10001 and absence of importable pip were verified; Trivy returned exit code 1 with 44 HIGH Debian findings, zero CRITICAL findings, and zero Python findings. Those findings blocked the Trixie image and are retained below as historical evidence.


The eight remaining CVEs have a [runtime-specific assessment](vulnerability-assessment.md), including evidence and limits. All HIGH/CRITICAL findings remain blocking; no exceptions are configured.

## Distroless comparison

A temporary multi-stage Dockerfile installed binary Python wheels in a Python 3.13 slim Trixie build stage and copied only application dependencies and code into `gcr.io/distroless/python3-debian13:nonroot`, pinned to digest `sha256:774595d652a294b54c9bd575b2d9fdd1a4b47547dc17b8bfa4c0e953c64855b3`. The inspected runtime uses Debian CPython 3.13.5; the build stage uses CPython 3.13.16. Both are CPython 3.13, and the tested dependency imports and HTTP behavior succeeded. Compatibility beyond the tested paths and architecture is not established.

Both HTTP scenarios passed with network isolation, read-only root filesystem, dropped capabilities, and no-new-privileges. UID 10001, absence of importable pip, and absence of `/bin/sh` were confirmed. No requirements or application changes were needed for this comparison.

The unchanged Trivy HIGH/CRITICAL gate returned exit code 1: 26 HIGH package findings, zero CRITICAL findings, and zero Python application-package findings. The HIGH results include libexpat1, ncurses libraries, libuuid1, and Debian Python runtime packages. Four additional Python-runtime CVE IDs (CVE-2026-15308, CVE-2026-19553, CVE-2026-7210, CVE-2026-82049) were reported repeatedly across Debian Python packages. Zero Python application-package findings must not be confused with zero Python interpreter findings.

The candidate was not adopted. It reduces installed tooling but does not satisfy the strict gate, and its different runtime findings require assessment. Repository Dockerfile and Kubernetes workload remained unchanged during this comparison. No vulnerability exceptions were enabled.

## Alpine runtime

The current Dockerfile uses the official Python 3.13 Alpine image pinned to `sha256:2dd78ad5cf13a0b68f5134dc49aa9950203a8cf4b7463431b9f3b398287c5059` in both stages. The inspected runtime is Python 3.13.16 on Alpine 3.24.2. Dependencies are installed from binary wheels into a separate prefix and checked in the build stage. Only that prefix and the application code are copied into runtime. Runtime applies available Alpine package updates, removes pip, and runs as UID/GID 10001.

A simulated Debian package removal could not resolve dependencies because apt and essential command-line tools depend on several flagged libraries. The Alpine candidate instead uses its native package inventory; no package metadata was deleted or scanner findings suppressed. Trivy detected all 29 Alpine packages and all 14 installed Python application distributions and returned exit code 0 with zero HIGH/CRITICAL findings on 2026-10-02.

Alpine uses musl rather than Debian's glibc. The current pydantic-core dependency has a compatible musllinux wheel for the tested linux/amd64 architecture; both HTTP scenarios passed with the existing restrictions. The binary-wheel-only build fails if a future dependency lacks a compatible wheel. Other architectures and future native dependencies require separate validation. A multi-stage build by itself does not eliminate vulnerabilities already present in a runtime base.

The strict scanner policy and workflow remain unchanged. A subsequent local-values change selected the new image and a manual Argo CD sync deployed it to kind. Image builds and CI jobs themselves do not deploy resources.