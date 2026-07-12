#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

case "${1:-}" in
    --panel|panel)
        shift
        exec "$ROOT_DIR/cinquain" panel "$@"
        ;;
    -h|--help)
        exec "$ROOT_DIR/cinquain" help
        ;;
    *)
        exec "$ROOT_DIR/cinquain" deploy "$@"
        ;;
esac
