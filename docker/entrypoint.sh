#!/bin/sh
set -eu

if [ -z "${RPC_SECRET:-}" ]; then
  echo "RPC_SECRET is required." >&2
  exit 64
fi

DOWNLOAD_DIR="${DOWNLOAD_DIR:-/downloads}"
RPC_PORT="${RPC_PORT:-6800}"
ARIA2_LOG_LEVEL="${ARIA2_LOG_LEVEL:-notice}"
STATE_DIR="${DOWNLOAD_DIR}/.aria2"
SESSION_FILE="${STATE_DIR}/session.txt"

case "${RPC_PORT}" in
  ''|*[!0-9]*)
    echo "RPC_PORT must be a numeric TCP port." >&2
    exit 64
    ;;
esac

if [ ! -d "${DOWNLOAD_DIR}" ]; then
  echo "DOWNLOAD_DIR does not exist: ${DOWNLOAD_DIR}" >&2
  exit 73
fi

if [ ! -w "${DOWNLOAD_DIR}" ]; then
  echo "DOWNLOAD_DIR is not writable by uid/gid 568:568: ${DOWNLOAD_DIR}" >&2
  exit 73
fi

mkdir -p "${STATE_DIR}"
touch "${SESSION_FILE}"

exec aria2c \
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
  --log=- \
  --log-level="${ARIA2_LOG_LEVEL}" \
  --console-log-level="${ARIA2_LOG_LEVEL}" \
  --summary-interval=0 \
  "$@"
