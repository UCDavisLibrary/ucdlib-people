#! /bin/bash
set -e
CMDS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$(cd "$CMDS_DIR/../.." && pwd)"
SERVICES_DIR="$(cd "$ROOT_DIR/services" && pwd)"
COMPOSE_DIR="$(cd "$ROOT_DIR/devops/compose" && pwd)"
LOCAL_DEV_DIR="$(cd "$ROOT_DIR/devops/compose/ucdlib-people-local-dev" && pwd)"
PROJECT_NAME="ucdlib-people"