-- V002: views, triggers de regra de negócio, auditoria e updated_at automático.
-- Rode depois de V001 e dos dados de exemplo (S001). O seed carrega pedidos antigos e monta o estoque
-- no fim; com estes triggers ativos antes dele, cada item histórico tentaria baixar um estoque que ainda não existe.
-- O porquê de cada regra estar no banco, e não só na aplicação, está no ADR 0002.

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ===========================================================================
-- Views
-- Regra usada em todas: só conta como faturamento o pedido pago, enviado ou entregue.
-- ===========================================================================

-- Um pedido por linha, com a quantidade de itens e o total calculado a partir dos itens.
CREATE VIEW vw_order_summary AS
SELECT o.id                                         AS order_id,
       o.customer_id,
       c.name                                       AS customer_name,
       o.status,
       o.created_at,
       COUNT(i.product_id)                          AS item_lines,
       COALESCE(SUM(i.quantity), 0)                 AS units,
       COALESCE(SUM(i.quantity * i.unit_price_cents), 0) AS total_cents,
       COALESCE((SELECT SUM(p.amount_cents)
                 FROM payment p
                 WHERE p.order_id = o.id AND p.status = 'APPROVED'), 0) AS paid_cents
FROM customer_order o
JOIN customer c ON c.id = o.customer_id
LEFT JOIN order_item i ON i.order_id = o.id
GROUP BY o.id;

-- Valor que cada cliente já gerou. Clientes sem compra aparecem com zero (LEFT JOIN).
CREATE VIEW vw_customer_lifetime_value AS
SELECT c.id                                   AS customer_id,
       c.name,
       COUNT(s.order_id)                      AS orders,
       COALESCE(SUM(s.total_cents), 0)        AS lifetime_value_cents,
       CASE WHEN COUNT(s.order_id) = 0 THEN 0
            ELSE SUM(s.total_cents) / COUNT(s.order_id) END AS average_ticket_cents,
       MIN(s.created_at)                      AS first_order_at,
       MAX(s.created_at)                      AS last_order_at
FROM customer c
LEFT JOIN vw_order_summary s
       ON s.customer_id = c.id AND s.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY c.id;

-- Produtos ativos no estoque mínimo ou abaixo dele, com quanto falta para repor.
CREATE VIEW vw_low_stock AS
SELECT p.id                                   AS product_id,
       p.sku,
       p.name,
       inv.quantity,
       inv.minimum_quantity,
       inv.minimum_quantity - inv.quantity    AS missing
FROM inventory inv
JOIN product p ON p.id = inv.product_id
WHERE p.active = 1 AND inv.quantity <= inv.minimum_quantity;

-- ===========================================================================
-- Estoque: a movimentação é a fonte da verdade (regra 7)
-- Ninguém altera o saldo direto: grava uma movimentação, e o trigger atualiza o saldo.
-- ===========================================================================

CREATE TRIGGER trg_stock_movement_check_balance
BEFORE INSERT ON stock_movement
WHEN NEW.type = 'OUT' OR (NEW.type = 'ADJUSTMENT' AND NEW.quantity < 0)
BEGIN
    SELECT RAISE(ABORT, 'Estoque insuficiente para esta saída')
    WHERE COALESCE((SELECT quantity FROM inventory WHERE product_id = NEW.product_id), 0)
          < abs(NEW.quantity);
END;

CREATE TRIGGER trg_stock_movement_apply
AFTER INSERT ON stock_movement
BEGIN
    INSERT OR IGNORE INTO inventory (product_id, quantity) VALUES (NEW.product_id, 0);
    UPDATE inventory
    SET quantity = quantity + CASE NEW.type WHEN 'OUT' THEN -NEW.quantity ELSE NEW.quantity END
    WHERE product_id = NEW.product_id;
END;

-- O histórico é imutável: correção se faz com um ajuste novo, nunca editando o passado.
CREATE TRIGGER trg_stock_movement_immutable_update
BEFORE UPDATE ON stock_movement
BEGIN
    SELECT RAISE(ABORT, 'Movimentação de estoque não pode ser alterada; registre um ajuste');
END;

CREATE TRIGGER trg_stock_movement_immutable_delete
BEFORE DELETE ON stock_movement
BEGIN
    SELECT RAISE(ABORT, 'Movimentação de estoque não pode ser excluída; registre um ajuste');
END;

-- ===========================================================================
-- Itens do pedido: baixa de estoque na hora da venda (regra 2)
-- ===========================================================================

CREATE TRIGGER trg_order_item_only_pending
BEFORE INSERT ON order_item
BEGIN
    SELECT RAISE(ABORT, 'Só é possível incluir itens em pedido PENDING')
    WHERE (SELECT status FROM customer_order WHERE id = NEW.order_id) <> 'PENDING';
END;

-- A verificação do saldo acontece no trigger de stock_movement, que aborta tudo se faltar.
CREATE TRIGGER trg_order_item_take_stock
AFTER INSERT ON order_item
BEGIN
    INSERT INTO stock_movement (product_id, order_id, type, quantity, reason)
    VALUES (NEW.product_id, NEW.order_id, 'OUT', NEW.quantity, 'Venda do pedido ' || NEW.order_id);
END;

-- ===========================================================================
-- Status do pedido (regras 4 e 5)
-- ===========================================================================

CREATE TRIGGER trg_order_status_transition
BEFORE UPDATE OF status ON customer_order
WHEN NEW.status <> OLD.status
BEGIN
    SELECT RAISE(ABORT, 'Transição de status inválida')
    WHERE NOT (
           (OLD.status = 'PENDING' AND NEW.status IN ('PAID', 'CANCELLED'))
        OR (OLD.status = 'PAID'    AND NEW.status IN ('SHIPPED', 'CANCELLED'))
        OR (OLD.status = 'SHIPPED' AND NEW.status = 'DELIVERED')
    );
END;

CREATE TRIGGER trg_order_paid_requires_payment
BEFORE UPDATE OF status ON customer_order
WHEN NEW.status = 'PAID' AND OLD.status <> 'PAID'
BEGIN
    SELECT RAISE(ABORT, 'Os pagamentos aprovados não fecham o total do pedido')
    WHERE COALESCE((SELECT SUM(amount_cents) FROM payment
                    WHERE order_id = NEW.id AND status = 'APPROVED'), 0)
       <> COALESCE((SELECT SUM(quantity * unit_price_cents) FROM order_item
                    WHERE order_id = NEW.id), 0);
END;

-- Pedido cancelado devolve ao estoque o que tinha saído por causa dele.
CREATE TRIGGER trg_order_cancel_returns_stock
AFTER UPDATE OF status ON customer_order
WHEN NEW.status = 'CANCELLED' AND OLD.status <> 'CANCELLED'
BEGIN
    INSERT INTO stock_movement (product_id, order_id, type, quantity, reason)
    SELECT product_id, NEW.id, 'IN', SUM(quantity), 'Cancelamento do pedido ' || NEW.id
    FROM stock_movement
    WHERE order_id = NEW.id AND type = 'OUT'
    GROUP BY product_id;
END;

-- ===========================================================================
-- Avaliação só de quem comprou e recebeu (regra 6)
-- ===========================================================================

CREATE TRIGGER trg_review_requires_delivery
BEFORE INSERT ON review
BEGIN
    SELECT RAISE(ABORT, 'Só quem recebeu o produto pode avaliá-lo')
    WHERE NOT EXISTS (
        SELECT 1
        FROM customer_order o
        JOIN order_item i ON i.order_id = o.id
        WHERE o.customer_id = NEW.customer_id
          AND i.product_id = NEW.product_id
          AND o.status = 'DELIVERED'
    );
END;

-- ===========================================================================
-- updated_at automático
-- ALTER TABLE ... ADD COLUMN não aceita DEFAULT com função, então a coluna nasce sem valor,
-- é preenchida aqui, e os triggers cuidam das linhas novas e das alterações.
-- ===========================================================================

ALTER TABLE product ADD COLUMN updated_at TEXT;
ALTER TABLE customer_order ADD COLUMN updated_at TEXT;

UPDATE product SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
UPDATE customer_order SET updated_at = created_at;

CREATE TRIGGER trg_product_updated_at_insert
AFTER INSERT ON product
WHEN NEW.updated_at IS NULL
BEGIN
    UPDATE product SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = NEW.id;
END;

-- A condição evita que o UPDATE do próprio trigger o dispare de novo.
CREATE TRIGGER trg_product_updated_at
AFTER UPDATE ON product
WHEN NEW.updated_at IS OLD.updated_at
BEGIN
    UPDATE product SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_order_updated_at_insert
AFTER INSERT ON customer_order
WHEN NEW.updated_at IS NULL
BEGIN
    UPDATE customer_order SET updated_at = NEW.created_at WHERE id = NEW.id;
END;

CREATE TRIGGER trg_order_updated_at
AFTER UPDATE ON customer_order
WHEN NEW.updated_at IS OLD.updated_at
BEGIN
    UPDATE customer_order SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = NEW.id;
END;

-- ===========================================================================
-- Auditoria
-- Guarda o antes e o depois em JSON, só das colunas que importam para quem investiga.
-- ===========================================================================

CREATE TABLE audit_log (
    id         INTEGER PRIMARY KEY,
    table_name TEXT NOT NULL,
    row_id     INTEGER NOT NULL,
    action     TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values TEXT CHECK (old_values IS NULL OR json_valid(old_values)),
    new_values TEXT CHECK (new_values IS NULL OR json_valid(new_values)),
    changed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

CREATE INDEX ix_audit_log_row ON audit_log (table_name, row_id);

-- Preço, nome e ativação do produto. O WHEN ignora o UPDATE que só mexe no updated_at.
CREATE TRIGGER trg_audit_product_update
AFTER UPDATE OF price_cents, name, active ON product
WHEN OLD.price_cents IS NOT NEW.price_cents OR OLD.name IS NOT NEW.name OR OLD.active IS NOT NEW.active
BEGIN
    INSERT INTO audit_log (table_name, row_id, action, old_values, new_values)
    VALUES ('product', NEW.id, 'UPDATE',
            json_object('name', OLD.name, 'price_cents', OLD.price_cents, 'active', OLD.active),
            json_object('name', NEW.name, 'price_cents', NEW.price_cents, 'active', NEW.active));
END;

CREATE TRIGGER trg_audit_product_delete
AFTER DELETE ON product
BEGIN
    INSERT INTO audit_log (table_name, row_id, action, old_values)
    VALUES ('product', OLD.id, 'DELETE',
            json_object('sku', OLD.sku, 'name', OLD.name, 'price_cents', OLD.price_cents));
END;

CREATE TRIGGER trg_audit_order_status
AFTER UPDATE OF status ON customer_order
WHEN OLD.status <> NEW.status
BEGIN
    INSERT INTO audit_log (table_name, row_id, action, old_values, new_values)
    VALUES ('customer_order', NEW.id, 'UPDATE',
            json_object('status', OLD.status), json_object('status', NEW.status));
END;

CREATE TRIGGER trg_audit_inventory_minimum
AFTER UPDATE OF minimum_quantity ON inventory
WHEN OLD.minimum_quantity <> NEW.minimum_quantity
BEGIN
    INSERT INTO audit_log (table_name, row_id, action, old_values, new_values)
    VALUES ('inventory', NEW.product_id, 'UPDATE',
            json_object('minimum_quantity', OLD.minimum_quantity),
            json_object('minimum_quantity', NEW.minimum_quantity));
END;

COMMIT;
