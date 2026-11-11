# Roda os testes do banco: cada arquivo de tests/ só pode imprimir linhas se algum teste falhar.
# Uso: .\scripts\test.ps1 [-Database arquivo.db]     (padrão: mercurium.db, criado antes pelo build.ps1)
param([string]$Database = "mercurium.db")

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path $Database)) { throw "Banco $Database não encontrado. Rode .\scripts\build.ps1 antes." }

$failed = $false
foreach ($test in Get-ChildItem "tests" -Filter "*.sql" | Sort-Object Name) {
    $output = & sqlite3 -bail $Database ".read tests/$($test.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Erro ao rodar $($test.Name)" }
    if ($output) {
        Write-Host "✗ tests/$($test.Name)"
        $output | ForEach-Object { Write-Host "    $_" }
        $failed = $true
    } else {
        Write-Host "✓ tests/$($test.Name)"
    }
}

if ($failed) { exit 1 }
