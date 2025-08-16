#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building utils workspace component with all dependencies..."
nix-shell --run "cd test-project/packages/utils && nix-build test-project.nix"

echo "🧪 Running utils component tests..."
nix-shell --run "cd test-project/packages/utils/result && node index.js"

echo "✅ Utils component test completed successfully!"

echo "🔧 Building TypeScript webapp component..."
nix-shell --run "cd test-project/apps/ts-webapp && nix-build test-webapp.nix"

echo "🧪 Testing TypeScript compilation..."
nix-shell --run "cd test-project/apps/ts-webapp/result && node dist/index.js"

echo "🧪 Testing dev dependencies excluded from final result..."
nix-shell --run "cd test-project/apps/ts-webapp/result && test ! -d node_modules/typescript && test -d node_modules/lodash && echo '✅ Dev deps excluded, runtime deps included'"
