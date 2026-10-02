# Local GitOps update and rollback validation

Validated on 2026-10-02 in the existing `aks-gitops` kind cluster, using Argo CD v3.5.3 and Kubernetes v1.37.0. Synchronization was manual; automatic sync, self-heal, and pruning remained disabled.

## Verified sequence

| Git revision | Change | Observed result after manual sync |
| --- | --- | --- |
| `7a61caf` | Local image changed to `aks-gitops-demo:git-e1f3391` | Alpine runtime, all three HTTP endpoints returned expected 200 JSON; UID 10001 and absence of the Kubernetes API token verified. |
| `233b457` | Local `appVersion` override set to `0.1.1` | `/version` returned `{"version":"0.1.1"}`; both health endpoints returned expected 200 JSON. |
| `27d33d7` | Revert removed the local version override | `/version` returned `{"version":"0.1.0"}`; both health endpoints returned expected 200 JSON. |

Each synchronization targeted the recorded merged revision and completed with `Succeeded`. Argo CD reported `Synced` and `Healthy`; each resulting application pod was `1/1 Running` with zero restarts at inspection. Requests were sent through `demo-app.demo-app.svc.cluster.local:8000` from the application pod, exercising service DNS and the internal service path.

The version change was commit `7e9c15e`. `git revert --no-commit 7e9c15e` prepared its inverse; the reviewed revert was committed as `ab475fd` and merged through a separate pull request. Git history was preserved. The image reference remained unchanged during the version update and rollback.

## Repeat the procedure

1. Record the current merged Git revision, image, and `/version` response.
2. Change `appVersion` in `environments/local/values.yaml` on a feature branch. Review the rendered Deployment and run CI through a pull request.
3. After merging, refresh Argo CD, review the diff, and manually sync the merged revision without prune or force. Wait for the rollout and verify `/version` and both health endpoints.
4. On a new branch, revert the original version-change commit. Review the inverse change, run CI, and merge the rollback pull request.
5. Manually sync the rollback revision. Verify the restored version, endpoint responses, and Argo CD health and sync status.

For image changes, the selected image must already be available on every target kind node because local values use `imagePullPolicy: Never`. See [the image update procedure](../gitops/local/README.md#update-the-local-application-image).

## Scope and limits

This exercise verifies a configuration rollback using the same image. It does not verify database migrations, restoration of persistent data, rollback to a different image, failed deployment recovery, uninterrupted availability, or production suitability. Zero restarts and endpoint responses are point-in-time observations; no load test or prolonged observation was performed.
