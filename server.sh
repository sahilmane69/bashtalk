#!/usr/bin/env bash

# BashTalk server: one server operator and one connected client at a time.

set -u

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$script_dir/lib/common.sh"

port="${1:-}"
if ! valid_port "$port"; then
  print_usage "$0" '<port>'
  exit 1
fi

require_netcat

data_dir="$script_dir/data"
history_file="$data_dir/chat-history.log"
mkdir -p "$data_dir"
touch "$history_file"

session_dir="$(make_temp_dir)"
incoming_fifo="$session_dir/incoming"
outgoing_fifo="$session_dir/outgoing"
mkfifo "$incoming_fifo" "$outgoing_fifo"

# Opening the outgoing FIFO for both reading and writing keeps netcat from
# blocking while it opens its input stream.
exec 3<>"$outgoing_fifo"

connection_pid=''
reader_pid=''

cleanup() {
  [ -n "$reader_pid" ] && kill "$reader_pid" 2>/dev/null || true
  [ -n "$connection_pid" ] && kill "$connection_pid" 2>/dev/null || true
  rm -rf "$session_dir"
}
trap cleanup EXIT INT TERM

send_line() {
  printf '%s\n' "$1" >&3
}

save_and_send() {
  printf '%s\n' "$1" >> "$history_file"
  printf '%s\n' "$1"
  send_line "$1"
}

read_client_messages() {
  local first_line=''
  local username=''
  local line=''

  if ! IFS= read -r first_line < "$incoming_fifo"; then
    return
  fi

  case "$first_line" in
    NAME\|*) username="${first_line#NAME|}" ;;
    *) username='Guest' ;;
  esac

  send_line "--- Recent chat history ---"
  cat "$history_file" >&3
  send_line "--- End history ---"
  save_and_send "[$(timestamp)] Server: $username joined the chat."

  case "$first_line" in
    NAME\|*) ;;
    *) save_and_send "[$(timestamp)] $username: $first_line" ;;
  esac

  while IFS= read -r line; do
    case "$line" in
      NAME\|*)
        username="${line#NAME|}"
        send_line "--- Recent chat history ---"
        cat "$history_file" >&3
        send_line "--- End history ---"
        save_and_send "[$(timestamp)] Server: $username joined the chat."
        ;;
      QUIT)
        save_and_send "[$(timestamp)] Server: $username left the chat."
        username=''
        ;;
      *)
        if [ -n "$username" ]; then
          save_and_send "[$(timestamp)] $username: $line"
        fi
        ;;
    esac
  done < "$incoming_fifo"
}

printf 'BashTalk server listening on TCP port %s.\n' "$port"
printf 'Waiting for one client. Press Ctrl-C to stop the server.\n'

listen_with_netcat "$port" < "$outgoing_fifo" > "$incoming_fifo" &
connection_pid=$!
read_client_messages &
reader_pid=$!

while IFS= read -r message; do
  case "$message" in
    /quit)
      send_line 'Server is closing the chat.'
      break
      ;;
    '') ;;
    *) save_and_send "[$(timestamp)] Server: $message" ;;
  esac
done
