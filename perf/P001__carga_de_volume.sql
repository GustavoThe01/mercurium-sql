-- P001: carga de volume para medir performance. NÃO faz parte do banco normal.
-- Use num arquivo separado (mercurium-perf.db), nesta ordem:
--   V001 → S001 → P001 → V002 → medir → V003 (índices) → medir de novo
--
-- Roda antes da V002 de propósito: os pedidos são históricos e já nascem pagos ou entregues,
-- e o trigger que só aceita item em pedido PENDING os recusaria.
--
-- Acrescenta ~5.000 clientes, 200.000 pedidos em 2 anos, ~500.000 itens, pagamentos e movimentações.
-- Como o seed, tudo vem de aritmética com módulo: o resultado é sempre o mesmo.

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

WITH RECURSIVE sequence (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM sequence WHERE n < 4940)
INSERT INTO customer (id, name, email, document, created_at)
SELECT 1000 + n,
       'Cliente de carga ' || n,
       'carga' || n || '@exemplo.test',
       printf('%011d', 80000000000 + n),
       strftime('%Y-%m-%dT%H:%M:%SZ', '2024-01-01', '+' || (n % 600) || ' days')
FROM sequence;

INSERT INTO address (customer_id, street, number, city, state, zip_code, is_primary)
SELECT id, 'Rua da Carga', CAST(id AS TEXT), 'Fortaleza', 'CE', '60000000', 1
FROM customer
WHERE id > 1000;

-- 200.000 pedidos entre nov/2024 e nov/2026. 1 em cada 20 está em andamento, 1 em cada 17 foi cancelado.
WITH RECURSIVE sequence (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM sequence WHERE n < 200000)
INSERT INTO customer_order (id, customer_id, status, shipping_street, shipping_number, shipping_city,
                            shipping_state, shipping_zip_code, created_at)
SELECT 100000 + n,
       1001 + (n * 7919) % 4940,
       CASE WHEN n % 17 = 0 THEN 'CANCELLED'
            WHEN n % 20 = 0 THEN 'PENDING'
            WHEN n % 20 = 1 THEN 'PAID'
            WHEN n % 20 = 2 THEN 'SHIPPED'
            ELSE 'DELIVERED' END,
       'Rua da Carga', '1', 'Fortaleza', 'CE', '60000000',
       strftime('%Y-%m-%dT%H:%M:%SZ', '2024-11-01', '+' || (n * 730 / 200000) || ' days',
                '+' || (n % 1440) || ' minutes')
FROM sequence;

WITH position (value) AS (VALUES (1), (2), (3), (4))
INSERT INTO order_item (order_id, product_id, quantity, unit_price_cents)
SELECT o.id, p.id, 1 + (o.id + position.value) % 3, p.price_cents
FROM customer_order o
JOIN position ON position.value <= 1 + o.id % 4
JOIN product p ON p.id = 1 + (o.id * 31 + position.value * 17) % 100
WHERE o.id > 100000;

WITH order_total AS (
    SELECT order_id, SUM(quantity * unit_price_cents) AS total_cents
    FROM order_item
    WHERE order_id > 100000
    GROUP BY order_id
)
INSERT INTO payment (order_id, method, amount_cents, status, created_at)
SELECT o.id, CASE o.id % 3 WHEN 0 THEN 'PIX' WHEN 1 THEN 'CARD' ELSE 'BOLETO' END,
       t.total_cents,
       CASE WHEN o.status IN ('PAID', 'SHIPPED', 'DELIVERED') THEN 'APPROVED'
            WHEN o.status = 'PENDING' THEN 'PENDING' ELSE 'REFUSED' END,
       strftime('%Y-%m-%dT%H:%M:%SZ', o.created_at, '+20 minutes')
FROM customer_order o
JOIN order_total t ON t.order_id = o.id;

INSERT INTO stock_movement (product_id, order_id, type, quantity, reason, created_at)
SELECT i.product_id, i.order_id, 'OUT', i.quantity, 'Venda', o.created_at
FROM order_item i
JOIN customer_order o ON o.id = i.order_id
WHERE o.id > 100000 AND o.status <> 'CANCELLED';

-- Entrada que cobre exatamente as saídas da carga: o saldo em inventory continua o mesmo.
INSERT INTO stock_movement (product_id, type, quantity, reason, created_at)
SELECT product_id, 'IN', SUM(quantity), 'Reposição da carga de volume', '2024-10-31T09:00:00Z'
FROM stock_movement
WHERE order_id > 100000
GROUP BY product_id;

COMMIT;

ANALYZE;
