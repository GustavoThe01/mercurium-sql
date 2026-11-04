-- V001: schema inicial do Mercurium.
-- O modelo e as decisões estão em docs/der.md.
--
-- Todas as tabelas são STRICT: sem isso, o SQLite aceitaria texto numa coluna INTEGER.
-- Dinheiro fica em centavos (INTEGER) e datas em ISO 8601 (TEXT), como decidi no ADR 0001.

-- O SQLite vem com as chaves estrangeiras desligadas, e esse PRAGMA vale por conexão.
-- Precisa ficar fora da transação: dentro dela o comando é ignorado sem aviso.
PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

CREATE TABLE customer (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL CHECK (length(trim(name)) >= 2),
    email      TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (email LIKE '%_@_%._%'),
    document   TEXT NOT NULL UNIQUE CHECK (length(document) = 11 AND document NOT GLOB '*[^0-9]*'),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

CREATE TABLE address (
    id          INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customer (id) ON DELETE CASCADE,
    street      TEXT NOT NULL CHECK (length(trim(street)) > 0),
    number      TEXT NOT NULL CHECK (length(trim(number)) > 0),
    city        TEXT NOT NULL CHECK (length(trim(city)) > 0),
    state       TEXT NOT NULL CHECK (length(state) = 2 AND state NOT GLOB '*[^A-Z]*'),
    zip_code    TEXT NOT NULL CHECK (length(zip_code) = 8 AND zip_code NOT GLOB '*[^0-9]*'),
    is_primary  INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1))
) STRICT;

-- Índice único parcial: cada cliente tem no máximo um endereço principal.
CREATE UNIQUE INDEX ux_address_one_primary_per_customer
    ON address (customer_id)
    WHERE is_primary = 1;

CREATE TABLE category (
    id        INTEGER PRIMARY KEY,
    name      TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(trim(name)) > 0),
    parent_id INTEGER REFERENCES category (id) ON DELETE RESTRICT,
    CHECK (parent_id IS NULL OR parent_id <> id)
) STRICT;

CREATE TABLE product (
    id          INTEGER PRIMARY KEY,
    sku         TEXT NOT NULL UNIQUE CHECK (length(sku) BETWEEN 3 AND 20),
    name        TEXT NOT NULL CHECK (length(trim(name)) >= 2),
    description TEXT NOT NULL DEFAULT '',
    price_cents INTEGER NOT NULL CHECK (price_cents > 0),
    category_id INTEGER NOT NULL REFERENCES category (id) ON DELETE RESTRICT,
    active      INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1))
) STRICT;

CREATE TABLE inventory (
    product_id       INTEGER PRIMARY KEY REFERENCES product (id) ON DELETE CASCADE,
    quantity         INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    minimum_quantity INTEGER NOT NULL DEFAULT 0 CHECK (minimum_quantity >= 0)
) STRICT;

-- O endereço de entrega é uma cópia (snapshot): editar o cadastro do cliente depois
-- não pode mudar para onde um pedido antigo foi enviado.
CREATE TABLE customer_order (
    id                INTEGER PRIMARY KEY,
    customer_id       INTEGER NOT NULL REFERENCES customer (id) ON DELETE RESTRICT,
    status            TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED')),
    shipping_street   TEXT NOT NULL,
    shipping_number   TEXT NOT NULL,
    shipping_city     TEXT NOT NULL,
    shipping_state    TEXT NOT NULL CHECK (length(shipping_state) = 2),
    shipping_zip_code TEXT NOT NULL CHECK (length(shipping_zip_code) = 8),
    created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

CREATE TABLE order_item (
    order_id         INTEGER NOT NULL REFERENCES customer_order (id) ON DELETE CASCADE,
    product_id       INTEGER NOT NULL REFERENCES product (id) ON DELETE RESTRICT,
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents > 0),
    PRIMARY KEY (order_id, product_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE payment (
    id           INTEGER PRIMARY KEY,
    order_id     INTEGER NOT NULL REFERENCES customer_order (id) ON DELETE RESTRICT,
    method       TEXT NOT NULL CHECK (method IN ('PIX', 'CARD', 'BOLETO')),
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    status       TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REFUSED')),
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

-- IN e OUT guardam a quantidade sempre positiva; só o ajuste (ADJUSTMENT) pode ser negativo.
CREATE TABLE stock_movement (
    id         INTEGER PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES product (id) ON DELETE RESTRICT,
    order_id   INTEGER REFERENCES customer_order (id) ON DELETE RESTRICT,
    type       TEXT NOT NULL CHECK (type IN ('IN', 'OUT', 'ADJUSTMENT')),
    quantity   INTEGER NOT NULL,
    reason     TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    CHECK ((type = 'ADJUSTMENT' AND quantity <> 0) OR (type <> 'ADJUSTMENT' AND quantity > 0))
) STRICT;

CREATE TABLE review (
    id          INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customer (id) ON DELETE CASCADE,
    product_id  INTEGER NOT NULL REFERENCES product (id) ON DELETE CASCADE,
    rating      INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE (customer_id, product_id)
) STRICT;

COMMIT;
