param(
    [string]$Deployment = "yoyo-service",
    [int]$TimeoutSeconds = 60
)

Write-Host "Checking rollout for deployment: $Deployment"
Write-Host "Timeout: $TimeoutSeconds seconds"

kubectl rollout status deployment/$Deployment --timeout="${TimeoutSeconds}s"

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Rollout completed successfully."
    exit 0
}
else {
    Write-Host "FAILURE: Rollout did not complete within $TimeoutSeconds seconds."
    exit 1
}