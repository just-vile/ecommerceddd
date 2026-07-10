#!/usr/bin/env pwsh
<#!
.SYNOPSIS
  Build and push EcommerceDDD Docker images to GHCR from a local machine.
 
.DESCRIPTION
  Builds one or more services using Dockerfiles in this repository and pushes
  images to ghcr.io/<user>/ecommerceddd-<service>:<tag>.
 
.EXAMPLE
  ./scripts/build-push-images.ps1 -GhcrUser just-vile -Tag main-latest
 
.EXAMPLE
  ./scripts/build-push-images.ps1 -GhcrUser just-vile -GhcrToken $env:GHCR_TOKEN -Services apigateway,identityserver -Tag sha-abc1234
 
.NOTES
  - Run from anywhere; the script resolves repository root automatically.
  - Docker build context is repository root for all services.
#>
 
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $GhcrUser,
 
    [Parameter(Mandatory = $false)]
    [string] $GhcrToken,
 
    [Parameter(Mandatory = $false)]
    [string] $Registry = "ghcr.io",
 
    [Parameter(Mandatory = $false)]
    [string] $Tag = "main-latest",
 
    [Parameter(Mandatory = $false)]
    [string[]] $Services = @("all"),
 
    [Parameter(Mandatory = $false)]
    [switch] $SkipLogin,
 
    [Parameter(Mandatory = $false)]
    [switch] $NoCache
)
 
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
 
function Require-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}
 
function Invoke-Checked([string] $Command, [string[]] $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command $($Arguments -join ' ')"
    }
}
 
$serviceMap = @{
    "apigateway"           = "src/Crosscutting/EcommerceDDD.ApiGateway/Dockerfile"
    "identityserver"       = "src/Crosscutting/EcommerceDDD.IdentityServer/Dockerfile"
    "signalr"              = "src/Crosscutting/EcommerceDDD.SignalR/Dockerfile"
    "spa"                  = "src/EcommerceDDD.Spa/Dockerfile"
    "customer-management"  = "src/Services/EcommerceDDD.CustomerManagement/Dockerfile"
    "product-catalog"      = "src/Services/EcommerceDDD.ProductCatalog/Dockerfile"
    "inventory-management" = "src/Services/EcommerceDDD.InventoryManagement/Dockerfile"
    "quote-management"     = "src/Services/EcommerceDDD.QuoteManagement/Dockerfile"
    "order-processing"     = "src/Services/EcommerceDDD.OrderProcessing/Dockerfile"
    "payment-processing"   = "src/Services/EcommerceDDD.PaymentProcessing/Dockerfile"
    "shipment-processing"  = "src/Services/EcommerceDDD.ShipmentProcessing/Dockerfile"
}
 
Require-Command "docker"
 
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptPath "..")
 
if (-not $SkipLogin) {
    if ([string]::IsNullOrWhiteSpace($GhcrToken)) {
        $GhcrToken = [Environment]::GetEnvironmentVariable("GHCR_TOKEN")
    }
 
    if ([string]::IsNullOrWhiteSpace($GhcrToken)) {
        throw "GHCR token is required. Pass -GhcrToken or set GHCR_TOKEN env var."
    }
 
    Write-Host "Logging in to $Registry as $GhcrUser..." -ForegroundColor Cyan
    $GhcrToken | docker login $Registry -u $GhcrUser --password-stdin
    if ($LASTEXITCODE -ne 0) {
        throw "Docker login failed for $Registry."
    }
}
 
$requested = @($Services | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne "" })
if ($requested.Count -eq 0 -or $requested -contains "all") {
    $targets = @($serviceMap.Keys | Sort-Object)
} else {
    $invalid = @($requested | Where-Object { -not $serviceMap.ContainsKey($_) })
    if ($invalid.Count -gt 0) {
        $validList = ($serviceMap.Keys | Sort-Object) -join ", "
        throw "Unknown service(s): $($invalid -join ', '). Valid values: $validList, all"
    }
    $targets = @($requested)
}
 
Write-Host "Building and pushing $($targets.Count) service(s) with tag '$Tag'..." -ForegroundColor Cyan
 
foreach ($service in $targets) {
    $dockerfile = Join-Path $repoRoot $serviceMap[$service]
    if (-not (Test-Path $dockerfile)) {
        throw "Dockerfile not found for service '$service': $dockerfile"
    }
 
    $image = "$Registry/$GhcrUser/ecommerceddd-$service`:$Tag"
 
    $buildArgs = @("build", "-f", $dockerfile, "-t", $image)
    if ($NoCache) {
        $buildArgs += "--no-cache"
    }
    $buildArgs += $repoRoot
 
    Write-Host "`n[$service] Building $image" -ForegroundColor Yellow
    Invoke-Checked -Command "docker" -Arguments $buildArgs
 
    Write-Host "[$service] Pushing $image" -ForegroundColor Yellow
    Invoke-Checked -Command "docker" -Arguments @("push", $image)
}
 
Write-Host "`nCompleted successfully." -ForegroundColor Green
Write-Host "Images pushed to: $Registry/$GhcrUser/ecommerceddd-<service>:$Tag"