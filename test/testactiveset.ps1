$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"
$now=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

@"
{"node_id":"node-01","site":"site-a","role":"governor","ts_unix":$now}
"@ | Set-Content -Encoding ASCII .\hb1.json

@"
{"node_id":"node-02","site":"site-a","role":"member","ts_unix":$now}
"@ | Set-Content -Encoding ASCII .\hb2.json

curl.exe -sS -X POST "$BASE/hb" -H "Content-Type: application/json" --data-binary "@hb1.json"
curl.exe -sS -X POST "$BASE/hb" -H "Content-Type: application/json" --data-binary "@hb2.json"

curl.exe -sS "$BASE/bench/activeset?window=300"