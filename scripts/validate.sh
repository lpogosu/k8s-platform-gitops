#!/usr/bin/env sh
# Renders everything this repository can render and checks the result against
# the Kubernetes OpenAPI schemas. This is the same set of checks CI runs, so a
# green run here means a green pipeline.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

BUILD_DIR="$REPO_ROOT/.build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "helm lint charts/demo-app"
tool helm lint --strict charts/demo-app

log "helm template charts/demo-app"
tool helm template demo-app charts/demo-app > "$BUILD_DIR/chart.yaml"

log "kustomize build deploy/base and every overlay"
for target in base overlays/dev overlays/stage overlays/prod; do
    out="$BUILD_DIR/$(echo "$target" | tr '/' '-').yaml"
    tool kustomize build --enable-helm "deploy/$target" > "$out"
    printf '    deploy/%-18s -> %s objects\n' "$target" "$(grep -c '^kind:' "$out")"
done

log "kustomize build platform/ and argocd/projects"
tool kustomize build platform/cert-manager-issuers > "$BUILD_DIR/cert-manager-issuers.yaml"
tool kustomize build argocd/projects > "$BUILD_DIR/projects.yaml"

log "kubeconform: rendered workloads against Kubernetes $KUBE_VERSION"
tool kubeconform \
    -kubernetes-version "$KUBE_VERSION" \
    -schema-location default \
    -schema-location "$CRD_SCHEMAS" \
    -strict -summary -verbose \
    .build/base.yaml .build/overlays-dev.yaml .build/overlays-stage.yaml .build/overlays-prod.yaml \
    | tail -1

log "kubeconform: Argo CD Applications, AppProjects and cert-manager issuers"
tool kubeconform \
    -kubernetes-version "$KUBE_VERSION" \
    -schema-location default \
    -schema-location "$CRD_SCHEMAS" \
    -strict -summary \
    argocd/root-app.yaml argocd/apps .build/projects.yaml .build/cert-manager-issuers.yaml \
    | tail -1

log "all manifests render and validate"
