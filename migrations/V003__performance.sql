-- V003: índices e um ajuste de view, escolhidos a partir das medições de docs/performance.md.
-- Cada índice existe por causa de uma consulta medida. Índice também custa: ocupa espaço
-- e deixa cada INSERT/UPDATE mais lento, então nenhum entrou "por garantia".

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- Q1: histórico do cliente. Igualdade primeiro (customer_id), ordenação depois (created_at):
-- o SQLite encontra o cliente e já percorre os pedidos na ordem certa, sem ordenar nada.
-- Também serve à chave estrangeira customer_order.customer_id.
CREATE INDEX ix_customer_order_customer_created ON customer_order (customer_id, created_at);

-- Q6: fila de pendentes. Mesma lógica: status (igualdade) antes de created_at (ordem).
-- Com as colunas invertidas, o índice não ajudaria a filtrar o status.
CREATE INDEX ix_customer_order_status_created ON customer_order (status, created_at);

-- Q3: compras de um produto. Índice de cobertura: quantity e unit_price_cents já estão no índice,
-- e o order_id vem junto porque é parte da chave primária. A tabela não precisa ser lida.
CREATE INDEX ix_order_item_product ON order_item (product_id, quantity, unit_price_cents);

-- Q4: a view soma os pagamentos aprovados de cada pedido. Sem índice, cada pedido varre a tabela inteira.
CREATE INDEX ix_payment_order ON payment (order_id, status, amount_cents);

-- Q5: extrato de estoque, já na ordem do extrato.
CREATE INDEX ix_stock_movement_product_created ON stock_movement (product_id, created_at);

-- Chave estrangeira sem índice: a CTE recursiva de faturamento por categoria junta produto por categoria.
CREATE INDEX ix_product_category ON product (category_id);

-- Q7: o lifetime value passava por vw_order_summary, que calcula o valor pago de cada pedido
-- com uma subconsulta, coluna que o LTV nem usa. A view nova soma direto os itens dos pedidos
-- que contam como receita. Mesmo resultado, com as mesmas colunas, em cerca de 60% do tempo.
DROP VIEW vw_customer_lifetime_value;

CREATE VIEW vw_customer_lifetime_value AS
WITH revenue AS (
    SELECT o.customer_id, o.id AS order_id, o.created_at, SUM(i.quantity * i.unit_price_cents) AS total_cents
    FROM customer_order o
    JOIN order_item i ON i.order_id = o.id
    WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    GROUP BY o.id
)
SELECT c.id                                   AS customer_id,
       c.name,
       COUNT(r.order_id)                      AS orders,
       COALESCE(SUM(r.total_cents), 0)        AS lifetime_value_cents,
       CASE WHEN COUNT(r.order_id) = 0 THEN 0
            ELSE SUM(r.total_cents) / COUNT(r.order_id) END AS average_ticket_cents,
       MIN(r.created_at)                      AS first_order_at,
       MAX(r.created_at)                      AS last_order_at
FROM customer c
LEFT JOIN revenue r ON r.customer_id = c.id
GROUP BY c.id;

COMMIT;

-- Atualiza as estatísticas que o planejador usa para escolher entre os índices.
ANALYZE;
