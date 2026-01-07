<# 简化版测试脚本：仅在执行时打印信息，便于本地调试。 #>

Write-Host "test-update.ps1: start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Working directory: $(Get-Location)"
Write-Host "User: $env:USERNAME"
Write-Host "WEBHOOK_SECRET (env): $env:WEBHOOK_SECRET"
Write-Host "Note: This is a local stub. No network requests will be performed."

# 显示传入参数（如果通过命令行传入）
if ($args -and $args.Length -gt 0) {
    Write-Host "Args:" ($args -join ' ')
}

Write-Host "test-update.ps1: end $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

exit 0
