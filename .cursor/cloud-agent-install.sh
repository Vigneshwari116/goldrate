#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
export PATH="${FLUTTER_HOME}/bin:${PATH}"
export FLUTTER_GIT_URL="${FLUTTER_GIT_URL:-https://github.com/flutter/flutter.git}"

flutter pub get
