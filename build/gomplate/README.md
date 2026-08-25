# Template generator image

The generator image packages the complete upstream Gomplate release with Bash
and the small set of shell utilities used by `scripts/generate.sh`. The image
is only a build tool: `make generate` bind-mounts the checkout and runs it with
the caller's numeric UID/GID and with runtime networking disabled.

## Supported platforms and integrity

The image supports `linux/amd64` and `linux/arm64`. The Dockerfile selects the
matching upstream `gomplate_linux-*` release asset using Docker's
`TARGETARCH`. It rejects all other architectures before downloading an asset.
The architecture-specific SHA-256 files in `checksums/` are part of the build
input, and the download stage verifies the selected asset before copying it to
the runtime image. A version without a committed checksum also fails the
build.

To update Gomplate:

1. Download the full `gomplate_linux-amd64` and `gomplate_linux-arm64` assets
   from the same upstream release.
2. Verify the release provenance and update both files in `checksums/` with
   `sha256sum` output.
3. Update `GOMPLATE_VERSION` in the Dockerfile and Makefile.
4. Run the `linux/amd64` and `linux/arm64` generator image contract jobs.

`make test-gomplate-image GOMPLATE_PLATFORM=linux/amd64` runs the same image
contract locally. It checks the platform, version and checksum, required
runtime tools, lack of a Go toolchain, 80 MiB size limit, offline and arbitrary
UID/GID execution, unchanged output, and all generator failure modes. The CI
matrix runs this independently on native AMD64 and ARM64 Linux runners.

## Cold-build benchmark

Wall-clock build time is recorded here rather than enforced in CI. Image size
and behavior are the deterministic CI gates.

Benchmark recorded 2026-08-25:

- Runner: GitHub-hosted standard `ubuntu-24.04` Linux runner (4 vCPU, 16 GiB
  RAM)
- Architecture: `linux/amd64` (`x86_64`)
- Scope: Docker build only; pruning was outside each timed interval
- Clean-build preparation and command:

  ```bash
  docker builder prune --all --force
  docker image rm --force gomplate-benchmark 2>/dev/null || true
  /usr/bin/time -f '%e' docker build \
    --pull --no-cache --platform linux/amd64 \
    --build-arg GOMPLATE_VERSION=3.11.6 \
    --file build/gomplate/Dockerfile \
    --tag gomplate-benchmark .
  ```

Five comparable clean-build measurements were 8.42 s, 7.91 s, 8.11 s,
8.36 s, and 7.98 s. The median was **8.11 seconds**, below the 20-second goal.
