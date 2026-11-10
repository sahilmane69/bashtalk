#!/usr/bin/env bash

# Shared helpers for BashTalk scripts. Keep this file compatible with the
# Bash version that ships with older macOS releases.

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

print_usage() {
  local script_name="$1"
  local usage_text="$2"

  printf 'Usage: %s %s\n' "$script_name" "$usage_text"
}

require_netcat() {
  if ! command -v nc >/dev/null 2>&1; then
    printf 'BashTalk needs netcat (the nc command) to make TCP connections.\n' >&2
    exit 1
  fi
}

valid_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

valid_username() {
  case "$1" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
  esac

  [ "${#1}" -le 24 ]
}

make_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/bashtalk.XXXXXX"
}

# Apple and the common Linux OpenBSD netcat use a positional listening port.
# Traditional netcat on some Linux distributions expects -p instead.
listen_with_netcat() {
  local port="$1"

  if [ "$(uname -s)" = 'Darwin' ]; then
    nc -lk "$port"
  elif nc -h 2>&1 | grep -qi 'openbsd'; then
    nc -lk "$port"
  else
    nc -lk -p "$port"
  fi
}
