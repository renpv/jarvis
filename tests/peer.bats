load helpers

setup() {
  make_sandbox
  mkdir -p "$SANDBOX/bin" "$SANDBOX/wg"
  cat > "$SANDBOX/bin/wg" <<'EOF'
#!/usr/bin/env bash
case $1 in
  genkey) echo "PRIV$RANDOM$RANDOM" ;;
  genpsk) echo "PSK$RANDOM$RANDOM" ;;
  pubkey) read -r k; echo "PUB-$k" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$SANDBOX/bin/wg"
  export PATH="$SANDBOX/bin:$PATH"
  echo PRIVSERVER > "$SANDBOX/wg/server.key"
  printf '[Interface]\nAddress = 10.8.0.1/24\nListenPort = 51820\n' > "$SANDBOX/wg/wg0.conf"
  export JARVIS_VARS="$REPO_ROOT/provision/vars.sh" WG_DIR="$SANDBOX/wg" APPLY=0 WG_ENDPOINT=203.0.113.5
  PEER="$REPO_ROOT/bin/jarvis-peer"
}

@test "add cria o primeiro dispositivo em .2 com config de cliente correta" {
  run "$PEER" add celular
  [ "$status" -eq 0 ]
  grep -qx "# peer: celular" "$SANDBOX/wg/wg0.conf"
  grep -qx "AllowedIPs = 10.8.0.2/32" "$SANDBOX/wg/wg0.conf"
  c="$SANDBOX/wg/clients/celular.conf"
  grep -qx "Address = 10.8.0.2/32" "$c"
  grep -qx "DNS = 10.8.0.1" "$c"
  grep -qx "Endpoint = 203.0.113.5:51820" "$c"
  grep -qx "AllowedIPs = 10.8.0.0/24" "$c"
  grep -qx "PublicKey = PUB-PRIVSERVER" "$c"
  [ "$(stat -c %a "$c")" = 600 ]
}

@test "o mesmo PresharedKey vai para servidor e cliente" {
  "$PEER" add celular
  s=$(sed -n 's/^PresharedKey = //p' "$SANDBOX/wg/wg0.conf")
  c=$(sed -n 's/^PresharedKey = //p' "$SANDBOX/wg/clients/celular.conf")
  [ -n "$s" ]
  [ "$s" = "$c" ]
}

@test "segundo dispositivo recebe .3 e o primeiro é preservado" {
  "$PEER" add celular
  run "$PEER" add notebook
  [ "$status" -eq 0 ]
  grep -qx "AllowedIPs = 10.8.0.3/32" "$SANDBOX/wg/wg0.conf"
  grep -qx "# peer: celular" "$SANDBOX/wg/wg0.conf"
}

@test "recusa nome repetido" {
  "$PEER" add celular
  run "$PEER" add celular
  [ "$status" -ne 0 ]
  [ "$(grep -c '^# peer: celular$' "$SANDBOX/wg/wg0.conf")" -eq 1 ]
}

@test "recusa nome inválido" {
  run "$PEER" add "../x"
  [ "$status" -ne 0 ]
  run "$PEER" add ""
  [ "$status" -ne 0 ]
}

@test "list mostra nome e IP de cada dispositivo" {
  "$PEER" add celular
  "$PEER" add notebook
  run "$PEER" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"celular"*"10.8.0.2"* ]]
  [[ "$output" == *"notebook"*"10.8.0.3"* ]]
}

@test "servidor fora do .1: o primeiro dispositivo não colide com o IP do servidor" {
  export WG_SERVER_IP=10.8.0.2
  run "$PEER" add celular
  [ "$status" -eq 0 ]
  grep -qx "AllowedIPs = 10.8.0.3/32" "$SANDBOX/wg/wg0.conf"
}
