param(
    [int]$DurationSeconds = 60
)

$Total = 0
$Success = 0
$Failures = 0
$Versions = @{}

Write-Host "Starting Service-level traffic test"
Write-Host "Target: http://yoyo-service/version"
Write-Host "Duration: $DurationSeconds seconds"
Write-Host "----------------------------------------"

$EndTime = (Get-Date).AddSeconds($DurationSeconds)

while ((Get-Date) -lt $EndTime) {

    $Total++
    $Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

    $Result = kubectl exec traffic-client -- curl -sS --max-time 2 `
        -w "|HTTP:%{http_code}" `
        http://yoyo-service/version 2>&1

    $Text = ($Result | Out-String).Trim()

    if ($Text -match "\|HTTP:(\d{3})") {
        $Status = $Matches[1]
        $Body = ($Text -replace "\|HTTP:\d{3}", "").Trim()
    }
    else {
        $Status = "ERROR"
        $Body = $Text
    }

    if ($Status -eq "200") {

        $Success++

        if ($Body -match "version=([^\s]+)") {
            $Version = $Matches[1]

            if ($Versions.ContainsKey($Version)) {
                $Versions[$Version]++
            }
            else {
                $Versions[$Version] = 1
            }
        }

        Write-Host "$Timestamp status=$Status $Body"
    }
    else {
        $Failures++
        Write-Host "$Timestamp status=$Status error=$Body"
    }

    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "========== TRAFFIC SUMMARY =========="
Write-Host "Total requests : $Total"
Write-Host "Successes      : $Success"
Write-Host "Failures       : $Failures"

foreach ($Version in $Versions.Keys) {
    Write-Host "Version $Version     : $($Versions[$Version])"
}

Write-Host "====================================="