New-Item -ItemType Directory C:\DSC\Demo -Force | Out-Null
Set-Location C:\DSC\Demo

. .\DemoConfig.ps1
DemoConfig -NodeName @("client1","client2") -OutputPath .\DemoConfig
