#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building lodash package (hardcoded)..."
nix-build lodash.nix -o result

echo "🧪 Running lodash tests..."
nix-shell --run "node test-app.js"

echo "🔧 Building package with dependencies..."
nix-build package-with-deps.nix

echo "🧪 Running dependency tests..."
nix-shell --run "node test-deps.js"

echo "🔧 Building lodash from lockfile (dynamic)..."
nix-build -A lodash dynamic-derivations.nix

echo "🧪 Running lockfile-driven tests..."
nix-shell --run "node test-lockfile.js"

echo "✅ All tests completed successfully!"