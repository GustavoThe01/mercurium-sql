# Recria o banco do zero: apaga o arquivo e aplica, em ordem, os scripts de scripts/plano.txt.
# Uso: .\scripts\build.ps1 [-Database arquivo.db]     (padrão: mercurium.db)
param([string]$Database = "mercurium.db")

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Error "sqlite3 não encontrado. Instale com: winget install SQLite.SQLite"
}

foreach ($suffix in "", "-journal", "-wal", "-shm") {
    Remove-Item "$Database$suffix" -ErrorAction SilentlyContinue
}

# .read faz o próprio sqlite3 ler o arquivo. Redirecionar o conteúdo pelo PowerShell 5.1 trocaria
# a codificação e estragaria os acentos.
$scripts = Get-Content "scripts/plano.txt" -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith("#") }
foreach ($script in $scripts) {
    Write-Host "-> $script"
    & sqlite3 -bail $Database ".read $script"
    if ($LASTEXITCODE -ne 0) { throw "Falha em $script" }
}

$integrity = & sqlite3 $Database "PRAGMA integrity_check;"
$foreignKeys = & sqlite3 $Database "PRAGMA foreign_key_check;"
if ($integrity -ne "ok" -or $foreignKeys) { throw "Falha na verificação do banco: $integrity $foreignKeys" }

$orders = & sqlite3 $Database "SELECT count(*) FROM customer_order;"
$products = & sqlite3 $Database "SELECT count(*) FROM product;"
Write-Host "Banco $Database criado: $orders pedidos, $products produtos."
