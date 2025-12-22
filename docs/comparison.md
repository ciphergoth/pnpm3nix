# pnpm3nix vs traditional Docker builds

This document explains how building a webapp with pnpm3nix + nix2container differs from the standard Dockerfile approach. It's written for developers familiar with Docker but not necessarily with Nix.

## The traditional approach

A typical webapp Dockerfile follows a **multi-stage build** pattern:

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# Stage 2: Runtime
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

This approach:

1. **Starts from a base Linux image** (Alpine, Debian, Ubuntu)
2. **Installs build tools** (Node.js, pnpm, compilers) inside the container
3. **Copies source code** into the container
4. **Runs the build** inside Docker (`pnpm install`, `pnpm build`)
5. **Copies artifacts** to a smaller "runtime" image
6. **Ships it**

### Problems with this approach

- **Imperative execution**: Each `RUN` command executes in sequence. Docker caches layers, but if you change line 5, everything after it rebuilds from scratch.
- **"Works on my machine"**: Builds depend on the base image state at pull time, network conditions during `npm install`, and timing. Two builds from the same Dockerfile can produce different results.
- **Coarse caching**: Change one line of your source code and the entire `pnpm install` layer is still cached, but the entire `pnpm build` layer rebuilds.
- **Manual layer optimization**: You have to carefully order your `COPY` and `RUN` commands to maximize cache hits. Get it wrong and rebuilds are slow.

## The Nix approach

**Nix** is a purely functional package manager. Instead of installing packages imperatively (like `apt install` or `npm install`), you declare what you want and Nix builds it in isolation. Each package is stored in a unique path based on a hash of all its inputs—source code, dependencies, build flags, everything. This means builds are reproducible: the same inputs always produce the same output.

With **pnpm3nix** + **nix2container**, we apply this philosophy to JavaScript projects:

### 1. Build happens outside Docker

The `mkPnpmPackage` function reads your `pnpm-lock.yaml` and builds the entire application as a **Nix derivation** on your host machine:

```nix
app = pkgs.mkPnpmPackage {
  workspace = ./../..;
  component = "apps/my-webapp";
};
```

This all happens before any container is involved.

#### How pnpm3nix transforms your lockfile

PNPM's lockfile (`pnpm-lock.yaml`) is a complete, solved dependency graph. It specifies exactly which version of each package to use, where to fetch it from, and how packages depend on each other. pnpm3nix treats this lockfile as a declarative specification and transforms it into Nix derivations:

1. **Parse the lockfile**: Extract all packages, their versions, integrity hashes, and dependency relationships
2. **Create per-package derivations**: Each npm package becomes its own Nix derivation, fetched by content hash from the npm registry
3. **Wire up dependencies**: Each package's `node_modules` is assembled via symlinks to its dependency derivations
4. **Build workspace packages**: Your application code is built with all dependencies in place

This per-package approach means Nix can cache each dependency individually. Update `lodash` and only `lodash` rebuilds—not your entire `node_modules`.

#### Handling dependency cycles

Real-world npm dependency graphs often contain cycles (e.g., `browserslist` ↔ `update-browserslist-db`). Nix derivations cannot have circular references, so pnpm3nix uses **Tarjan's algorithm** to detect strongly connected components (SCCs) in the dependency graph. Packages involved in cycles are bundled into a single shared derivation, while packages without cycles get their own individual derivations. This means pnpm3nix can handle any valid pnpm lockfile, even those with complex circular dependencies.

### 2. No Dockerfile at all

Instead of a Dockerfile, you describe the container declaratively:

```nix
dockerImage = nix2container.buildImage {
  name = "my-webapp";
  tag = "latest";
  maxLayers = 100;

  config = {
    Entrypoint = [ "${entrypoint}" ];
    ExposedPorts."3000/tcp" = {};
    Env = [ "NODE_ENV=production" ];
  };
};
```

The `nix2container.buildImage` function takes the already-built application and constructs a container image directly from the Nix store.

### 3. Content-addressed, automatic layer splitting

When you set `maxLayers = 100`, nix2container analyzes the **closure** (all dependencies of your app, recursively) and automatically splits them into Docker layers using a "popularity" algorithm:

- Common packages like glibc, openssl, and Node.js get their own layers
- These layers are shared across different images and builds
- Your application code goes in its own layer at the top

You don't manually optimize layer order—the tool does it for you based on what's actually shared.

### 4. Byte-identical reproducibility

Given the same inputs (source code, lockfile, Nix version), Nix produces the **exact same output** every time. Two developers on different machines, or CI running a month apart, get identical images down to the byte.

## Key differences

| Aspect | Traditional Docker | Nix + nix2container |
|--------|-------------------|---------------------|
| **Where build happens** | Inside container | On host, before containerization |
| **Dependency resolution** | At build time (`npm install`) | Declaratively from lockfile |
| **Caching granularity** | Per Dockerfile line | Per package/dependency |
| **Reproducibility** | Best-effort | Byte-identical guaranteed |
| **Layer strategy** | Manual, based on COPY order | Automatic, optimized for sharing |
| **Base image** | Pulled from Docker Hub | None—constructed from Nix store |

## The "no base image" concept

This is often the most surprising part: **there is no base image**.

In traditional Docker, you always start `FROM` something—Alpine, Ubuntu, `node:20`, etc. That base image includes a Linux userspace, shell, package manager, and various utilities.

With nix2container, the image is built entirely from **Nix store paths**. If your app needs Node.js, glibc, and openssl, those exact versions are included—nothing more. There's no `/bin/sh`, no `apt`, no extra utilities unless you explicitly add them.

This means:
- Smaller images (only what you need)
- Smaller attack surface (no unused binaries)
- No "base image update" maintenance

## Practical example: what happens when you change code

### Traditional Docker

1. You edit `src/index.ts`
2. Run `docker build .`
3. Docker uses cached layers for `COPY package.json` and `RUN pnpm install`
4. Docker rebuilds everything from `COPY . .` onwards
5. Entire application is rebuilt and bundled

### Nix + nix2container

1. You edit `src/index.ts`
2. Run `nix build`
3. Nix sees that only your source derivation changed
4. Nix rebuilds only your application (dependencies are cached)
5. nix2container regenerates only the top layer containing your app
6. All other layers (Node.js, npm packages, system libraries) remain unchanged

If you update a single npm package, only that package's layer changes—not every package.

## Trade-offs

### Why you might prefer traditional Docker

- **Familiarity**: Most developers know Dockerfiles
- **Simpler toolchain**: Just Docker, no Nix installation required
- **Faster iteration for small projects**: For a tiny app, the overhead of learning Nix isn't worth it
- **Wider ecosystem support**: Most CI systems have first-class Docker support

### Why you might prefer Nix

- **Large dependency trees**: When you have hundreds of npm packages, per-package caching is transformative
- **Monorepos**: Nix handles multi-package workspaces naturally
- **Reproducibility requirements**: When "it works on my machine" isn't acceptable
- **Deployment to multiple targets**: The same Nix expression can produce Docker images, VM images, or bare deployments

## Further reading

- [Nix Pills](https://nixos.org/guides/nix-pills/) - Gentle introduction to Nix concepts
- [nix2container](https://github.com/nlewo/nix2container) - The tool that builds OCI images from Nix
- [pnpm3nix README](../README.md) - How this project handles JavaScript specifically
