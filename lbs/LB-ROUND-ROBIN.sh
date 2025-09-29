# Get all httpbin pod names
$pods = kubectl get pods -l app=httpbin -o jsonpath='{.items[*].metadata.name}'

Write-Host "`nRequest Distribution Across Pods:" -ForegroundColor Cyan
foreach ($pod in $pods -split ' ') {
    Write-Host "`n--- Pod: $pod ---" -ForegroundColor Yellow
    
    # Get the pod IP
    $podIP = kubectl get pod $pod -o jsonpath='{.status.podIP}'
    Write-Host "Pod IP: $podIP" -ForegroundColor Gray
    
    # Check request count on this pod
    $reqCount = kubectl exec $pod -c istio-proxy -- pilot-agent request GET stats 2>$null | Select-String "istio_requests_total.*response_code.200" | Select-String "fortio"
    
    if ($reqCount -and $reqCount -match ':.*?(\d+)$') {
        Write-Host "Requests received: $($matches[1])" -ForegroundColor Green
    } else {
        Write-Host "Requests received: 0" -ForegroundColor Gray
    }
}