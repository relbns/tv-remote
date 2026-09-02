#!/usr/bin/env bash
# Copy the repository's shared data into the Flutter package.
#
# Flutter can only declare assets that live inside the package, so the canonical
# files in ../shared are copied in before build. The destination is git-ignored.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$here/../assets/shared"
cp "$here/../../shared/"*.json "$here/../assets/shared/"
echo "shared: $(cd "$here/../../shared" && ls *.json | tr '\n' ' ')→ mobile/assets/shared/"
