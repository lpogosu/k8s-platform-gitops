#!/usr/bin/env sh
# Shared helpers. Sourced, never executed directly.
#
# The linting and validation targets are expected to run on a laptop that may
# only have Docker installed, and inside CI where the binaries are on PATH.
# Every tool call therefore goes through `tool`, which prefers the local binary
# and falls back to a pinned container image.

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Every tool below is invoked with paths relative to the repository root, and
# yamllint resolves the `ignore:` patterns in .yamllint.yml against the working
# directory. Running from anywhere else silently changes what gets checked, so
# the working directory is fixed here rather than in each caller.
cd "$REPO_ROOT" || exit 1

# Pinned so that a validation failure is always reproducible. cytopia/yamllint
# only publishes major tags, so it is pinned to the 1.x line.
IMAGE_TOOLS="alpine/k8s:1.31.0"
IMAGE_YAMLLINT="cytopia/yamllint:alpine-1"

# Schema set used by kubeconform. Matches the kind node image in kind/cluster.yaml.
# shellcheck disable=SC2034  # read by validate.sh, which sources this file
KUBE_VERSION="1.33.4"

# CRDs are not part of the upstream Kubernetes OpenAPI schemas, so kubeconform
# needs a second source for Application, AppProject, ClusterIssuer and friends.
# shellcheck disable=SC2034  # read by validate.sh, which sources this file
CRD_SCHEMAS="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

have() {
    command -v "$1" >/dev/null 2>&1
}

# Docker Desktop under Git Bash rejects the /e/... form that MSYS produces and
# wants a drive-letter path instead.
host_path() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*)
            (cd "$1" && pwd -W)
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

require_docker() {
    if ! have docker; then
        echo "error: '$1' is not installed and Docker is not available to run it" >&2
        exit 1
    fi
}

# Run a tool from PATH, or from IMAGE_TOOLS with the repository mounted at /repo.
tool() {
    bin=$1
    shift
    if have "$bin"; then
        "$bin" "$@"
    else
        require_docker "$bin"
        MSYS_NO_PATHCONV=1 docker run --rm \
            -v "$(host_path "$REPO_ROOT")":/repo -w /repo \
            "$IMAGE_TOOLS" "$bin" "$@"
    fi
}

yamllint_all() {
    if have yamllint; then
        yamllint -c .yamllint.yml .
    else
        require_docker yamllint
        MSYS_NO_PATHCONV=1 docker run --rm \
            -v "$(host_path "$REPO_ROOT")":/repo -w /repo \
            "$IMAGE_YAMLLINT" -c .yamllint.yml .
    fi
}

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$*"
}

fail() {
    printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}
