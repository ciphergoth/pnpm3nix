# pnpm3nix

A Nix-based tool for building JavaScript projects with PNPM lockfiles using SCC-aware per-package derivations. Unlike traditional pnpm2nix implementations, this approach uses Tarjan's algorithm to detect dependency cycles and creates shared derivations for cyclic dependencies, enabling better caching, smaller Docker images, and proper Nix ecosystem integration.

## Quick Start

```bash
# Enter development shell
nix-shell

# Run tests to validate the system
./run-tests.sh

# Build a workspace component
nix-build -E '
  let pkgs = import <nixpkgs> {};
      pnpm2nix = import ./pnpm2nix.nix { inherit pkgs; };
  in pnpm2nix.mkPnpmPackage {
    workspace = ./test-project;
    component = "apps/ts-webapp";
    script = "build";
  }
'
```

## Key Features

- **SCC-based cycle resolution**: Uses Tarjan's algorithm to handle circular dependencies
- **Per-package derivations**: Individual Nix derivations enable fine-grained caching
- **Workspace support**: Full PNPM monorepo support with `link:` dependencies
- **Semantic naming**: Clean derivation names without internal implementation details
- **Peer dependency isolation**: Different peer contexts get separate derivations

## How It Works

1. **Parse lockfile**: Uses `yaml2json` to parse `pnpm-lock.yaml`
2. **Detect cycles**: Runs Tarjan's algorithm to find strongly connected components
3. **Generate derivations**: Creates shared derivations for each SCC
4. **Build dependencies**: Installs all dependencies and runs build scripts
5. **Create runtime**: Copies results with only runtime dependencies

## Architecture

### Derivation Structure

**Singleton packages** get individual derivations:
```
/nix/store/abc123-lodash-4.17.21/
└── lodash@4.17.21/
    ├── package.json
    └── lib/
```

**Cyclic packages** share a single derivation:
```
/nix/store/def456-browserslist-update-browserslist-db-cycle/
├── browserslist@4.25.0/
│   └── node_modules/
│       └── update-browserslist-db@ -> ../update-browserslist-db@1.1.3/
└── update-browserslist-db@1.1.3/
    └── node_modules/
        └── browserslist@ -> ../browserslist@4.25.0/
```

### API

```nix
mkPnpmPackage {
  workspace = ./my-project;        # Path to workspace root
  component = "apps/webapp";       # Component to build
  script = "build";                # Build script to run
  name = "my-app";                 # Optional name override
  version = "1.0.0";               # Optional version override
}
```

## Dependencies

- **Node.js**: For running build scripts
- **PNPM**: For lockfile compatibility
- **yaml2json**: For parsing PNPM lockfiles
- **jq**: For dependency graph transformation
- **tarjan-cli**: External binary for SCC detection (see `tarjan-cli.nix`)

## Testing

The test suite validates the system with a multi-package workspace:

```bash
./run-tests.sh
```

This builds both workspace utilities and a TypeScript webapp, testing:
- Dependency resolution across workspace boundaries
- Build script execution
- Runtime vs dev dependency separation
- Complex dependency scenarios including cycles

## Comparison to Other Approaches

| Feature | pnpm3nix | buildNpmPackage | Traditional pnpm2nix |
|---------|----------|-----------------|---------------------|
| Circular dependencies | ✅ Handled via SCC | ❌ Fails | ❌ Monolithic workaround |
| Caching granularity | ✅ Per-package | ❌ All-or-nothing | ❌ All-or-nothing |
| Docker image size | ✅ Minimal | ❌ Large | ❌ Massive |
| Workspace support | ✅ Full | ⚠️ Limited | ✅ Yes |
| Nix integration | ✅ Native | ✅ Native | ❌ Limited |

## Files Overview

- **`pnpm2nix.nix`**: Main API providing `mkPnpmPackage` function
- **`derivations.nix`**: Core SCC-aware derivation generator
- **`tarjan-cli.nix`**: Builds the Tarjan algorithm CLI tool
- **`flake.nix`**: Nix flake interface
- **`overlay.nix`**: Nixpkgs overlay
- **`test-project/`**: Comprehensive test workspace
- **`run-tests.sh`**: Test runner script

## Contributing

This project uses SCC-based architecture to solve the fundamental circular dependency problem in JavaScript package graphs. When making changes, ensure that the SCC detection and shared derivation logic remains intact.

See `CLAUDE.md` for detailed development guidance and `pnpm2nix-project-spec.md` for complete architectural documentation.
