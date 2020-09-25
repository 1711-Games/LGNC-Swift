#!/bin/sh

set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
integration_dir="$root_dir/IntegrationTests"
integration_codegen_dir="$integration_dir/Sources/IntegrationTests/Codegen"
tests_dir="$root_dir/Tests/LGNCSwiftTests"
tests_codegen_dir="$tests_dir/Codegen"
build_dir="$root_dir/.build"
LGNBuilder_dir="${integration_dir}/Var/LGNBuilder"
LGNBuilder_repository="git@github.com:1711-Games/LGNBuilder.git"
LGNBuilder_executable="$LGNBuilder_dir/Scripts/generate"

if [ -d "$LGNBuilder_dir" ]; then
    (cd "$LGNBuilder_dir" && git pull)
else
    mkdir -p "$LGNBuilder_dir"
    git clone "$LGNBuilder_repository" "$LGNBuilder_dir"
fi

mkdir -p "$tests_codegen_dir"
"$LGNBuilder_executable" --lang Swift \
    --input  "$tests_dir/Schema" \
    --output "$tests_codegen_dir"
swift test --package-path "$root_dir"

mkdir -p "$integration_codegen_dir"
"$LGNBuilder_executable" --lang Swift \
    --input  "$LGNBuilder_dir/IntegrationTests/Schema" \
    --output "$integration_codegen_dir"
swift run  --package-path "$integration_dir" --build-path "$build_dir" \
    IntegrationTests --tests-directory "$LGNBuilder_dir/IntegrationTests/Tests"

echo "** All tests passed **"
