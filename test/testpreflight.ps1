
#$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
#$BASE="http://127.0.0.1:48443/i/$ID"

#$body = @{ node_id = "node-01" } | ConvertTo-Json -Compress
#Invoke-RestMethod -Method Post -Uri "$BASE/preflight/run" -ContentType "application/json" -Body $body


$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$BASE="http://127.0.0.1:48443/i/$ID"
$uri="$BASE/preflight/run?main=./main&state=./zmesh.state"

$body = @{ node_id = "node-01" } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body $body