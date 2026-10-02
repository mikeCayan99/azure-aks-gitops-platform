# Continuous integration

The workflow in `.github/workflows/ci.yaml` runs on pull requests and pushes to `main`. It validates changes without publishing images, deploying resources, or accessing Azure.

## Checks

- Application and image: build the Docker image (including Python dependency compatibility verification before removing pip), and run two HTTP test scenarios covering all three endpoints with both the default version and an explicit `APP_VERSION`. Tests run inside the non-root image with no external network, a read-only root filesystem, dropped capabilities, and no privilege escalation.
- Image scan: export the built image to an archive and scan operating system and Python packages with Trivy 0.75.0. Any HIGH or CRITICAL finding fails the job, including findings without an available fix. No ignore list or failure suppression is configured. The scanner reads the archive without access to the Docker socket.
- Helm: download Helm 4.3.0, verify its archive against a fixed SHA-256 checksum, lint chart defaults and local values, and render both configurations. These checks do not create a cluster or validate runtime Kubernetes behavior.
- Secret scan: Gitleaks 8.30.1 scans all fetched Git history and checked-out files. Output is redacted; any finding fails the job. A successful scan is not proof that every possible secret has been excluded.

## Permissions and dependencies

Jobs run on GitHub-hosted Ubuntu 24.04 runners with `contents: read`. Checkout does not persist credentials. There is no `pull_request_target` trigger, registry login, Azure login, or repository secret passed to application code. Full history is fetched only for the secret scan.

The checkout action is pinned to a full commit SHA. Scanner images are pinned to immutable digests. Review these pins when updating tool versions. Helm's archive checksum is fixed in the workflow. The Python base image is pinned to a digest. Operating system package updates and transitive application dependencies are not fully locked, and vulnerability databases change over time.

Timeouts bound job runtime and newer runs cancel older runs for the same ref. CI status checks do not prevent merging until repository branch protection or rulesets require them; that configuration is not included here.

## Local validation

The image build, dependency check, both HTTP test scenarios, both Helm lint/render configurations, and Gitleaks history/file scans passed locally. Actionlint 1.7.12 accepted the workflow syntax and shell commands. No GitHub Actions run has been verified yet.

The first local Trivy scan failed, as the configured gate requires: the current Python slim Bookworm image contained 63 HIGH/CRITICAL operating system package findings and four Python package findings. The four Python findings concern pip-bundled msgpack and urllib3, plus a setuptools entry in pip's internal vendor metadata. These are not direct FastAPI/Uvicorn dependencies. The actual msgpack and urllib3 directories and pip's vendor list were inspected; no separately installed or importable setuptools distribution was found. The scan report is a temporary local output and is not committed.

The image scan must be addressed before this workflow can pass in GitHub. Several operating system findings have no published fix in the scanned Debian release. The reviewed runtime image improvement described below has been implemented and revalidated; the remaining unfixable findings still require assessment. No findings were silently ignored to make the check pass.

## Run the HTTP tests locally

From the repository root in PowerShell:

```powershell
docker build --pull --tag demo-app:ci .
$ciTestsDirectory = Join-Path (Get-Location).Path 'tests'
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$ciTestsDirectory,target=/tests,readonly" --entrypoint python demo-app:ci -m unittest discover -s /tests -v
```

The tests use Python's standard library; no test dependency is installed into the production image. Test files are mounted for execution and remain outside the Docker build context.

## Image investigation

Initial comparison images were built from temporary Dockerfiles. The tested Trixie image improvement was subsequently adopted in the repository Dockerfile. The running Kubernetes workload was not changed.

| Candidate | HIGH/CRITICAL package findings | CRITICAL | Python findings | Findings with a fixed version |
| --- | ---: | ---: | ---: | ---: |
| Existing Python 3.13 slim Bookworm image | 67 | 5 | 4 | 4 |
| Python 3.13 slim Trixie | 49 | 0 | 4 | 5 |
| Trixie with available package updates and pip removed after installation | 44 | 0 | 0 | 0 |

The last candidate passed both HTTP test scenarios under the same restricted container settings. Dependency compatibility was checked during the build before pip was uninstalled. Removing pip eliminates unneeded packaging code from runtime; application dependencies remain installed. The repository Dockerfile now runs `pip check` during the build; the workflow no longer invokes pip in the runtime container.

The original 67 package findings represent 27 unique vulnerability IDs. The final 44 findings represent eight unique IDs repeated across affected binary packages: CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410, CVE-2026-54369, CVE-2025-69720, CVE-2026-16742, and CVE-2026-9538. The scanned database lists no fix version for these remaining Trixie findings; this is not proof of application exploitability or a reason to suppress them automatically.

Debian's tracker confirms that the investigated SQLite [CVE-2025-7458](https://security-tracker.debian.org/tracker/CVE-2025-7458) and Perl [CVE-2026-13221](https://security-tracker.debian.org/tracker/CVE-2026-13221) are fixed in Trixie. It also documents that the Bookworm zlib [CVE-2023-45853](https://security-tracker.debian.org/tracker/CVE-2023-45853) report concerns MiniZip code not built by that source package; package-level scanner severity alone does not establish runtime exposure.

The Trixie base resolved to digest `sha256:bb2988715db2cf7ace7b53f38f3cffbef7c7046a656bee66245eb0ed386e2e81`. Only libpcre2-8-0 required an available Debian update during the final comparison build, upgrading to `10.46-1~deb13u3`. The strict HIGH/CRITICAL gate remains unchanged and would still fail for all comparison images. The final repository image was rebuilt and retested: HTTP tests and dependency compatibility passed; UID 10001 and absence of importable pip were verified; Trivy returned exit code 1 with 44 HIGH Debian findings, zero CRITICAL findings, and zero Python findings. The image improvement is implemented; the remaining findings are assessed separately and still block the strict gate.


The eight remaining CVEs have a [runtime-specific assessment](vulnerability-assessment.md), including evidence and limits. All HIGH/CRITICAL findings remain blocking; no exceptions are configured.

## Distroless comparison

A temporary multi-stage Dockerfile installed binary Python wheels in a Python 3.13 slim Trixie build stage and copied only application dependencies and code into `gcr.io/distroless/python3-debian13:nonroot`, pinned to digest `sha256:774595d652a294b54c9bd575b2d9fdd1a4b47547dc17b8bfa4c0e953c64855b3`. The inspected runtime uses Debian CPython 3.13.5; the build stage uses CPython 3.13.16. Both are CPython 3.13, and the tested dependency imports and HTTP behavior succeeded. Compatibility beyond the tested paths and architecture is not established.

Both HTTP scenarios passed with network isolation, read-only root filesystem, dropped capabilities, and no-new-privileges. UID 10001, absence of importable pip, and absence of `/bin/sh` were confirmed. No requirements or application changes were needed for this comparison.

The unchanged Trivy HIGH/CRITICAL gate returned exit code 1: 26 HIGH package findings, zero CRITICAL findings, and zero Python application-package findings. The HIGH results include libexpat1, ncurses libraries, libuuid1, and Debian Python runtime packages. Four additional Python-runtime CVE IDs (CVE-2026-15308, CVE-2026-19553, CVE-2026-7210, CVE-2026-82049) were reported repeatedly across Debian Python packages. Zero Python application-package findings must not be confused with zero Python interpreter findings.

The candidate was not adopted. It reduces installed tooling but does not satisfy the strict gate, and its different runtime findings require assessment. Repository Dockerfile and Kubernetes workload remained unchanged during this comparison. No vulnerability exceptions were enabled.
