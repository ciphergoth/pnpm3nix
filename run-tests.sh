#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building utils workspace component with all dependencies..."
nix-shell --run "cd test-project/packages/utils && nix-build test-project.nix"

echo "🧪 Running utils component tests..."
nix-shell --run "cd test-project/packages/utils/result && node index.js"

echo "✅ Utils component test completed successfully!"