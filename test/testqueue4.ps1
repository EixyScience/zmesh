$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"
$NOW=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()

@"
{"event_id":"pev-001","node_id":"node-99","ts_unix_ms":$NOW,"kind":"change","summary":"pending injected"}
"@ | Set-Content -Encoding ASCII .\p.json

# ★ここが unknown endpoint になるかどうかで確定する
curl.exe -sS -X POST "$BASE/pending/add" -H "Content-Type: application/json" --data-binary "@p.json"

# 入ったか確認
curl.exe -sS "$BASE/pending"