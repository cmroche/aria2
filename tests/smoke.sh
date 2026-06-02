#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/cmroche/aria2:latest}"
PLATFORM="${TEST_PLATFORM:-linux/amd64}"
RPC_PORT="${TEST_RPC_PORT:-16800}"
HTTP_PORT="${TEST_HTTP_PORT:-18080}"
PUID="${TEST_PUID:-10001}"
PGID="${TEST_PGID:-10002}"
UMASK="${TEST_UMASK:-0077}"
ARIA2_DISK_CACHE="${TEST_ARIA2_DISK_CACHE:-64M}"
ARIA2_MAX_CONCURRENT_DOWNLOADS="${TEST_ARIA2_MAX_CONCURRENT_DOWNLOADS:-2}"
ARIA2_MAX_CONNECTION_PER_SERVER="${TEST_ARIA2_MAX_CONNECTION_PER_SERVER:-4}"
TMPDIR="$(mktemp -d)"
CID=""
HTTP_PID=""

cleanup() {
  if [ -n "${CID}" ]; then
    docker logs "${CID}" >/tmp/aria2-smoke-container.log 2>&1 || true
    docker rm -f "${CID}" >/dev/null 2>&1 || true
  fi
  if [ -n "${HTTP_PID}" ]; then
    kill "${HTTP_PID}" >/dev/null 2>&1 || true
  fi
  if [ -d "${TMPDIR}" ]; then
    docker run --rm \
      --platform "${PLATFORM}" \
      --user 0:0 \
      --entrypoint /bin/sh \
      -v "${TMPDIR}:/work" \
      "${IMAGE}" \
      -c 'rm -rf /work/* /work/.[!.]* /work/..?*' >/dev/null 2>&1 || true
    rmdir "${TMPDIR}" >/dev/null 2>&1 || rm -rf "${TMPDIR}" || true
  fi
}
trap cleanup EXIT

rpc() {
  curl -fsS \
    "http://127.0.0.1:${RPC_PORT}/jsonrpc" \
    -H "Content-Type: application/json" \
    -d "$1"
}

assert_no_bittorrent_feature() {
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
features = data.get("result", {}).get("enabledFeatures", [])
if any(feature.lower() == "bittorrent" for feature in features):
    raise SystemExit(f"BitTorrent unexpectedly enabled: {features}")
print("RPC enabled features:", ", ".join(features))
'
}

if docker run --rm --platform "${PLATFORM}" --entrypoint aria2c "${IMAGE}" -v | grep -i "BitTorrent"; then
  echo "aria2c -v reports BitTorrent support." >&2
  exit 1
fi

mkdir -p "${TMPDIR}/downloads" "${TMPDIR}/www"
chmod 0777 "${TMPDIR}/downloads"
printf "aria2 smoke test\n" > "${TMPDIR}/www/payload.txt"

python3 -m http.server "${HTTP_PORT}" --bind 0.0.0.0 --directory "${TMPDIR}/www" >/tmp/aria2-smoke-http.log 2>&1 &
HTTP_PID="$!"

http_ready=""
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${HTTP_PORT}/payload.txt" >/dev/null 2>&1; then
    http_ready=1
    break
  fi
  sleep 1
done

if [ -z "${http_ready}" ]; then
  echo "Test HTTP server did not become ready." >&2
  exit 1
fi

CID="$(
  docker run -d \
    --platform "${PLATFORM}" \
    --add-host=host.docker.internal:host-gateway \
    --cap-drop ALL \
    --cap-add SETUID \
    --cap-add SETGID \
    --read-only \
    --security-opt no-new-privileges \
    --tmpfs /tmp:rw,mode=1777,size=64m \
    -e RPC_SECRET=test \
    -e PUID="${PUID}" \
    -e PGID="${PGID}" \
    -e UMASK="${UMASK}" \
    -e ARIA2_DISK_CACHE="${ARIA2_DISK_CACHE}" \
    -e ARIA2_MAX_CONCURRENT_DOWNLOADS="${ARIA2_MAX_CONCURRENT_DOWNLOADS}" \
    -e ARIA2_MAX_CONNECTION_PER_SERVER="${ARIA2_MAX_CONNECTION_PER_SERVER}" \
    -p "127.0.0.1:${RPC_PORT}:6800" \
    -v "${TMPDIR}/downloads:/downloads" \
    "${IMAGE}"
)"

for _ in $(seq 1 30); do
  if version_response="$(
    rpc '{"jsonrpc":"2.0","id":"version","method":"aria2.getVersion","params":["token:test"]}' 2>/dev/null
  )"; then
    printf "%s" "${version_response}" | assert_no_bittorrent_feature
    break
  fi
  sleep 1
done

if [ -z "${version_response:-}" ]; then
  echo "aria2 JSON-RPC did not become ready." >&2
  exit 1
fi

rpc '{"jsonrpc":"2.0","id":"options","method":"aria2.getGlobalOption","params":["token:test"]}' \
  | EXPECTED_DISK_CACHE="${ARIA2_DISK_CACHE}" \
    EXPECTED_MAX_CONCURRENT_DOWNLOADS="${ARIA2_MAX_CONCURRENT_DOWNLOADS}" \
    EXPECTED_MAX_CONNECTION_PER_SERVER="${ARIA2_MAX_CONNECTION_PER_SERVER}" \
    python3 -c '
import json
import os
import sys

data = json.load(sys.stdin)["result"]
expected = {
    "max-concurrent-downloads": os.environ["EXPECTED_MAX_CONCURRENT_DOWNLOADS"],
    "max-connection-per-server": os.environ["EXPECTED_MAX_CONNECTION_PER_SERVER"],
}
for name, value in expected.items():
    actual = data.get(name)
    if actual != value:
        raise SystemExit(f"{name} expected {value}, got {actual}")

expected_cache = os.environ["EXPECTED_DISK_CACHE"]
actual_cache = data.get("disk-cache")
accepted_cache_values = {expected_cache, expected_cache.upper(), expected_cache.lower()}
if expected_cache[-1:].upper() == "M" and expected_cache[:-1].isdigit():
    accepted_cache_values.add(str(int(expected_cache[:-1]) * 1024 * 1024))
elif expected_cache[-1:].upper() == "K" and expected_cache[:-1].isdigit():
    accepted_cache_values.add(str(int(expected_cache[:-1]) * 1024))
if actual_cache not in accepted_cache_values:
    raise SystemExit(f"disk-cache expected {expected_cache}, got {actual_cache}")

print("Configured aria2 options verified.")
'

gid="$(
  rpc '{"jsonrpc":"2.0","id":"add-http","method":"aria2.addUri","params":["token:test",["http://host.docker.internal:'"${HTTP_PORT}"'/payload.txt"],{"out":"payload.txt"}]}' \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["result"])'
)"

for _ in $(seq 1 60); do
  status="$(
    rpc '{"jsonrpc":"2.0","id":"status","method":"aria2.tellStatus","params":["token:test","'"${gid}"'",["status","errorMessage"]]}' \
    | python3 -c 'import json, sys; data=json.load(sys.stdin)["result"]; print(data["status"] + "\t" + data.get("errorMessage", ""))'
  )"
  case "${status}" in
    complete*) break ;;
    error*) echo "HTTP download failed: ${status}" >&2; exit 1 ;;
  esac
  sleep 1
done

if ! docker run --rm \
  --platform "${PLATFORM}" \
  --user 0:0 \
  --entrypoint /usr/bin/test \
  -v "${TMPDIR}/downloads:/downloads:ro" \
  "${IMAGE}" \
  -f /downloads/payload.txt; then
  echo "Downloaded payload was not written to /downloads." >&2
  exit 1
fi

docker run --rm \
  --platform "${PLATFORM}" \
  --user 0:0 \
  --entrypoint /usr/bin/cmp \
  -v "${TMPDIR}/www:/www:ro" \
  -v "${TMPDIR}/downloads:/downloads:ro" \
  "${IMAGE}" \
  /www/payload.txt /downloads/payload.txt

payload_stat="$(
  docker run --rm \
    --platform "${PLATFORM}" \
    --user 0:0 \
    --entrypoint /usr/bin/stat \
    -v "${TMPDIR}/downloads:/downloads:ro" \
    "${IMAGE}" \
    -c '%u:%g %a' /downloads/payload.txt
)"

if [ "${payload_stat}" != "${PUID}:${PGID} 600" ]; then
  echo "Unexpected payload owner/mode: ${payload_stat}" >&2
  exit 1
fi

magnet_response="$(
  curl -sS \
    "http://127.0.0.1:${RPC_PORT}/jsonrpc" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":"magnet","method":"aria2.addUri","params":["token:test",["magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test"]]}'
)"

printf "%s" "${magnet_response}" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
if "error" not in data:
    raise SystemExit(f"Magnet URI was accepted unexpectedly: {data}")
print("Magnet URI rejected as expected:", data["error"].get("message", "error"))
'

echo "Smoke tests passed."
