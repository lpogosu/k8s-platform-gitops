# How sync works

## The loop

Argo CD compares three states, not two:

- **desired** — the manifests produced by rendering a source (`helm template`,
  `kustomize build`, or a plain directory) at the target revision;
- **live** — what the API server currently reports;
- **last applied** — what Argo CD itself put there.

A difference between desired and live makes the Application `OutOfSync`. What
happens next depends on the sync policy:

| Setting | Effect in this repository |
| --- | --- |
| `automated.prune: true` | Deleting a file removes the object. Set on everything except `platform-projects`. |
| `automated.selfHeal: true` | A manual `kubectl edit` is reverted on the next reconcile (60s, see `timeout.reconciliation`). |
| `syncOptions: CreateNamespace=true` | Argo CD creates the destination namespace instead of failing the first sync. |
| `syncOptions: ServerSideApply=true` | Used for cert-manager and sealed-secrets: their CRDs exceed the 262144-byte annotation that client-side apply writes. |
| `syncOptions: PruneLast=true` | On the demo workload, so the namespace is removed after the objects inside it. |
| `retry.backoff` | A component whose dependency is not ready yet fails, backs off, and succeeds on a later attempt rather than needing a human. |

`prune` is deliberately off for `platform-projects`. Pruning an `AppProject`
would orphan every `Application` that references it — including the root
Application, which lives in the `platform` project.

## Sync waves

`argocd.argoproj.io/sync-wave` orders resources inside a sync. Argo CD applies
every resource of wave *N*, waits for all of them to report `Healthy`, and only
then starts wave *N+1*.

| Wave | Application | Why it cannot move earlier |
| --- | --- | --- |
| `-10` | `platform-projects` | Every other Application references a project by name; a missing project makes the Application invalid. |
| `0` | `cert-manager`, `ingress-nginx`, `sealed-secrets`, `metrics-server` | No dependencies between them, so they install in parallel. |
| `1` | `cert-manager-issuers` | A `ClusterIssuer` is rejected by the cert-manager validating webhook until that webhook is serving. |
| `2` | `demo-app-dev` | Its `Ingress` is rejected by the ingress-nginx admission webhook if the controller is not up, and its `Certificate` needs an issuer. |

Waves are why cert-manager and its `ClusterIssuer` are two Applications and not
one. Inside a single Application the CRDs, the controller and the issuer would be
applied in one pass, and the issuer would fail because the webhook that validates
it is still starting. Splitting them lets the wave boundary express "wait until
cert-manager is healthy".

The retry backoff is the safety net rather than the mechanism: a wave that fails
because a dependency was a few seconds late is retried, so the platform converges
on its own instead of needing a manual re-sync.

## What health means here

Wave *N+1* starts when wave *N* is `Healthy`, so the health assessment matters:

- a `Deployment` is healthy when its `.status` shows the updated replicas
  available — which for the demo workload means the readiness probe on `/ping`
  passed;
- a `Certificate` is healthy when cert-manager sets `Ready=True`, so the demo
  workload genuinely waits for its TLS secret;
- a `ClusterIssuer` is healthy when its `Ready` condition is true, which for the
  CA issuer means the CA secret exists.

## Drift and the working copy

Argo CD reconciles the **git remote**, not the checkout on the machine that ran
`make up`. A change under `deploy/` or `charts/` has no effect until it is pushed
to the branch named in `spec.source.targetRevision`. This is the point of the
model — the cluster state is a function of a commit, not of who ran what — but it
is also the first thing that surprises people who expect `make up` to pick up
uncommitted edits. After forking, run:

```sh
make set-repo REPO_URL=https://github.com/<you>/k8s-platform-gitops.git
```

## Secrets

The controller from `sealed-secrets` generates an RSA key pair on first start and
adds a fresh one every 30 days, keeping the old keys so that previously sealed
secrets stay decryptable. Encrypting is a client-side operation against the
public half:

```sh
kubectl create secret generic demo-credentials \
  --namespace demo-dev --dry-run=client -o yaml \
  --from-literal=token=example \
  | kubeseal --controller-namespace sealed-secrets --format yaml \
  > deploy/overlays/dev/demo-credentials.sealed.yaml
```

Only the resulting `SealedSecret` goes into git; `.gitignore` blocks the
intermediate plaintext. The private half never leaves the cluster, which is also
the failure mode to plan for: destroying the `sealed-secrets` namespace makes
every committed `SealedSecret` undecryptable. On a real cluster the sealing keys
are backed up out of band:

```sh
kubectl -n sealed-secrets get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealing-keys.yaml
```

This repository ships no `SealedSecret` of its own — the demo workload has no
credentials — so the controller is here as the pattern, not as decoration.
