#!/usr/src/app
$null = Find-Module -Name Az | Install-Module -Force
$null = Install-Module Az.ResourceGraph -Force
$null = Install-Module -Name Az.Accounts -Force
$null = Install-Module -Name Pester -Force

$secpasswd = ConvertTo-SecureString $env:SERVICE_PRINCIPAL_PASS -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($env:SERVICE_PRINCIPAL, $secpasswd)

Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $env:TENANT_ID -Subscription $env:SUBSCRIPTION_ID

Write-Host "Welcome to the script for deploying your Shared Services"
./Orchestration/OrchestrationService/ModuleConfigurationDeployment.ps1 -TearDownEnvironment -DefinitionPath ./Environments/SharedServices/definition.json

