$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"
$NOW=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()

@"
{"event_id":"pev-001","node_id":"node-99","ts_unix_ms":$NOW,"kind":"change","summary":"pending injected"}
"@ | Set-Content -Encoding ASCII .\p.json

# pendingに追加
curl.exe -sS -X POST "$BASE/pending/add" -H "Content-Type: application/json" --data-binary "@p.json"

# pending確認（itemsに入る）
curl.exe -sS "$BASE/pending"

# reconcile実行（自分自身をpeerにして pull→queue enqueue）
curl.exe -sS -X POST "$BASE/reconcile/run?peer=http://127.0.0.1:48443"

# queueに入ったか確認（poll）
curl.exe -sS "$BASE/queue/poll?worker=node-01&limit=10"