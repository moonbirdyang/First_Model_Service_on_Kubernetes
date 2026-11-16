param([int]$MaxSeconds = 960)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$env:KUBECONFIG = Join-Path $PSScriptRoot '.kube\minikube-config'
$env:MINIKUBE_HOME = Join-Path $PSScriptRoot '.minikube'
$mini = Join-Path $PSScriptRoot 'tools\minikube.exe'
$evidence = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
function K {
    $result = & $mini -p iris-lab kubectl -- --kubeconfig $env:KUBECONFIG --context iris-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $args" }
    return $result
}
function Save-Text([string]$Name, [object]$Value) {
    [IO.File]::WriteAllText((Join-Path $evidence $Name), ($Value -join "`n"), (New-Object Text.UTF8Encoding($false)))
}
function Snapshot([string]$Name) {
    $hpa = (K get hpa iris-api -o json) -join "`n" | ConvertFrom-Json
    $pods = (K get pods -l app=iris-api -o json) -join "`n" | ConvertFrom-Json
    $deployment = (K get deployment iris-api -o json) -join "`n" | ConvertFrom-Json
    $snapshot = [ordered]@{
        time = [DateTimeOffset]::Now.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
        hpa = $hpa
        pods = $pods
        deployment = $deployment
    }
    Save-Text "$Name.json" ($snapshot | ConvertTo-Json -Depth 60)
    return $snapshot
}

$base = Snapshot 'before-load'
Save-Text 'before-load.txt' (K get 'pods,svc,hpa')
$forwardScript = Join-Path $PSScriptRoot 'lab.ps1'
$forward = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$forwardScript+'"'),'forward') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'port-forward.log') -RedirectStandardError (Join-Path $evidence 'port-forward.err')
try {
    $healthy = $false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod http://127.0.0.1:8080/healthz -TimeoutSec 3
            if ($health.ok) { $healthy=$true; break }
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $healthy) { throw 'API did not become reachable' }
    $prediction = Invoke-RestMethod http://127.0.0.1:8080/predict -Method Post -ContentType 'application/json' -Body '{"instances":[[5.1,3.5,1.4,0.2]]}'
    if ($prediction.predictions[0] -ne 0) { throw 'Unexpected prediction' }
    Save-Text 'api-result.json' (@{health=$health;prediction=$prediction;url='http://127.0.0.1:8080/predict';requestBody='{"instances":[[5.1,3.5,1.4,0.2]]}'} | ConvertTo-Json -Depth 8)
    Write-Output 'API verified: healthz OK, predictions=[0]'
    K delete job iris-load --ignore-not-found
    K apply -f loadtest.yaml
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $maxReplicas=1
    $scaled=$false
    $complete=$false
    $recovered=$false
    $history=New-Object Collections.Generic.List[object]
    while ($timer.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $snapshot=Snapshot 'latest'
        $hpa=$snapshot.hpa
        $replicas=[int]$snapshot.deployment.status.replicas
        $ready=[int]$snapshot.deployment.status.readyReplicas
        $cpu=$null
        if ($hpa.status.currentMetrics.Count -gt 0) { $cpu=$hpa.status.currentMetrics[0].resource.current.averageUtilization }
        $job=(K get job iris-load -o json) -join "`n" | ConvertFrom-Json
        if ($job.status.succeeded -ge 1) { $complete=$true }
        $row=[ordered]@{time=$snapshot.time;elapsedSeconds=[int]$timer.Elapsed.TotalSeconds;replicas=$replicas;readyReplicas=$ready;cpuPercent=$cpu;jobComplete=$complete}
        $history.Add($row)
        Save-Text 'hpa-history.json' ($history.ToArray() | ConvertTo-Json -Depth 8)
        Write-Output ($row | ConvertTo-Json -Compress)
        if ($replicas -gt $maxReplicas) {
            $maxReplicas=$replicas
            Save-Text 'during-load.json' ($snapshot | ConvertTo-Json -Depth 60)
            Save-Text 'during-load.txt' (K get 'pods,hpa')
        }
        if ($replicas -gt 1 -and $ready -gt 1) { $scaled=$true }
        if ($scaled -and $complete -and $replicas -eq 1 -and $ready -eq 1) {
            $recovered=$true
            Save-Text 'after-load.json' ($snapshot | ConvertTo-Json -Depth 60)
            Save-Text 'after-load.txt' (K get 'pods,hpa')
            break
        }
        if ($job.status.failed -ge 1) { throw 'Load job failed; inspect logs' }
        Start-Sleep -Seconds 15
    }
    Save-Text 'hey-results.txt' (K logs job/iris-load)
    Save-Text 'hpa-description.txt' (K describe hpa iris-api)
    Save-Text 'hpa-events.json' (K get events --field-selector involvedObject.name=iris-api -o json)
    $result=[ordered]@{apiVerified=$true;maxReplicas=$maxReplicas;scaleUpVerified=$scaled;loadCompleted=$complete;scaleDownVerified=$recovered;elapsedSeconds=[int]$timer.Elapsed.TotalSeconds}
    Save-Text 'verification-result.json' ($result | ConvertTo-Json)
    Write-Output ($result | ConvertTo-Json)
    if (-not ($scaled -and $complete -and $recovered)) { throw 'Autoscaling verification incomplete; see evidence files' }
} finally {
    if (-not $forward.HasExited) { & taskkill.exe /PID $forward.Id /T /F | Out-Null }
}
