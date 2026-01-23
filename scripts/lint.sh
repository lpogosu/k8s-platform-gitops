#!/usr/bin/env sh
# yamllint over every YAML file that is written by hand. Rendered output under
# .build/ and the Helm templates (which are Go templates, not YAML) are
# excluded in .yamllint.yml.

set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

log "yamllint"
yamllint_all
log "yamllint clean"
