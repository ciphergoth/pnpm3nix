#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building lodash package..."
nix-build lodash.nix -o result

echo "🧪 Running lodash tests..."
nix-shell --run "node test-app.js"

echo "🔧 Building package with dependencies..."
nix-build package-with-deps.nix

echo "🧪 Running dependency tests..."
nix-shell --run "node test-deps.js"

echo "✅ All tests completed successfully!"