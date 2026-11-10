#!/usr/bin/env sh
# Recria o banco do zero: apaga o arquivo e aplica, em ordem, os scripts de scripts/plano.txt.
# Uso: ./scripts/build.sh [arquivo.db]     (padrão: mercurium.db)
set -eu

cd "$(dirname "$0")/.."
DB="${1:-mercurium.db}"

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 não encontrado. Instale o SQLite 3 (https://sqlite.org/download.html) e rode de novo." >&2
    exit 1
fi

rm -f "$DB" "$DB-journal" "$DB-wal" "$DB-shm"

grep -v '^#' scripts/plano.txt | grep -v '^[[:space:]]*$' | while IFS= read -r script; do
    script=$(printf '%s' "$script" | tr -d '\r')
    echo "-> $script"
    # -bail: para no primeiro erro, em vez de seguir e deixar o banco pela metade.
    sqlite3 -bail "$DB" ".read $script"
done

# O banco só é considerado pronto se passar nas duas verificações.
INTEGRITY=$(sqlite3 "$DB" "PRAGMA integrity_check;")
FOREIGN_KEYS=$(sqlite3 "$DB" "PRAGMA foreign_key_check;")
if [ "$INTEGRITY" != "ok" ] || [ -n "$FOREIGN_KEYS" ]; then
    echo "Falha na verificação do banco: $INTEGRITY $FOREIGN_KEYS" >&2
    exit 1
fi

echo "Banco $DB criado: $(sqlite3 "$DB" "SELECT count(*) FROM customer_order;") pedidos, $(sqlite3 "$DB" "SELECT count(*) FROM product;") produtos."
