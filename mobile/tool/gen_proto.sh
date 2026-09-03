#!/usr/bin/env bash
# Generate Dart classes from the Android TV Remote v2 protobuf schemas.
#
# The output is committed, so neither CI nor a fresh clone needs protoc:
#   brew install protobuf
#   dart pub global activate protoc_plugin
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/.."

export PATH="$PATH:$HOME/.pub-cache/bin"
command -v protoc >/dev/null || { echo "protoc חסר: brew install protobuf" >&2; exit 1; }
command -v protoc-gen-dart >/dev/null || { echo "protoc-gen-dart חסר: dart pub global activate protoc_plugin" >&2; exit 1; }

out="lib/src/proto"
rm -rf "$out"
mkdir -p "$out"
protoc --dart_out="$out" --proto_path=protos protos/*.proto

# The generator emits a service stub importing package:grpc, which this project
# does not use — the protocol is raw protobuf over a TLS socket.
rm -f "$out"/*.pbgrpc.dart

echo "נוצרו:"
ls -1 "$out"
