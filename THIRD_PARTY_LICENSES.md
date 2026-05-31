# Third-party licenses

## aria2

- Version: `1.37.0`
- Source: <https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.xz>
- SHA-256: `60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b`
- License: GNU GPL version 2 or, at your option, any later version

The container image copies aria2 `COPYING`, `AUTHORS`, and `README.rst` into
`/usr/share/doc/aria2`.

## Debian runtime packages

The image uses `debian:bookworm-slim` plus runtime libraries installed from the
Debian package repositories. Those packages retain their upstream and Debian
package licenses; inspect `/usr/share/doc/*/copyright` inside the image for
package-specific license text.

## Repository packaging

The repository's `LICENSE` covers the Docker packaging, workflows, tests, and
documentation in this repository. It does not relicense aria2 or Debian
packages included in the built image.
