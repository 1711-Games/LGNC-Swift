#!/bin/sh

set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
integration_dir="$root_dir/IntegrationTests"
build_dir="$root_dir/.build"
LGNBuilder_dir="${integration_dir}/Var/LGNBuilder"
LGNBuilder_repository="git@github.com:1711-Games/LGNBuilder.git"

if [ -d "$LGNBuilder_dir" ]; then
    (cd "$LGNBuilder_dir" && git pull)
else
    mkdir -p "$LGNBuilder_dir"
    git clone "$LGNBuilder_repository" "$LGNBuilder_dir"
fi

"$LGNBuilder_dir/Scripts/generate" \
    --lang   Swift \
    --input  "$LGNBuilder_dir/IntegrationTests/Schema" \
    --output "$integration_dir/Sources/IntegrationTests/Codegen"

swift test --package-path "$root_dir"
swift run  --package-path "$integration_dir" --build-path "$build_dir" \
    IntegrationTests --tests-directory "$LGNBuilder_dir/IntegrationTests/Tests"

echo "** All tests passed **"
