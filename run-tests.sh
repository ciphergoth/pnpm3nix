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

echo "🔧 Building test-project with lockfile-generated dependencies..."
nix-build test-project.nix

echo "🧪 Running project tests..."
nix-shell --run "cd result && node test.js"

echo "✅ All tests completed successfully!"