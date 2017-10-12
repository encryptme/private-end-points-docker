#!/bin/sh -u

BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

fail() {
    echo "$@" >&2
    exit 1
}

usage() {
    cat <<EOI
Usage: $SCRIPT_NAME [ARGUMENTS]
(e.g.)

OPTIONS:
    -h|--help             This information
    -r|--repo REPO        Custom private-end points repo
    -t|--tag TAG          Custom tag to use        

EXAMPLE:

  \$ $SCRIPT_NAME --repo git+
EOI
}

tag="encryptme"
repo=""

while [ $# -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in 
        --tag|-t)
            [ $# -gt 0 ] || fail "Missing arg to --tag|-t"
            tag="$1"
            shift
            ;;
        --repo|-r)
            [ $# -gt 0 ] || fail "Missing arg to --repo|-r"
            repo="$1"
            shift
            ;;
        --help|-h)
            usage
            exit
            ;;
        *)
            fail "Invalid argument: $arg"
            ;;
    esac
done

which docker 2>&1 || fail "Failed to locate 'docker' binary"

build_args=(-t "$tag" .)
[ -n "$repo" ] && build_args=(--build-arg pep_repo="$repo" "${build_args[@]}")
docker build "${build_args[@]}"
