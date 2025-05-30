Remove-Item -Path $PSScriptRoot\Win11Readiness.ps1 -Force

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Columbo818/Win11Readiness/main/Win11Readiness.ps1" -Method Get -OutFile "$PSScriptRoot\Win11Readiness.ps1"
