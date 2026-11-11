-- Testes de comportamento: executa operações válidas dentro de uma transação, confere o efeito dos triggers
-- e desfaz tudo no fim. Como em integrity.sql, cada linha que aparecer é um teste que falhou.
-- Os caminhos de erro (RAISE) ficam demonstrados em queries/03-views-e-triggers.sql.

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

CREATE TEMP TABLE before (product_id INTEGER PRIMARY KEY, quantity INTEGER);
INSERT INTO before SELECT product_id, quantity FROM inventory WHERE product_id IN (12, 13);

INSERT INTO customer_order (id, customer_id, shipping_street, shipping_number, shipping_city, shipping_state, shipping_zip_code)
VALUES (9101, 1, 'Rua Teste', '1', 'Fortaleza', 'CE', '60000000');
INSERT INTO order_item (order_id, product_id, quantity, unit_price_cents) VALUES (9101, 12, 2, 1000), (9101, 13, 1, 500);
INSERT INTO payment (order_id, method, amount_cents, status) VALUES (9101, 'PIX', 2500, 'APPROVED');

-- Venda: a saída de estoque e a movimentação acontecem junto com o item
SELECT 'venda não baixou o estoque' AS failed_test
WHERE (SELECT quantity FROM inventory WHERE product_id = 12) <> (SELECT quantity FROM before WHERE product_id = 12) - 2
UNION ALL
SELECT 'venda sem movimentação de saída'
WHERE (SELECT count(*) FROM stock_movement WHERE order_id = 9101 AND type = 'OUT') <> 2
UNION ALL
SELECT 'pedido novo sem updated_at'
WHERE (SELECT updated_at FROM customer_order WHERE id = 9101) IS NULL;

UPDATE customer_order SET status = 'PAID' WHERE id = 9101;
UPDATE customer_order SET status = 'CANCELLED' WHERE id = 9101;

-- Cancelamento devolve o estoque, e a auditoria registra as duas mudanças de status
SELECT 'cancelamento não devolveu o estoque' AS failed_test
WHERE EXISTS (SELECT 1 FROM before b JOIN inventory i ON i.product_id = b.product_id WHERE i.quantity <> b.quantity)
UNION ALL
SELECT 'auditoria não registrou as mudanças de status'
WHERE (SELECT count(*) FROM audit_log WHERE table_name = 'customer_order' AND row_id = 9101) <> 2;

UPDATE product SET price_cents = price_cents + 100 WHERE id = 12;
INSERT INTO product (id, sku, name, price_cents, category_id) VALUES (9999, 'GAR-999', 'Garrafa térmica', 5990, 120);

-- Mudança de preço vai para a auditoria; produto novo entra na busca e nasce com atributos vazios
SELECT 'mudança de preço sem auditoria' AS failed_test
WHERE NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'product' AND row_id = 12)
UNION ALL
SELECT 'produto novo fora da busca'
WHERE NOT EXISTS (SELECT 1 FROM product_search WHERE product_search MATCH 'garrafa termica')
UNION ALL
SELECT 'produto novo sem atributos JSON'
WHERE (SELECT attributes FROM product WHERE id = 9999) <> '{}';

ROLLBACK;
