-- Consultas usadas na análise de performance (docs/performance.md).
-- Rode no banco de carga (mercurium-perf.db), antes e depois da V003:
--   sqlite3 mercurium-perf.db < perf/consultas-medidas.sql
-- .eqp on mostra o plano de cada consulta; .timer on mostra o tempo.

.eqp on
.timer on

-- Q1. Os 10 últimos pedidos de um cliente (tela "Meus pedidos")
SELECT id, status, created_at
FROM customer_order
WHERE customer_id = 1234
ORDER BY created_at DESC
LIMIT 10;

-- Q2. Faturamento mensal de 2026 (só pedidos que contam como receita)
SELECT strftime('%Y-%m', o.created_at) AS month, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
FROM customer_order o
JOIN order_item i ON i.order_id = o.id
WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
  AND o.created_at >= '2026-01-01'
GROUP BY month
ORDER BY month;

-- Q3. As 20 compras mais recentes de um produto
SELECT o.id, o.customer_id, i.quantity, o.created_at
FROM order_item i
JOIN customer_order o ON o.id = i.order_id
WHERE i.product_id = 42
ORDER BY o.created_at DESC
LIMIT 20;

-- Q4. Resumo de um pedido pela view (total e quanto já foi pago)
SELECT order_id, status, item_lines, total_cents, paid_cents
FROM vw_order_summary
WHERE order_id = 150000;

-- Q5. Extrato de estoque de um produto
SELECT type, quantity, created_at
FROM stock_movement
WHERE product_id = 42
ORDER BY created_at, id;

-- Q6. Fila de pedidos pendentes, do mais antigo para o mais novo
SELECT id, customer_id, created_at
FROM customer_order
WHERE status = 'PENDING'
ORDER BY created_at
LIMIT 50;

-- Q7. Os 10 clientes com maior lifetime value (agrega a base inteira)
SELECT customer_id, name, lifetime_value_cents
FROM vw_customer_lifetime_value
ORDER BY lifetime_value_cents DESC
LIMIT 10;
