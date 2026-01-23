#!/usr/bin/env sh
# Deletes the local cluster. Nothing outside kind is touched, and no state is
# kept between runs: the whole platform is reproducible from git.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

CLUSTER_NAME="${CLUSTER_NAME:-platform}"

have kind || fail "kind is required for 'make down'"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    log "deleting kind cluster '$CLUSTER_NAME'"
    kind delete cluster --name "$CLUSTER_NAME"
else
    log "no kind cluster named '$CLUSTER_NAME', nothing to do"
fi
