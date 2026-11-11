#!/usr/bin/env sh
# Roda os testes do banco: cada arquivo de tests/ só pode imprimir linhas se algum teste falhar.
# Uso: ./scripts/test.sh [arquivo.db]     (padrão: mercurium.db, criado antes pelo build.sh)
set -eu

cd "$(dirname "$0")/.."
DB="${1:-mercurium.db}"

if [ ! -f "$DB" ]; then
    echo "Banco $DB não encontrado. Rode ./scripts/build.sh antes." >&2
    exit 1
fi

failed=0
for test in tests/*.sql; do
    output=$(sqlite3 -bail "$DB" ".read $test")
    if [ -n "$output" ]; then
        echo "✗ $test"
        echo "$output" | sed 's/^/    /'
        failed=1
    else
        echo "✓ $test"
    fi
done

exit $failed
