$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"

# dirty を立てる
@'
{"node_id":"node-01","dirty":true,"dirty_since_unix_ms":0}
'@ | Set-Content -Encoding ASCII .\pset.json
curl.exe -sS -X POST "$BASE/pending/set" -H "Content-Type: application/json" --data-binary "@pset.json"

# 確認
curl.exe -sS "$BASE/pending/status"

# clear
@'
{"node_id":"node-01"}
'@ | Set-Content -Encoding ASCII .\pclr.json
curl.exe -sS -X POST "$BASE/pending/clear" -H "Content-Type: application/json" --data-binary "@pclr.json"
curl.exe -sS "$BASE/pending/status"