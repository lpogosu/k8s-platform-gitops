#!/usr/bin/env sh
# Creates the local cluster and hands it over to Argo CD.
#
# Everything after step 3 is a single `kubectl apply`: the root Application is
# the only object applied imperatively, and it pulls the rest out of git.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

CLUSTER_NAME="${CLUSTER_NAME:-platform}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300s}"

for bin in docker kind kubectl; do
    have "$bin" || fail "$bin is required for 'make up' (see README, Быстрый старт)"
done

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    log "cluster '$CLUSTER_NAME' already exists, reusing it"
else
    log "creating kind cluster '$CLUSTER_NAME' (1 control-plane, 2 workers)"
    kind create cluster --name "$CLUSTER_NAME" --config "$REPO_ROOT/kind/cluster.yaml" --wait 120s
fi

kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

log "installing Argo CD from argocd/install"
kubectl apply -k "$REPO_ROOT/argocd/install" --server-side --force-conflicts

log "waiting for the Application CRD to be established"
kubectl wait --for=condition=Established --timeout=120s \
    crd/applications.argoproj.io crd/appprojects.argoproj.io

log "waiting for the Argo CD control plane (up to $WAIT_TIMEOUT)"
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout="$WAIT_TIMEOUT"
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout="$WAIT_TIMEOUT"
kubectl -n argocd rollout status deployment/argocd-server --timeout="$WAIT_TIMEOUT"

# An Application referencing a project that does not exist is rejected, and the
# projects themselves are managed by an Application. This one apply breaks the
# cycle; from here on Argo CD owns them.
log "seeding AppProjects"
kubectl apply -k "$REPO_ROOT/argocd/projects"

log "applying the root Application"
kubectl apply -f "$REPO_ROOT/argocd/root-app.yaml"

cat <<'EOF'

Argo CD is reconciling the platform. Follow it with:

  make status
  make argocd-password
  make port-forward     # then open http://localhost:8080 as user 'admin'

The demo workload answers once ingress-nginx is up:

  make demo

Note: Argo CD syncs from the git remote, not from this working copy. Changes
under deploy/ or charts/ only reach the cluster after they are pushed to the
branch referenced in argocd/root-app.yaml. Use `make set-repo REPO_URL=...`
after forking.
EOF
