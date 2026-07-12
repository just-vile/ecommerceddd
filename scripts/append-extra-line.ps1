param(
    [string[]]$Paths = @(
        "src/Services/EcommerceDDD.CustomerManagement/EcommerceDDD.CustomerManagement.csproj",
        "src/Services/EcommerceDDD.CustomerManagement.Tests/EcommerceDDD.CustomerManagement.Tests.csproj",
        "src/Services/EcommerceDDD.InventoryManagement/EcommerceDDD.InventoryManagement.csproj",
        "src/Services/EcommerceDDD.InventoryManagement.Tests/EcommerceDDD.InventoryManagement.Tests.csproj",
        "src/Services/EcommerceDDD.OrderProcessing/EcommerceDDD.OrderProcessing.csproj",
        "src/Services/EcommerceDDD.OrderProcessing.Tests/EcommerceDDD.OrderProcessing.Tests.csproj",
        "src/Services/EcommerceDDD.PaymentProcessing/EcommerceDDD.PaymentProcessing.csproj",
        "src/Services/EcommerceDDD.PaymentProcessing.Tests/EcommerceDDD.PaymentProcessing.Tests.csproj",
        "src/Services/EcommerceDDD.ProductCatalog/EcommerceDDD.ProductCatalog.csproj",
        "src/Services/EcommerceDDD.ProductCatalog.Tests/EcommerceDDD.ProductCatalog.Tests.csproj",
        "src/Services/EcommerceDDD.QuoteManagement/EcommerceDDD.QuoteManagement.csproj",
        "src/Services/EcommerceDDD.QuoteManagement.Tests/EcommerceDDD.QuoteManagement.Tests.csproj",
        "src/Services/EcommerceDDD.ShipmentProcessing/EcommerceDDD.ShipmentProcessing.csproj",
        "src/Services/EcommerceDDD.ShipmentProcessing.Tests/EcommerceDDD.ShipmentProcessing.Tests.csproj",
        "src/EcommerceDDD.Spa/package.json"
    )
)

$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($relativePath in $Paths) {
    $fullPath = Join-Path $repoRoot $relativePath

    if (-not (Test-Path $fullPath)) {
        Write-Warning "Skipping missing file: $relativePath"
        continue
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    if (-not $content.EndsWith("`n")) {
        $content += "`n"
    }

    $content += "`n"
    [System.IO.File]::WriteAllText($fullPath, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated $relativePath"
}

Write-Host "Done."
