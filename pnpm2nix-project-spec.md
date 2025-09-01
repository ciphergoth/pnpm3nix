# pnpm3nix: SCC-Based Dependency Resolution for Nix

This document describes the motivation, architecture, and implementation of pnpm3nix - a tool that builds JavaScript projects with PNPM lockfiles using Strongly Connected Component (SCC) analysis to handle circular dependencies in Nix derivations.

## Background and Motivation

### Current Problem
Existing pnpm2nix implementations (notably https://github.com/FliegendeWurst/pnpm2nix-nzbr) create single large derivations containing all packages from the lockfile. This leads to:

- **Massive Docker images**: Everything in the lockfile gets included, even packages only used by dev dependencies or unused transitive dependencies
- **Poor caching behavior**: Changing any dependency rebuilds the entire dependency tree
- **No Nix integration**: Can't use overlays, package overrides, or other Nix tooling on individual packages

### Why Not buildNpmPackage?
`buildNpmPackage` doesn't natively support pnpm workspaces well. It's designed around npm's simpler dependency model and struggles with:
- pnpm's workspace protocol (`workspace:*`) dependencies
- The content-addressable store structure
- Peer dependency contexts that can't be represented in flat `node_modules`

While there are pnpm hooks in nixpkgs that can work with `buildNpmPackage` to some degree, discussion suggests they don't fully handle complex workspace scenarios.

## Implemented Solution: SCC-Based Derivations

### Core Concept
Use Tarjan's algorithm to detect Strongly Connected Components (SCCs) in the dependency graph and create shared derivations for cyclic dependencies. This solves the fundamental problem where circular dependencies (like `browserslist` ↔ `update-browserslist-db`) would create unresolvable circular references in Nix.

### SCC Strategy
- **Singleton packages**: Get individual derivations (`lodash@4.17.21`)
- **Cyclic packages**: Share a single derivation containing all packages in the cycle
- **Semantic naming**: Derivation names reflect content without exposing internal SCC indices

### Key Insight: Peer Dependencies Create Separate Contexts
PNPM's notation like `package@1.0.0(react@19.1.0)(typescript@5.3.2)` represents the same source package in different peer dependency contexts. These genuinely need separate Nix derivations because:
- The runtime environment is different (different peer dependencies available)
- Node.js module resolution will find different versions depending on context
- This isolation is what makes pnpm's peer dependency resolution work

### Architecture Details

Each derivation contains either a single package or multiple packages in a dependency cycle:

**For singleton packages** (`lodash@4.17.21`):
```
/nix/store/abc123-lodash-4.17.21/
└── lodash@4.17.21/
    ├── package.json
    └── lib/
```

**For cyclic packages** (`browserslist` ↔ `update-browserslist-db`):
```
/nix/store/def456-browserslist-update-browserslist-db-cycle/
├── browserslist@4.25.0/
│   └── node_modules/
│       └── update-browserslist-db@ -> ../update-browserslist-db@1.1.3/
└── update-browserslist-db@1.1.3/
    └── node_modules/
        └── browserslist@ -> ../browserslist@4.25.0/
```

#### Symlink Structure
For a package with dependencies, the derivation creates:
```
/nix/store/abc123-package-1.0.0/
├── package.json
├── lib/
└── node_modules/
    ├── react/ -> /nix/store/def456-react-19.1.0
    ├── @types/
    │   └── react/ -> /nix/store/ghi789-types-react-18.2.45
    └── lodash/ -> /nix/store/jkl012-lodash-4.17.21
```

#### Workspace Handling
Workspace dependencies like `link:../package` in the lockfile become references to other workspace derivations. Since pnpm lockfiles represent acyclic dependency graphs by definition, Nix can build workspace packages in topological order.

## Current Implementation

### SCC Detection Pipeline
1. **Lockfile parsing**: `yaml2json` converts PNPM lockfile to JSON
2. **Dependency extraction**: `jq` transforms snapshots into dependency graph format
3. **Cycle detection**: `tarjan-cli` finds SCCs using Tarjan's algorithm
4. **Derivation generation**: Create shared derivations for each SCC

### Package Resolution
For packages with no dependencies:
```nix
pkgs.stdenv.mkDerivation {
  pname = "lodash";
  version = "4.17.21";
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz";
    sha512 = "...";
  };
  dontBuild = true;  # Most JS packages are pre-built
  installPhase = ''
    cp -r package $out
  '';
}
```

For packages with dependencies, add symlink creation in `installPhase`.

### Dependency Resolution
- **Internal cycle references**: Use relative symlinks (`../package`) within shared derivations
- **External references**: Use absolute paths to other derivations
- **Scoped packages**: Create proper `@scope/package` directory structures
- **Workspace packages**: Handle `link:` dependencies between workspace components

## Why This Approach Should Work

### Ecosystem Resilience Argument
The JavaScript ecosystem has adapted to multiple package managers with radically different approaches:
- npm's flattening algorithm
- pnpm's symlink forests
- Yarn PnP's complete elimination of `node_modules`

Any package that works with these diverse systems should work with our symlink-based approach. The ecosystem has been forced to be resilient to different `node_modules` structures.

### Lockfile as Solved State
PNPM has already handled complex edge cases when creating the lockfile:
- Optional dependencies (already decided what to include/exclude)
- Platform-specific packages (already resolved for your platform)
- Build scripts (already executed, results captured)
- Environment-based resolution (already resolved based on NODE_ENV)

We're implementing a lockfile interpreter, not reimplementing a package manager.

### Content-Addressable Alignment
Both PNPM and Nix use content-addressable storage with similar philosophies. We're translating between compatible systems rather than forcing incompatible models together.

## Detailed Technical Challenges Analysis

### 1. Module Resolution Conflicts
**Risk**: Node.js module resolution might not behave correctly with Nix store symlinks.

**Specific concerns**:
- Relative path resolution between packages
- `require.resolve()` behavior when crossing symlink boundaries
- `__dirname` and `process.cwd()` pointing to unexpected locations
- Platform differences in symlink handling

**Assessment**: Likely not a problem because pnpm already uses extensive symlinks and the ecosystem has adapted. Our approach is actually more conservative than Yarn PnP.

### 2. Hardlink vs Symlink Issues
**Risk**: PNPM uses hardlinks for actual files, we'd use symlinks everywhere.

**Specific concerns**:
- Package write permissions (some packages expect to modify their directory)
- Build scripts that assume writable package directories
- File identity operations that behave differently with symlinks
- Executable permissions on symlinked files

**Assessment**: Most well-behaved packages don't self-modify. Nix's read-only store could actually prevent corruption. Main issue would be packages that need temporary file creation.

### 3. Workspace Dependencies
**Initial concern**: Circular dependencies and build ordering.

**Resolution**: PNPM lockfiles represent solved, acyclic dependency graphs. If pnpm generated a lockfile, there are no true cycles. Nix can build in topological order using the dependency relationships from the lockfile.

### 4. Native Dependencies
**Risk**: Packages with `.node` files having filesystem layout assumptions.

**Details**: 
- `.node` files are compiled C++ extensions for Node.js
- Native packages might use relative paths to find shared libraries
- Build process might expect specific directory structures

**Assessment**: Probably manageable as long as complete package directory structure is preserved in each derivation.

### 5. Path Length Limits
**Risk**: Deep Nix store symlink structures hitting filesystem limits.

**Details**:
- Filename limit: 255 characters (individual files/directories)
- Full path limit: 4096 characters on modern systems
- Nix store paths are already quite long
- Deep dependency nesting could compound the problem

**Assessment**: Least likely to be a fatal problem. Modern systems have generous limits, and dependency trees rarely get extremely deep.

## Premortem: Most Likely Failure Modes

### 1. Symlink/Module Resolution Edge Case (Medium probability)
You get 90% working, then hit a subtle Node.js behavior that doesn't work with your symlink structure. Popular package does something unexpected with `require.resolve()` or filesystem introspection.

**Mitigation**: Test with diverse real-world packages early.

### 2. Complexity Explosion (High probability)
The "simple" lockfile parsing turns into handling dozens of edge cases:
- Optional dependencies
- Platform-specific packages  
- Different lockfile format versions
- Build scripts with special requirements
- Packages that modify themselves

**Counter-argument**: PNPM handles these when creating the lockfile. We just interpret the solved state.

### 3. Workspace Package Edge Cases (Medium probability)
Workspace dependencies turn out harder than expected - version mismatches, build ordering issues, dev dependency cycles.

**Mitigation**: Start with simple workspace cases and build up complexity.

### 4. Performance Issues (Low-Medium probability)
Either Nix builds are too slow (too many derivations) or runtime performance suffers from symlink traversal.

### 5. Build Tooling Incompatibility (Medium probability)
Your approach works for running apps but breaks webpack/vite/rollup analysis of the dependency tree.

## Testing Strategy

### Unit Tests
- **Lockfile parsing**: Test various lockfile formats and versions
- **Package identifier handling**: Scoped packages, peer dependencies, workspace references
- **Edge case parsing**: Empty sections, missing fields, malformed entries
- **Regression tests**: As bugs are discovered

### Integration Tests - Tiered Complexity

**Tier 1: Simple Cases**
- Single package application, no dependencies
- Single package with simple dependencies (no peer deps)
- Basic workspace with two packages

**Tier 2: Real-world Complexity**  
- Popular open source projects of increasing complexity
- Projects with peer dependencies
- Multi-package workspaces with interdependencies

**Tier 3: Edge Cases**
- Native packages requiring compilation
- Packages with optional dependencies
- Complex peer dependency scenarios

### Comparison Testing
For each test case, compare behavior with `pnpm install`:
- Same packages importable via `require()`
- Same build script execution results
- Same runtime application behavior
- Performance characteristics

### Automated Test Infrastructure

**Docker-based testing**:
```bash
# Test against known-good pnpm behavior
docker run --rm -v $(pwd):/workspace test-runner \
  compare-behavior /workspace/test-project
```

**Property-based testing**:
- Generate lockfiles with different dependency patterns
- Verify invariants (acyclic graphs, resolvable dependencies)
- Test edge cases automatically

**CI Integration**:
- Test against multiple Node.js versions
- Test different pnpm lockfile format versions
- Performance regression detection

### Development Workflow Testing
- Incremental builds (changing one package rebuilds only affected derivations)
- Docker layer optimization with `buildLayeredImage`
- Integration with existing Nix workflows

## Comparison with Existing Approaches

### vs. Current pnpm2nix
**Their approach**: Single derivation recreating entire `.pnpm` structure
**Advantages of per-package**:
- Smaller final images (only reachable packages included)
- Better caching (individual package changes don't invalidate everything)
- Nix-native integration (overlays, overrides work naturally)

### vs. buildNpmPackage with pnpm hooks
**Current limitations**: Discussion suggests workspace support is incomplete
**Our advantages**: 
- Designed specifically for pnpm's peer dependency model
- Better Docker layering through fine-grained derivations
- Handles complex workspace scenarios

### vs. Manual Docker builds
**Disadvantages of manual**: No reproducibility, no caching, no integration
**Our advantages**: Full Nix benefits while maintaining pnpm compatibility

## Success Metrics

### Functional Correctness
- Applications behave identically to `pnpm install` versions
- All `require()` calls resolve to same packages
- Build scripts execute with same results

### Efficiency Gains
- Significantly smaller Docker images vs current pnpm2nix
- Faster incremental builds through selective rebuilding
- Better Docker layer caching

### Nix Integration
- Seamless use with existing Nix tooling
- Support for overlays and package overrides
- Integration with flakes and development shells

## Implementation Roadmap

### Minimal Viable Product
1. **Hardcoded test case**: Single package with known dependencies, hardcoded derivation structure
2. **Basic lockfile parsing**: Extract package list and dependencies from simple lockfile
3. **Derivation generation**: Create working derivations for parsed packages
4. **Symlink construction**: Build correct `node_modules` structure
5. **End-to-end test**: Build and run simple application

### Incremental Expansion
1. **Workspace support**: Handle `link:` references and build ordering
2. **Peer dependency contexts**: Ensure different contexts create separate derivations  
3. **Scoped packages**: Proper `@scope/package` directory structure
4. **Edge case handling**: Optional deps, platform-specific packages
5. **Native package support**: Compilation and build tooling
6. **Performance optimization**: Minimize derivation count, optimize builds

### Production Readiness
1. **Comprehensive testing**: Large test suite with real-world projects
2. **Documentation**: Usage guides and API reference
3. **CI/CD integration**: Automated testing and release process
4. **Community feedback**: Address issues found by early adopters

## Advanced Considerations

### Performance Optimizations
- **Derivation batching**: Group related packages to reduce total derivation count
- **Shared base layers**: Common dependencies as shared Docker layers
- **Build parallelization**: Leverage Nix's parallel building effectively

### Integration Points
- **Flakes support**: Clean integration with Nix flakes workflows
- **Development shells**: Provide development environments with correct dependencies
- **IDE integration**: Ensure editors can find type definitions and dependencies

### Extensibility
- **Plugin system**: Allow custom handling for specific package types
- **Override mechanisms**: Easy way to customize individual package builds
- **Multi-platform support**: Handle different architectures and operating systems

## Related Work and Inspiration

### Existing Tools
- **pnpm2nix variants**: Learn from limitations of current approaches
- **yarn2nix**: Similar challenges with different package manager
- **node2nix**: Earlier approach to Node.js packaging in Nix

### Conceptual Foundations
- **PNPM's design**: Content-addressable storage and peer dependency isolation
- **Nix principles**: Reproducible builds and content-addressable derivations
- **Docker layering**: Efficient image construction and caching

## Conclusion

This approach leverages the conceptual alignment between PNPM's and Nix's content-addressable philosophies to create a more efficient and Nix-native solution for JavaScript dependency management. By treating the lockfile as a solved specification rather than reimplementing resolution logic, we can achieve better correctness, efficiency, and integration than existing approaches.

The main risks are implementation complexity and potential edge cases, but the fundamental approach is sound and builds on proven concepts from both ecosystems. The testing strategy focuses on incremental validation and comparison with known-good behavior to minimize these risks.

Success would provide significant practical benefits for deploying JavaScript applications in containerized environments while maintaining the full power of Nix's dependency management system.