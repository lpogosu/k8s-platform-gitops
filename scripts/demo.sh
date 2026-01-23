#!/usr/bin/env sh
# Sends one request through the ingress controller to the demo workload and
# prints what came back. Used as a smoke test after `make up`.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

HOST="${DEMO_HOST:-demo.dev.localtest.me}"
NAMESPACE="${DEMO_NAMESPACE:-demo-dev}"

have kubectl || fail "kubectl is required for 'make demo'"
have curl || fail "curl is required for 'make demo'"

log "waiting for the demo deployment in namespace $NAMESPACE"
if ! kubectl -n "$NAMESPACE" rollout status deployment/demo-app --timeout=180s; then
    fail "demo-app is not ready; check 'kubectl -n argocd get applications'"
fi

log "GET http://$HOST/"
code=$(curl -s -o /tmp/demo-response.json -w '%{http_code}' --max-time 10 "http://$HOST/")

if [ "$code" != "200" ]; then
    fail "ingress returned HTTP $code (expected 200); is ingress-nginx healthy?"
fi

echo
cat /tmp/demo-response.json
echo
echo
log "HTTP $code from http://$HOST/"
