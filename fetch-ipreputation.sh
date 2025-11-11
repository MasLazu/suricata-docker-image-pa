#!/usr/bin/env bash
set -euo pipefail
IPREP_BASE_URL="${IPREP_BASE_URL:-http://iprep-service:8888}" # service DNS name or host:port
REPUTATION_ENDPOINT="${REPUTATION_ENDPOINT:-/api/v1/reputation/list}"
CATEGORIES_ENDPOINT="${CATEGORIES_ENDPOINT:-/api/v1/reputation/categories}"
REPUTATION_DEST="${REPUTATION_DEST:-/var/lib/suricata/reputation.list}"
CATEGORIES_DEST="${CATEGORIES_DEST:-/var/lib/suricata/reputation.categories.txt}"
TMP_DIR="/tmp/iprep"
INTERVAL_SECONDS="${IPREP_POLL_INTERVAL_SECONDS:-300}" # default 5 minutes

mkdir -p "${TMP_DIR}"

fetch_once() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[${ts}] Fetching IP reputation from ${IPREP_BASE_URL}" >&2
  local rep_tmp cats_tmp
  rep_tmp="${TMP_DIR}/reputation.list.tmp"
  cats_tmp="${TMP_DIR}/categories.txt.tmp"
  # Use ETag caching if previous files exist
  local etag_file rep_etag cats_etag
  etag_file="${TMP_DIR}/etag"
  rep_etag=""; cats_etag=""
  if [[ -f "${REPUTATION_DEST}" && -f "${etag_file}.rep" ]]; then
    rep_etag=$(cat "${etag_file}.rep")
  fi
  if [[ -f "${CATEGORIES_DEST}" && -f "${etag_file}.cats" ]]; then
    cats_etag=$(cat "${etag_file}.cats")
  fi
  # Reputation
  if [[ -n "${rep_etag}" ]]; then
    curl -fsS -H "If-None-Match: ${rep_etag}" "${IPREP_BASE_URL}${REPUTATION_ENDPOINT}" -o "${rep_tmp}" || return 1
  else
    curl -fsS "${IPREP_BASE_URL}${REPUTATION_ENDPOINT}" -o "${rep_tmp}" || return 1
  fi
  # Categories
  if [[ -n "${cats_etag}" ]]; then
    curl -fsS -H "If-None-Match: ${cats_etag}" "${IPREP_BASE_URL}${CATEGORIES_ENDPOINT}" -o "${cats_tmp}" || return 1
  else
    curl -fsS "${IPREP_BASE_URL}${CATEGORIES_ENDPOINT}" -o "${cats_tmp}" || return 1
  fi
  # Extract new ETags from headers (second fetch via -D to capture) if changed
  # Simplicity: always replace for now after successful fetch
  mkdir -p "$(dirname "${REPUTATION_DEST}")"
  mkdir -p "$(dirname "${CATEGORIES_DEST}")"
  mv "${rep_tmp}" "${REPUTATION_DEST}" 2>/dev/null || cp "${rep_tmp}" "${REPUTATION_DEST}"
  mv "${cats_tmp}" "${CATEGORIES_DEST}" 2>/dev/null || cp "${cats_tmp}" "${CATEGORIES_DEST}"
  echo "Updated reputation and categories files." >&2

  # Trigger Suricata to reload rules/datasets if suricatasc is available
  if command -v suricatasc >/dev/null 2>&1; then
    suricatasc -c reload-rules >/dev/null 2>&1 || true
  else
    # Fallback: send SIGHUP to Suricata
    pkill -HUP -x suricata >/dev/null 2>&1 || true
  fi
}

# Background loop if invoked without args
if [[ "${1:-}" == "run" ]]; then
  while true; do
    if ! fetch_once; then
      echo "Fetch failed; will retry in ${INTERVAL_SECONDS}s" >&2
    fi
    sleep "${INTERVAL_SECONDS}" || break
  done
else
  fetch_once
fi
