$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"
$NOW=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()

# enqueue（同じevent_idを2回 → 2回目は Inserted=false が期待）
curl.exe -sS -X POST "$BASE/queue/enqueue" -H "Content-Type: application/json" `
  -d "{\"event_id\":\"ev-001\",\"node_id\":\"node-01\",\"ts_unix_ms\":$NOW,\"kind\":\"change\",\"summary\":\"touch a.txt\"}"

curl.exe -sS -X POST "$BASE/queue/enqueue" -H "Content-Type: application/json" `
  -d "{\"event_id\":\"ev-001\",\"node_id\":\"node-01\",\"ts_unix_ms\":$NOW,\"kind\":\"change\",\"summary\":\"touch a.txt\"}"

# poll（worker=node-01）
curl.exe -sS "$BASE/queue/poll?worker=node-01&limit=10"

# ack
curl.exe -sS -X POST "$BASE/queue/ack" -H "Content-Type: application/json" `
  -d "{\"event_id\":\"ev-001\",\"worker_node_id\":\"node-01\",\"message\":\"done\"}"