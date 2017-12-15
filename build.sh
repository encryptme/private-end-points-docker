#!/bin/sh -u

BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

fail() {
    echo "$@" >&2
    exit 1
}

usage() {
    cat <<EOI
Usage: $SCRIPT_NAME [ARGUMENTS] [DOCKER ARGS]
(e.g.)

OPTIONS:
    -b|--branch REPO      Override branch for PEP client repo
    -e|--env ENV          Env to build/push (stage, prod) (default: $env)
    -h|--help             This information
    -p|--push             Automatically push to Docker hub
    -t|--tag              Specify explicit tag (overrides --env)

EXAMPLE:

  \$ $SCRIPT_NAME -e stage -b jkf
EOI
}

# args
env='prod'
branch=
push=0
docker_args=(--rm)
force_tag=

while [ $# -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in 
        --branch|-b)
            [ $# -gt 0 ] || fail "Missing arg to --env|-e"
            branch="$1"
            shift
            ;;
        --env|-e)
            [ $# -gt 0 ] || fail "Missing arg to --env|-e"
            env="$1"
            [ "$env" = 'stage' -o "$env" = 'prod' ] \
                || fail "Unknown env: '$env'; 'stage' or 'prod' expected."
            shift
            ;;
        --push|-p)
            push=1
            ;;
        --tag|-t)
            force_tag="$1"
            shift
            ;;
        --help|-h)
            usage
            exit
            ;;
        *)
            docker_args[${#docker_args[*]}]="$arg"
            ;;
    esac
done


which docker 2>&1 || fail "Failed to locate 'docker' binary"

tag="encryptme/pep"
if [ "$env" = 'stage' ]; then
    tag="$tag-stage"
    [ -n "$branch" ] || branch='stage'
else
    [ -n "$branch" ] || branch='master'
fi
if [ ! -z "$force_tag" ]; then
    tag="$force_tag"
fi

echo "Building '$tag' for '$env' with PEP client repo branch '$branch'"
echo
echo '           ----======----'
docker build . -t "$tag" \
    --build-arg repo_branch="$branch" \
    "${docker_args[@]}" \
    || fail "Failed to build '$tag' with repo branch '$branch'"
echo '           ----======----'
echo
echo

if [ $push -eq 1 ]; then
    docker push "$tag" || fail "Failed to push '$tag'"
else
    echo "Skipped 'docker push \"$tag\"'"
fi


exit 0
