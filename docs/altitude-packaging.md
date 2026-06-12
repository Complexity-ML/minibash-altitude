# Altitude package system

## Scope of version 1

Debian `debootstrap` remains a temporary forge provider for third-party
binaries. Its prepared filesystem is never packed directly into the image.
Altitude captures it as `altitude-base`, `altitude-kernel` and
`altitude-firmware`, signs those artifacts, then reconstructs a fresh root from
the repository snapshot. The installed-system contract is therefore Altitude's
package repository rather than a live Debian mirror. APT, dpkg and their state
databases are removed from the delivered snapshot; `pkg` is the installed
package-management interface. Local package archives can also be installed with
`altpkg-install PACKAGE.altpkg`, which delegates to `pkg install-file`.

## Package format

An `.altpkg` file is a tar archive with exactly two roots:

```text
ALTITUDE/MANIFEST
ALTITUDE/files.sha256
payload/...
```

The manifest is declarative and is never sourced as shell code. Required
fields are `Name`, `Version`, `Architecture` and `Description`. Every regular
payload file is covered by `files.sha256`. `pkg` rejects absolute paths,
parent-directory traversal, invalid metadata and checksum mismatches.

## Repository and trust

`altrepo` publishes packages under `packages/`, creates the stanza-based
`INDEX`, hashes each artifact with SHA-256, and signs that digest with Ed25519.
Installed systems only contain the public key in
`/etc/altitude/keys/repository.pem`. The private key stays in the release
environment and is excluded from git and images.

The default repository is local and embedded:

```text
file:///var/lib/altitude/repository
```

The same format supports HTTPS. A production server only needs to serve the
repository directory as static files.

Developer machines can also use a dedicated Altitude workshop volume. On the
HP Omen target, `/dev/sda4` is labelled `altitude-spare` and mounted at
`/srv/altitude`:

```text
/srv/altitude/repository
/srv/altitude/sources
/srv/altitude/builds
/srv/altitude/logs
/srv/altitude/images
```

Initialize it with:

```sh
scripts/init-altitude-workshop.sh
```

The script does not format disks. It only mounts the existing
`LABEL=altitude-spare`, initializes `altrepo`, and points
`/etc/altitude/repositories.conf` at `file:///srv/altitude/repository`.

Then source the workshop environment before builds:

```sh
source scripts/use-altitude-workshop.sh
scripts/build-source-recipe.sh zlib
scripts/publish-workshop-packages.sh
```

With that environment, source archives are cached under
`/srv/altitude/sources`, recipe work directories go under
`/srv/altitude/builds/source-work/<recipe>`, new `.altpkg` files land in
`/srv/altitude/packages-staging`, and publishing adds them to
`/srv/altitude/repository`.

## Release policy

Altitude uses semantic versions for owned packages and named OS releases:

```text
0.1 Basecamp
0.2 Ridgeline
1.0 Summit
```

Each published package is immutable. A changed payload requires a new version.
Repository signing keys are offline release assets. Security fixes receive a
new package version, are published to a staging repository, pass package and
boot tests, then are promoted to stable. Kernel and initramfs updates continue
to use the existing A/B boot slots so a failed boot can roll back.

## Next migration layers

1. Package every Altitude service and configuration file.
2. Build a package dependency solver and an upgrade transaction.
3. Build libc and base utilities from pinned source recipes instead of a
   debootstrap forge.
4. Build and configure the kernel from an Altitude-owned source recipe.
5. Operate separate stable, testing and security repositories.

## Source forge

`sources/SOURCES.lock` is the source trust root. Each entry pins an official
upstream URL and SHA-256 digest. `scripts/source-fetch.sh` refuses unlocked or
modified archives. Recipes under `recipes/` build into isolated staging roots,
record their compiler and source digest, then emit normal signed `.altpkg`
artifacts.
## Source toolchain

Locked upstream archives live in `sources/SOURCES.lock`. Source recipes verify
those hashes before extracting anything and install their payload below an
isolated Altitude prefix. The toolchain starts at `/opt/altitude/toolchain`;
host tools remain bootstrap inputs only and their version is recorded in each
package's provenance file.

The forge is built in passes:

1. bootstrap Binutils and GCC using the available host compiler;
2. install Linux UAPI headers and build the Altitude libc in the sysroot;
3. rebuild Binutils and GCC with the Altitude compiler and sysroot;
4. rebuild BusyBox, the kernel, and subsequent packages with that toolchain.

Only artifacts produced by the final pass are eligible for an Altitude release.
Bootstrap packages are deliberately named `*-bootstrap`; they are forge inputs,
not packages installed in a release image.
