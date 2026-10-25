#!/usr/bin/env bash
# Sourced only by simulator qualification. No secrets or database logs are artifacts.
relay_pid=''
relay_directory=''
relay_url='https://127.0.0.1:18443'

relay_stop_server() {
  local status=0
  if [[ -n "$relay_pid" ]]; then
    if kill -0 "$relay_pid" 2>/dev/null; then
      kill -TERM "$relay_pid" || status=1
      for ((attempt=0; attempt<20; attempt++)); do
        if ! kill -0 "$relay_pid" 2>/dev/null; then break; fi
        sleep 1
      done
      if kill -0 "$relay_pid" 2>/dev/null; then
        kill -KILL "$relay_pid" || status=1
        status=1
      fi
      wait "$relay_pid" || status=1
    fi
    relay_pid=''
  fi
  return "$status"
}

# Closed-vocabulary diagnostic: no URL bodies, headers, certificates or server logs.
relay_probe_file='artifacts/ios/relay-probe.txt'
relay_probe() {
  local label=$1 alive=no exit_code=none port=unknown category=other curl_status=0 seconds='0'
  [[ "$label" =~ ^[a-z0-9_]+$ ]] || label=invalid
  if [[ -n "$relay_pid" ]] && kill -0 "$relay_pid" 2>/dev/null; then
    alive=yes
  elif [[ -n "$relay_pid" ]]; then
    wait "$relay_pid" 2>/dev/null && exit_code=0 || exit_code=$?
    relay_pid=''
  fi
  if command -v lsof > /dev/null 2>&1; then
    if lsof -nP -iTCP:18443 -sTCP:LISTEN > /dev/null 2>&1; then port=yes; else port=no; fi
  fi
  if [[ -n "$relay_directory" && -f "$relay_directory/ca.crt" ]]; then
    seconds=$(curl --silent --fail --output /dev/null --max-time 5 --cacert "$relay_directory/ca.crt" \
      --write-out '%{time_total}' "$relay_url/qualification/ready" 2>/dev/null) || curl_status=$?
  else
    curl_status=-1
  fi
  case "$curl_status" in
    0) category=ok ;;
    28) category=timeout ;;
    7) category=connect_refused ;;
    35|51|53|54|58|59|60|66|77|80|83|90|91) category=tls ;;
    22) category=http_error ;;
    -1) category=not_started ;;
  esac
  [[ "$seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] || seconds=0
  local milliseconds
  milliseconds=$(awk -v s="$seconds" 'BEGIN { printf "%d", s * 1000 }')
  mkdir -p "$(dirname "$relay_probe_file")"
  printf 'probe=%s utc=%s pid_alive=%s exit_code=%s port_listening=%s curl=%s curl_ms=%s\n' \
    "$label" "$(date -u +%H:%M:%S)" "$alive" "$exit_code" "$port" "$category" "$milliseconds" >> "$relay_probe_file" || true
}

relay_mark() {
  [[ "$1" =~ ^[a-z0-9_]+$ && "$2" =~ ^[a-z0-9_.-]+$ ]] || return 0
  mkdir -p "$(dirname "$relay_probe_file")"
  printf 'mark=%s value=%s utc=%s\n' "$1" "$2" "$(date -u +%H:%M:%S)" >> "$relay_probe_file" || true
}

relay_cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -n "$relay_pid" ]]; then relay_probe before_cleanup; fi
  relay_stop_server
  local server_status=$?
  local postgres_status=0
  if [[ -n "$relay_directory" && -f "$relay_directory/postgres/postmaster.pid" ]]; then
    pg_ctl -D "$relay_directory/postgres" -m fast -w stop > /dev/null 2>&1
    postgres_status=$?
  fi
  if [[ -n "$relay_directory" ]]; then
    case "$relay_directory" in
      "$RUNNER_TEMP"/drivy-relay.*) rm -rf -- "$relay_directory" || status=1 ;;
      *) echo 'Nettoyage du relais refusé hors du dossier temporaire.' >&2; status=1 ;;
    esac
  fi
  if (( server_status != 0 || postgres_status != 0 )); then status=1; fi
  exit "$status"
}

relay_start_server() {
  NODE_ENV=test DRIVY_RELAY_ALLOW_RESET=1 \
    TEST_DATABASE_URL='postgres://drivy_test@127.0.0.1:15432/drivy_test' \
    DRIVY_RELAY_PORT=18443 DRIVY_RELAY_TLS_CERT="$relay_directory/server.crt" \
    DRIVY_RELAY_TLS_KEY="$relay_directory/server.key" \
    node --import tsx scripts/messaging-relay-qualification.mts > "$relay_directory/server.log" 2>&1 &
  relay_pid=$!
  local ready=0
  for ((attempt=0; attempt<180; attempt++)); do
    if ! kill -0 "$relay_pid" 2>/dev/null; then break; fi
    if curl --silent --fail --max-time 2 --cacert "$relay_directory/ca.crt" \
      "$relay_url/qualification/ready" > "$relay_directory/ready.json"; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then
    echo 'Relais HTTPS de qualification indisponible ; journaux sensibles non publiés.' >&2
    return 1
  fi
  python3 - "$relay_directory/ready.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
if data.get('ready') is not True or data.get('fixture') != 'drivy-messaging-relay-v1':
    raise SystemExit('Relais de qualification inattendu')
PY
}

relay_start() {
  [[ "$(uname -s)" == Darwin && "${RUNNER_ENVIRONMENT:-}" == github-hosted && -n "${RUNNER_TEMP:-}" ]] || {
    echo 'Le relais intégré exige un runner Apple GitHub hébergé et jetable.' >&2
    return 1
  }
  umask 077
  relay_directory=$(mktemp -d "$RUNNER_TEMP/drivy-relay.XXXXXX")
  trap relay_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  initdb -D "$relay_directory/postgres" -U drivy_test -A trust --no-locale --encoding=UTF8 > "$relay_directory/init.log" 2>&1
  pg_ctl -D "$relay_directory/postgres" -l "$relay_directory/postgres.log" \
    -o "-h 127.0.0.1 -p 15432 -c unix_socket_directories=''" -w start > /dev/null
  createdb -h 127.0.0.1 -p 15432 -U drivy_test drivy_test
  cat > "$relay_directory/tls.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ca
[dn]
CN = Drivy disposable qualification CA
[ca]
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
[server]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF
  openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 2 \
    -config "$relay_directory/tls.cnf" -keyout "$relay_directory/ca.key" -out "$relay_directory/ca.crt" > "$relay_directory/tls.log" 2>&1
  openssl req -new -newkey rsa:2048 -nodes -sha256 -subj /CN=localhost \
    -keyout "$relay_directory/server.key" -out "$relay_directory/server.csr" >> "$relay_directory/tls.log" 2>&1
  openssl x509 -req -sha256 -days 2 -in "$relay_directory/server.csr" \
    -CA "$relay_directory/ca.crt" -CAkey "$relay_directory/ca.key" -CAcreateserial \
    -extfile "$relay_directory/tls.cnf" -extensions server -out "$relay_directory/server.crt" >> "$relay_directory/tls.log" 2>&1
  relay_start_server
}

relay_trust_simulator() {
  local trust_status=0
  xcrun simctl keychain "$1" add-root-cert "$relay_directory/ca.crt" || trust_status=$?
  relay_mark trust_status "$trust_status"
  return "$trust_status"
}

relay_reset_fixture() {
  relay_stop_server
  # The test-only server reapplies real migrations and fixtures in its isolated database.
  relay_start_server
}
