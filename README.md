# aria2 TrueNAS Custom App Image

This repository builds a headless aria2 container for TrueNAS Community
Edition custom apps. The image compiles aria2 from upstream source with
BitTorrent disabled, exposes only the JSON-RPC port, and stores downloads in an
external `/downloads` mount.

The target TrueNAS stable release is 25.10.3.1 as of May 31, 2026. TrueNAS 26
is still early-release/beta, so this image and Compose example target the
25.10 custom app flow.

## Image contract

| Item | Value |
| --- | --- |
| Image | `ghcr.io/cmroche/aria2:<tag>` |
| Architecture | `linux/amd64` |
| Runtime user | `568:568` (`apps:apps` on TrueNAS) |
| JSON-RPC port | `6800/tcp` |
| Downloads mount | `/downloads` |
| Required environment | `RPC_SECRET` |
| Optional environment | `RPC_PORT`, `DOWNLOAD_DIR`, `ARIA2_LOG_LEVEL`, `TZ` |

No BitTorrent support is compiled into the binary, and no BitTorrent TCP or UDP
ports are exposed.

## TrueNAS Custom App deployment

1. Create or choose a downloads dataset, for example
   `/mnt/tank/apps/aria2/downloads`.
2. Grant write access to UID/GID `568:568` on that dataset. In the TrueNAS app
   UI this is the default `apps/apps` user and group.
3. Make the GHCR package public, or configure registry credentials in TrueNAS
   before deploying a private package.
4. In TrueNAS, go to **Apps > Discover Apps > more_vert > Install via YAML**.
5. Paste `examples/truenas-compose.yaml`.
6. Replace or provide these values before saving:

```sh
RPC_SECRET=replace-with-a-long-random-token
DOWNLOADS_PATH=/mnt/tank/apps/aria2/downloads
HOST_RPC_PORT=6800
```

The Compose example runs as `568:568`, drops Linux capabilities, enables
`no-new-privileges`, uses a read-only root filesystem, mounts `/tmp` as tmpfs,
and bind-mounts the downloads dataset at `/downloads`.

If the TrueNAS YAML editor does not provide external Compose environment
variables, edit the YAML directly and replace the `${...}` placeholders with
literal values before clicking Save.

## Local build and test

Build the image:

```sh
docker build \
  --build-arg ARIA2_VERSION=1.37.0 \
  -t ghcr.io/cmroche/aria2:dev \
  .
```

Run the smoke test suite:

```sh
IMAGE=ghcr.io/cmroche/aria2:dev tests/smoke.sh
```

Run it manually:

```sh
mkdir -p downloads
chmod 0777 downloads

docker run --rm \
  -e RPC_SECRET=test \
  -p 6800:6800 \
  -v "$PWD/downloads:/downloads" \
  ghcr.io/cmroche/aria2:dev
```

Call JSON-RPC:

```sh
curl -s http://127.0.0.1:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "id": "version",
    "method": "aria2.getVersion",
    "params": ["token:test"]
  }'
```

Check the compiled feature list:

```sh
docker run --rm --entrypoint aria2c ghcr.io/cmroche/aria2:dev -v
```

The output must not list `BitTorrent`.

## Publishing

`.github/workflows/image.yml` builds on pull requests without publishing. Pushes
to `main`, Git tags matching `v*`, and manual workflow dispatches publish to
GHCR using `GITHUB_TOKEN`.

Tags:

- `latest` from the default branch
- semantic version tags from `v*` Git tags
- `sha-<shortsha>` for traceability

The publish job also requests BuildKit provenance and SBOM attestations.

## References

- TrueNAS Custom Apps: <https://apps.truenas.com/managing-apps/installing-custom-apps/>
- TrueNAS 25.10 version notes: <https://www.truenas.com/docs/scale/25.10/gettingstarted/versionnotes/>
- TrueNAS 26 version notes: <https://www.truenas.com/docs/scale/26/gettingstarted/versionnotes/>
- aria2 upstream: <https://github.com/aria2/aria2>
- GitHub Actions GHCR publishing: <https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images>
- Docker docs: <https://docs.docker.com/>
