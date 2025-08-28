# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **pnpm3nix** - a Nix-based tool for building JavaScript projects with PNPM lockfiles using per-package derivations. Unlike traditional pnpm2nix implementations that create monolithic builds, this approach creates individual Nix derivations for each package, enabling better caching, smaller Docker images, and proper Nix ecosystem integration.

## Core Architecture

### Main Components

- **`pnpm2nix.nix`**: Main API - provides `mkPnpmPackage` function for building workspace components
- **`dynamic-derivations.nix`**: Core engine that parses `pnpm-lock.yaml` and generates per-package derivations
- **`flake.nix`**: Nix flake interface exporting the overlay and packages
- **`overlay.nix`**: Nixpkgs overlay making `mkPnpmPackage` available as `pkgs.mkPnpmPackage`

### Key Design Principles

1. **Per-package derivations**: Each resolved package context gets its own Nix derivation
2. **Peer dependency isolation**: Packages with different peer dependency contexts become separate derivations (e.g., `package@1.0.0(react@19.1.0)` vs `package@1.0.0(react@18.0.0)`)
3. **Workspace support**: Handles PNPM workspaces with `link:` references between packages
4. **Symlink-based node_modules**: Creates proper node_modules structure using symlinks to package derivations

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
# Build using the main API
nix-build -E '
  let pkgs = import <nixpkgs> {};
      pnpm2nix = import ./pnpm2nix.nix { inherit pkgs; };
  in pnpm2nix.mkPnpmPackage {
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

## Development Environment

```bash
# Shell provides Node.js and PNPM
nix-shell

# Available tools
- nodejs (for running tests)
- pnpm (for lockfile generation/maintenance)
- yaml2json (for lockfile parsing)
```