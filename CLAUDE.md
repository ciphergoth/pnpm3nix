# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **pnpm3nix** - a Nix-based tool for building JavaScript projects with PNPM lockfiles using per-package derivations. Unlike traditional pnpm2nix implementations that create monolithic builds, this approach creates individual Nix derivations for each package, enabling better caching, smaller Docker images, and proper Nix ecosystem integration.

## Core Architecture

### Main Components

- **`pnpm2nix.nix`**: Original API - provides `mkPnpmPackage` function for building workspace components
- **`pnpm2nix-scc.nix`**: **NEW** SCC-aware API that handles cyclic dependencies using Tarjan's algorithm
- **`dynamic-derivations.nix`**: Original per-package derivation generator (may fail on cycles)
- **`scc-aware-derivations.nix`**: **NEW** SCC-aware derivation generator that bundles cyclic dependencies
- **`flake.nix`**: Nix flake interface exporting the overlay and packages
- **`overlay.nix`**: Nixpkgs overlay making `mkPnpmPackage` available as `pkgs.mkPnpmPackage`

### Key Design Principles

1. **SCC-aware bundling**: Uses Tarjan's algorithm to detect dependency cycles and bundle them into single derivations
2. **Consistent structure**: All packages (singleton and bundled) use the same `bundle-name/{package@version}/` directory layout
3. **Semantic naming**: Bundle names reflect their contents (e.g., `browserslist-update-browserslist-db-cycle-bundle`)
4. **Peer dependency isolation**: Packages with different peer dependency contexts become separate derivations
5. **Workspace support**: Handles PNPM workspaces with `link:` references between packages
6. **Symlink-based node_modules**: Creates proper node_modules structure using symlinks to bundle derivations

## Development Commands

### Running Tests
```bash
# Run all tests - builds both workspace utils and TypeScript webapp
./run-tests.sh

# Enter development shell
nix-shell

# Test individual components
cd test-project/packages/utils && nix-build test-project.nix
cd test-project/apps/ts-webapp && nix-build test-webapp.nix
```

### Building Components
```bash
# Build using the original API (may fail on cycles)
nix-build -E '
  let pkgs = import <nixpkgs> {};
      pnpm2nix = import ./pnpm2nix.nix { inherit pkgs; };
  in pnpm2nix.mkPnpmPackage {
    workspace = ./test-project;
    components = ["apps/ts-webapp"];
    script = "build";
  }
'

# Build using the SCC-aware API (handles cycles)
nix-build -E '
  let pkgs = import <nixpkgs> {};
      pnpm2nixSCC = import ./pnpm2nix-scc.nix { 
        inherit pkgs; 
        tarjanPath = "/path/to/tarjan-cli";
      };
  in pnpm2nixSCC.mkPnpmPackage {
    workspace = ./test-project;
    components = ["apps/ts-webapp"];
    script = "build";
  }
'
```

## API Usage

### mkPnpmPackage Parameters

- **`workspace`**: Path to workspace root (where `pnpm-lock.yaml` exists)
- **`components`**: Array of component paths relative to workspace (currently handles first component)
- **`name`**: Optional package name (auto-detected from package.json if omitted)
- **`version`**: Optional version (defaults to "1.0.0" or package.json version)  
- **`script`**: Build script to run (e.g., "build", "compile") - empty string skips building

### Build Process

1. **Parse lockfile**: Uses `yaml2json` to parse `pnpm-lock.yaml`
2. **Generate derivations**: Creates per-package derivations for all dependencies
3. **Build phase**: Installs all dependencies (runtime + dev) and runs build script
4. **Install phase**: Copies built result and installs only runtime dependencies

## Lockfile Parsing Strategy

The system treats `pnpm-lock.yaml` as a solved dependency specification rather than reimplementing PNPM's resolution logic:

- **packages**: Direct npm package references
- **snapshots**: Resolved dependency contexts (including peer dependency variations) 
- **importers**: Workspace package dependency specifications
- **Workspace detection**: Identifies `link:` dependencies to build workspace packages in topological order

## Testing Structure

- **`test-project/`**: Comprehensive test workspace with multiple scenarios
- **`test.js`**: Node.js integration test validating dependency resolution
- **Multi-package workspace**: Tests both workspace utilities and TypeScript compilation
- **Dependency types**: Tests regular deps, dev deps, workspace deps, scoped packages (@types/node), and peer dependencies (React/ReactDOM)

## SCC (Strongly Connected Components) Approach

### Problem Solved
The original `dynamic-derivations.nix` fails when PNPM lockfiles contain dependency cycles (e.g., `browserslist` ↔ `update-browserslist-db`) because Nix cannot resolve circular derivation references.

### Solution Architecture
1. **Cycle Detection**: Uses Tarjan's algorithm via external CLI tool to find SCCs in dependency graph
2. **Bundle Strategy**: 
   - **Singleton packages**: Get individual bundles (e.g., `lodash-bundle/{lodash@4.17.21}/`)
   - **Cyclic packages**: Get bundled together (e.g., `browserslist-update-browserslist-db-cycle-bundle/{browserslist@4.25.0/, update-browserslist-db@1.1.3}/`)
3. **Dependency Resolution**: Internal cycle references use relative symlinks (`../package`), external references use absolute bundle paths

### Bundle Structure
```
/nix/store/abc123-lodash-bundle/
└── lodash@4.17.21/          # Singleton bundle
    ├── package.json
    └── lib/

/nix/store/def456-browserslist-update-browserslist-db-cycle-bundle/
├── browserslist@4.25.0/     # Cyclic bundle  
│   └── node_modules/
│       └── update-browserslist-db@ -> ../update-browserslist-db@1.1.3-browserslist@4.25.0-
└── update-browserslist-db@1.1.3-browserslist@4.25.0-/
    └── node_modules/
        └── browserslist@ -> ../browserslist@4.25.0/
```

## Development Environment

```bash
# Shell provides Node.js and PNPM
nix-shell

# Available tools
- nodejs (for running tests)
- pnpm (for lockfile generation/maintenance)
- yaml2json (for lockfile parsing)
- jq (for dependency graph transformation)
- External tarjan-cli binary (for SCC detection)
```