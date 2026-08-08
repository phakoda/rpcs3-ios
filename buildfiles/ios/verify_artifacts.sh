#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage:
  verify_artifacts.sh framework /path/to/RPCS3Core.framework [device|simulator]
  verify_artifacts.sh xcframework /path/to/RPCS3Core.xcframework
  verify_artifacts.sh app /path/to/RPCS3\ iOS\ Core.app
  verify_artifacts.sh dependencies device|simulator archive-or-library [...]
EOF
    exit 2
}

[[ $# -ge 2 ]] || usage
MODE="$1"
shift
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "${MODE}" in
    framework)
        "${ROOT}/buildfiles/ios/verify_core_framework.sh" "$@"
        ;;
    xcframework)
        [[ $# -eq 1 ]] || usage
        "${ROOT}/buildfiles/ios/verify_core_xcframework.sh" "$1"
        ;;
    app)
        [[ $# -eq 1 ]] || usage
        "${ROOT}/buildfiles/ios/verify_core_app.sh" "$1"
        ;;
    dependencies)
        [[ $# -ge 2 ]] || usage
        "${ROOT}/buildfiles/ios/verify_dependency_archives.sh" "$@"
        ;;
    *) usage ;;
esac
