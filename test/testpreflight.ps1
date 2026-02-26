#$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
#$BASE="http://127.0.0.1:48443/i/$ID"

#curl.exe -sS -X POST "$BASE/preflight/run" `
  #-H "Content-Type: application/json" `
  #-d '{"node_id":"node-01"}'

$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"

# BOM無しUTF-8でJSONを書き出し
#$json = '{"node_id":"node-01"}'
#[System.IO.File]::WriteAllText("req.json", $json, (New-Object System.Text.UTF8Encoding($false)))

#curl.exe -sS -X POST "$BASE/preflight/run" `
  #-H "Content-Type: application/json" `
  #--data-binary "@req.json"

  #$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
#$BASE="http://127.0.0.1:48443/i/$ID"

$body = @{ node_id = "node-01" } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$BASE/preflight/run" -ContentType "application/json" -Body $body

