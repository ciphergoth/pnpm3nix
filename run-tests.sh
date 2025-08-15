#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building lodash package..."
nix-build lodash.nix -o result

echo "🧪 Running tests..."
nix-shell --run "node test-app.js"

echo "✅ Test runner completed successfully!"