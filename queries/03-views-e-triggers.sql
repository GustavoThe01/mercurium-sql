-- Demonstração das views e dos triggers da V002.
-- Rode depois de V001, S001 e V002. Tudo acontece dentro de uma transação desfeita no fim,
-- então o banco volta exatamente ao estado de antes.
--
-- Algumas linhas falham de propósito, para mostrar uma regra sendo aplicada. O sqlite3 mostra o erro
-- e segue para a próxima linha. Não use a opção -bail aqui.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- Os 5 clientes que mais geraram receita
SELECT name, orders, lifetime_value_cents / 100.0 AS lifetime_value, average_ticket_cents / 100.0 AS average_ticket
FROM vw_customer_lifetime_value
ORDER BY lifetime_value_cents DESC
LIMIT 5;

-- O que precisa de reposição
SELECT sku, name, quantity, minimum_quantity, missing
FROM vw_low_stock
ORDER BY missing DESC, sku;

-- Pedidos pagos cujo total não bate com os pagamentos aprovados (o esperado é nenhum)
SELECT order_id, total_cents, paid_cents
FROM vw_order_summary
WHERE status IN ('PAID', 'SHIPPED', 'DELIVERED') AND total_cents <> paid_cents;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- Uma venda do começo ao fim
-- ---------------------------------------------------------------------------

INSERT INTO customer_order (id, customer_id, shipping_street, shipping_number, shipping_city, shipping_state, shipping_zip_code)
VALUES (9001, 1, 'Av. Beira Mar', '100', 'Fortaleza', 'CE', '60165121');

SELECT 'estoque antes' AS momento, quantity FROM inventory WHERE product_id = 12;

-- O trigger grava a saída em stock_movement, e o saldo cai junto.
INSERT INTO order_item (order_id, product_id, quantity, unit_price_cents) VALUES (9001, 12, 2, 23990);

SELECT 'estoque depois' AS momento, quantity FROM inventory WHERE product_id = 12;

-- Esperado: erro "Estoque insuficiente para esta saída". O item não entra.
INSERT INTO order_item (order_id, product_id, quantity, unit_price_cents) VALUES (9001, 13, 99999, 1000);

-- Esperado: erro "Transição de status inválida" (PENDING não pula para SHIPPED).
UPDATE customer_order SET status = 'SHIPPED' WHERE id = 9001;

-- Esperado: erro "Os pagamentos aprovados não fecham o total do pedido".
UPDATE customer_order SET status = 'PAID' WHERE id = 9001;

INSERT INTO payment (order_id, method, amount_cents, status) VALUES (9001, 'PIX', 47980, 'APPROVED');
UPDATE customer_order SET status = 'PAID' WHERE id = 9001;

-- Cancelar devolve o estoque, com uma entrada nova no histórico.
UPDATE customer_order SET status = 'CANCELLED' WHERE id = 9001;

SELECT type, quantity, reason FROM stock_movement WHERE order_id = 9001 ORDER BY id;
SELECT 'estoque após cancelar' AS momento, quantity FROM inventory WHERE product_id = 12;

-- Esperado: erro "Movimentação de estoque não pode ser alterada; registre um ajuste".
UPDATE stock_movement SET quantity = 1 WHERE order_id = 9001;

-- ---------------------------------------------------------------------------
-- Auditoria e updated_at
-- ---------------------------------------------------------------------------

UPDATE product SET price_cents = 24990 WHERE id = 12;

SELECT table_name, row_id, old_values, new_values
FROM audit_log
ORDER BY id;

SELECT id, price_cents, updated_at FROM product WHERE id = 12;

-- ---------------------------------------------------------------------------
-- Avaliação
-- ---------------------------------------------------------------------------

-- Esperado: erro "Só quem recebeu o produto pode avaliá-lo" (o cliente 56 nunca comprou).
INSERT INTO review (customer_id, product_id, rating, comment) VALUES (56, 12, 5, 'Ótimo');

ROLLBACK;
