#!/usr/bin/env sh
# Rewrites the git remote every Argo CD Application points at.
#
# Argo CD pulls manifests from a repository, not from the working copy on the
# machine that ran `make up`. After forking this repository the URL has to
# change in one place per Application, which is what this script does.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

OLD_URL="https://github.com/lpogosu/k8s-platform-gitops.git"
NEW_URL="${REPO_URL:-}"

[ -n "$NEW_URL" ] || fail "usage: make set-repo REPO_URL=https://github.com/<you>/<repo>.git"

changed=0
for file in "$REPO_ROOT"/argocd/root-app.yaml "$REPO_ROOT"/argocd/apps/*.yaml "$REPO_ROOT"/argocd/projects/*.yaml; do
    grep -q "$OLD_URL" "$file" || continue
    sed "s|$OLD_URL|$NEW_URL|g" "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    changed=$((changed + 1))
    printf '    %s\n' "${file#"$REPO_ROOT"/}"
done

log "rewrote the repository URL in $changed file(s)"
log "commit and push before running 'make up', otherwise Argo CD syncs the old revision"
