$ID="01963b5c-7d3a-7a3a-8d8c-0e3b63b9d2c1"
$base="http://127.0.0.1:48443/i/$ID/token"

Invoke-RestMethod -Method Get  -Uri "$base/status"
Invoke-RestMethod -Method Post -Uri "$base/claim"  -ContentType "application/json" -Body (@{node_id="node-01"} | ConvertTo-Json)
Invoke-RestMethod -Method Post -Uri "$base/renew"  -ContentType "application/json" -Body (@{node_id="node-01"} | ConvertTo-Json)
Invoke-RestMethod -Method Post -Uri "$base/renew"  -ContentType "application/json" -Body (@{node_id="node-99"} | ConvertTo-Json)