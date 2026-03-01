function Zm-PostJson($url, $obj) {
  $body = $obj | ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body
}

function Zm-Get($url) {
  Invoke-RestMethod -Method Get -Uri $url
}