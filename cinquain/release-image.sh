#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$ROOT_DIR/.." && pwd)

require_tool() {
    tool_name=$1
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        echo "Required tool not found: $tool_name"
        exit 1
    fi
}

require_tool docker

IMAGE_TAG=${1:-${CINQUAIN_IMAGE_TAG:-}}
if [ -z "$IMAGE_TAG" ]; then
    echo "Usage: ./release-image.sh <image:tag>"
    echo "Or set CINQUAIN_IMAGE_TAG in the environment."
    exit 1
fi

BUILD_MODE=${CINQUAIN_BUILD_MODE:-load}
case "$BUILD_MODE" in
    load)
        OUTPUT_FLAG=--load
        ;;
    push)
        OUTPUT_FLAG=--push
        ;;
    *)
        echo "Unsupported CINQUAIN_BUILD_MODE: $BUILD_MODE"
        echo "Expected one of: load, push"
        exit 1
        ;;
esac

docker buildx build \
    --file "$REPO_ROOT/docker/Dockerfile" \
    --build-arg CONTINUWUITY_VERSION_EXTRA=+cinquain \
    --tag "$IMAGE_TAG" \
    "$OUTPUT_FLAG" \
    "$REPO_ROOT"
