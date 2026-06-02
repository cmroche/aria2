#!/bin/sh
set -eu

if [ -z "${RPC_SECRET:-}" ]; then
  echo "RPC_SECRET is required." >&2
  exit 64
fi

DOWNLOAD_DIR="${DOWNLOAD_DIR:-/downloads}"
RPC_PORT="${RPC_PORT:-6800}"
ARIA2_LOG_LEVEL="${ARIA2_LOG_LEVEL:-notice}"
ARIA2_DISK_CACHE="${ARIA2_DISK_CACHE:-512M}"
ARIA2_MAX_CONCURRENT_DOWNLOADS="${ARIA2_MAX_CONCURRENT_DOWNLOADS:-3}"
ARIA2_MAX_CONNECTION_PER_SERVER="${ARIA2_MAX_CONNECTION_PER_SERVER:-8}"
PUID="${PUID:-568}"
PGID="${PGID:-${GUID:-${GID:-568}}}"
UMASK="${UMASK:-0022}"
STATE_DIR="${DOWNLOAD_DIR}/.aria2"
SESSION_FILE="${STATE_DIR}/session.txt"

case "${RPC_PORT}" in
  ''|*[!0-9]*)
    echo "RPC_PORT must be a numeric TCP port." >&2
    exit 64
    ;;
esac

case "${PUID}" in
  ''|*[!0-9]*)
    echo "PUID must be a numeric user ID." >&2
    exit 64
    ;;
esac

case "${PGID}" in
  ''|*[!0-9]*)
    echo "PGID must be a numeric group ID." >&2
    exit 64
    ;;
esac

case "${UMASK}" in
  [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7])
    ;;
  *)
    echo "UMASK must be three or four octal digits." >&2
    exit 64
    ;;
esac

case "${ARIA2_MAX_CONCURRENT_DOWNLOADS}" in
  ''|*[!0-9]*)
    echo "ARIA2_MAX_CONCURRENT_DOWNLOADS must be a positive integer." >&2
    exit 64
    ;;
  0)
    echo "ARIA2_MAX_CONCURRENT_DOWNLOADS must be greater than 0." >&2
    exit 64
    ;;
esac

case "${ARIA2_MAX_CONNECTION_PER_SERVER}" in
  ''|*[!0-9]*)
    echo "ARIA2_MAX_CONNECTION_PER_SERVER must be a positive integer." >&2
    exit 64
    ;;
  0)
    echo "ARIA2_MAX_CONNECTION_PER_SERVER must be greater than 0." >&2
    exit 64
    ;;
esac

if ! printf '%s' "${ARIA2_DISK_CACHE}" | grep -Eq '^[0-9]+([KkMm])?$'; then
  echo "ARIA2_DISK_CACHE must be a size in bytes, K, or M." >&2
  exit 64
fi

umask "${UMASK}"

run_as_target() {
  if [ "$(id -u)" -eq 0 ]; then
    gosu "${PUID}:${PGID}" "$@"
  else
    "$@"
  fi
}

exec_as_target() {
  if [ "$(id -u)" -eq 0 ]; then
    exec gosu "${PUID}:${PGID}" "$@"
  else
    exec "$@"
  fi
}

if [ ! -d "${DOWNLOAD_DIR}" ]; then
  echo "DOWNLOAD_DIR does not exist: ${DOWNLOAD_DIR}" >&2
  exit 73
fi

if ! run_as_target mkdir -p "${STATE_DIR}"; then
  echo "DOWNLOAD_DIR is not writable by uid/gid ${PUID}:${PGID}: ${DOWNLOAD_DIR}" >&2
  exit 73
fi

if ! run_as_target touch "${SESSION_FILE}"; then
  echo "Session file is not writable by uid/gid ${PUID}:${PGID}: ${SESSION_FILE}" >&2
  exit 73
fi

exec_as_target aria2c \
  --no-conf=true \
  --enable-rpc=true \
  --rpc-listen-all=true \
  --rpc-listen-port="${RPC_PORT}" \
  --rpc-secret="${RPC_SECRET}" \
  --dir="${DOWNLOAD_DIR}" \
  --input-file="${SESSION_FILE}" \
  --save-session="${SESSION_FILE}" \
  --save-session-interval=60 \
  --force-save=true \
  --continue=true \
  --disk-cache="${ARIA2_DISK_CACHE}" \
  --max-concurrent-downloads="${ARIA2_MAX_CONCURRENT_DOWNLOADS}" \
  --max-connection-per-server="${ARIA2_MAX_CONNECTION_PER_SERVER}" \
  --log=- \
  --log-level="${ARIA2_LOG_LEVEL}" \
  --console-log-level="${ARIA2_LOG_LEVEL}" \
  --show-console-readout=false \
  --summary-interval=0 \
  "$@"
