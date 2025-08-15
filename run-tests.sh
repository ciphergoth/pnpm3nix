#!/usr/bin/env bash

set -euo pipefail

echo "🔧 Building test-project with lockfile-generated dependencies..."
nix-build test-project.nix

echo "🧪 Running project tests..."
nix-shell --run "cd result && node test.js"

echo "✅ Test completed successfully!"