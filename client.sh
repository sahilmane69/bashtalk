#!/usr/bin/env bash

# BashTalk client: connect to a BashTalk server over TCP.

set -u

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$script_dir/lib/common.sh"

host="${1:-}"
port="${2:-}"
username="${3:-}"

if [ -z "$host" ] || ! valid_port "$port" || ! valid_username "$username"; then
  print_usage "$0" '<server-ip-or-name> <port> <username>'
  printf 'Username: 1-24 letters, numbers, underscores, or hyphens.\n' >&2
  exit 1
fi

require_netcat

session_dir="$(make_temp_dir)"
incoming_fifo="$session_dir/incoming"
outgoing_fifo="$session_dir/outgoing"
mkfifo "$incoming_fifo" "$outgoing_fifo"
exec 3<>"$outgoing_fifo"

connection_pid=''
reader_pid=''
sent_quit='false'

cleanup() {
  if [ "$sent_quit" = 'false' ]; then
    printf 'QUIT\n' >&3 2>/dev/null || true
  fi
  exec 3>&- 2>/dev/null || true
  [ -n "$reader_pid" ] && kill "$reader_pid" 2>/dev/null || true
  [ -n "$connection_pid" ] && kill "$connection_pid" 2>/dev/null || true
  rm -rf "$session_dir"
}
trap cleanup EXIT INT TERM

show_server_messages() {
  local line=''
  while IFS= read -r line; do
    printf '%s\n' "$line"
  done < "$incoming_fifo"
}

printf 'Connecting to %s:%s as %s...\n' "$host" "$port" "$username"
nc "$host" "$port" < "$outgoing_fifo" > "$incoming_fifo" &
connection_pid=$!
show_server_messages &
reader_pid=$!

printf 'NAME|%s\n' "$username" >&3
printf 'Connected. Type a message and press Enter. Type /quit to leave.\n'

while IFS= read -r message; do
  case "$message" in
    /quit)
      printf 'QUIT\n' >&3
      sent_quit='true'
      break
      ;;
    '') ;;
    *) printf '%s\n' "$message" >&3 ;;
  esac
done
