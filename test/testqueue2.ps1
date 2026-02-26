$NOW=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()
@"
{"event_id":"ev-001","node_id":"node-01","ts_unix_ms":$NOW,"kind":"change","summary":"touch a.txt"}
"@ | Set-Content -Encoding ASCII .\req.json

curl.exe -sS -X POST "$BASE/queue/enqueue" -H "Content-Type: application/json" --data-binary "@req.json"
curl.exe -sS "$BASE/queue/poll?worker=node-01&limit=10"
@"
{"event_id":"ev-001","worker_node_id":"node-01","message":"done"}
"@ | Set-Content -Encoding ASCII .\ack.json
curl.exe -sS -X POST "$BASE/queue/ack" -H "Content-Type: application/json" --data-binary "@ack.json"