# pnpm2nix TODO

## API Alignment with Existing pnpm2nix

To match the existing pnpm2nix usage pattern in eloise/apps/zerbongle/flake.nix:

1. ✅ **Add workspace + components parameters** - Support monorepo pattern with `workspace = ../..` and `components = ["apps/zerbongle"]`
2. ✅ **Add overlay support** - Export as `overlays.default` to extend pkgs
3. **Add buildScripts parameter** - Run npm build commands like `buildScripts = ["build"]`
4. **Add installNodeModules flag** - Optional dependency installation control
5. **Keep backward compatibility** - Support both single `src` and workspace patterns

## Core Features (Completed ✅)

- ✅ Lockfile parsing with yaml2json
- ✅ Per-package derivations with fetchurl
- ✅ Transitive dependency resolution
- ✅ Scoped packages (@scope/package)
- ✅ Workspace support (link: references)
- ✅ Peer dependency contexts
- ✅ Basic mkPnpmPackage API

## Edge Cases & Polish

- **Native package support** - Packages requiring compilation (node-gyp, Python)
- **Optional dependencies** - Handle optionalDependencies in lockfile
- **Platform-specific packages** - Handle os/cpu constraints
- **CLI tool** - Standalone executable for easy usage
- **Error handling** - Graceful failures for missing packages/bad hashes
- **Performance** - Optimize for large lockfiles

## Testing

- **Real-world projects** - Test with complex monorepos
- **Integration tests** - Automated testing beyond current test-project
- **Edge case coverage** - Test optional deps, platform packages, etc.