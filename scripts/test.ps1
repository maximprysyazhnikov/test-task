$ErrorActionPreference = 'Stop'
$baseUrl = 'http://localhost:8080'

# Verify the public endpoint and its exact contract.
$health = Invoke-RestMethod -Uri "$baseUrl/healthz"
if ($health.status -ne 'ok' -or $health.service -ne 'app' -or -not $health.env) {
    throw "Unexpected health response: $($health | ConvertTo-Json -Compress)"
}
Write-Host "Healthcheck OK: $($health | ConvertTo-Json -Compress)"

# The app echoes the ID that nginx forwarded, making the full path observable.
$requestId = [guid]::NewGuid().ToString()
$response = Invoke-WebRequest -UseBasicParsing -Headers @{ 'X-Request-ID' = $requestId } -Uri "$baseUrl/healthz"
if ($response.Headers['X-Request-ID'] -ne $requestId) {
    throw 'X-Request-ID was not passed through end to end.'
}
Write-Host "Request-ID pass-through request OK: $requestId"

# Background jobs work in both Windows PowerShell 5.1 and PowerShell 7.
$jobs = 1..20 | ForEach-Object {
    Start-Job -ScriptBlock {
        try {
            (Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8080/healthz').StatusCode
        } catch {
            [int]$_.Exception.Response.StatusCode
        }
    }
}
$statuses = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$summary = $statuses | Group-Object | Sort-Object Name
$summary | ForEach-Object { Write-Host ("HTTP {0}: {1}" -f $_.Name, $_.Count) }
if (200 -notin $statuses -or 429 -notin $statuses) {
    throw "Rate-limit test failed: expected both HTTP 200 and 429; observed: $($statuses -join ', ')."
}
Write-Host 'Rate-limit OK: both HTTP 200 and HTTP 429 were observed.'
