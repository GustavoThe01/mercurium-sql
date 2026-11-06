-- Consultas fundamentais: 15 perguntas de negócio respondidas com SQL.
-- Rode depois de carregar o schema e os dados de exemplo.
--
-- Ordem lógica de execução de um SELECT, que explica boa parte dos erros comuns:
--   FROM/JOIN -> WHERE -> GROUP BY -> HAVING -> SELECT -> DISTINCT -> ORDER BY -> LIMIT
-- Por isso o WHERE não enxerga um SUM() (ele roda antes do agrupamento) e o HAVING enxerga.
--
-- Regra usada em todo o arquivo: só conta como faturamento o pedido pago, enviado ou entregue.

-- 1. Quais pedidos foram entregues, com o nome do cliente? Os 5 mais recentes.
--    Conceito: INNER JOIN, filtro e ordenação.
SELECT o.id, c.name AS customer, o.created_at
FROM customer_order AS o
JOIN customer AS c ON c.id = o.customer_id
WHERE o.status = 'DELIVERED'
ORDER BY o.created_at DESC
LIMIT 5;

-- 2. Quantos pedidos cada cliente fez, incluindo quem nunca comprou?
--    Conceito: LEFT JOIN. COUNT(o.id) ignora NULL; COUNT(*) contaria 1 para quem não tem pedido.
SELECT c.id, c.name, COUNT(o.id) AS orders
FROM customer AS c
LEFT JOIN customer_order AS o ON o.customer_id = c.id
GROUP BY c.id, c.name
ORDER BY orders DESC, c.name;

-- 3. Quais clientes nunca fizeram um pedido?
--    Conceito: anti-join com LEFT JOIN + IS NULL.
SELECT c.id, c.name, c.email
FROM customer AS c
LEFT JOIN customer_order AS o ON o.customer_id = c.id
WHERE o.id IS NULL
ORDER BY c.id;

-- 4. Qual é o faturamento, em reais, de cada mês?
--    Conceito: agregação sobre uma data transformada. Dividir por 100.0 evita a divisão inteira.
SELECT strftime('%Y-%m', o.created_at) AS month,
       SUM(i.quantity * i.unit_price_cents) / 100.0 AS revenue
FROM customer_order AS o
JOIN order_item AS i ON i.order_id = o.id
WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY month
ORDER BY month;

-- 5. Quantos pedidos existem em cada status, e qual a participação de cada um?
--    Conceito: subconsulta escalar no SELECT.
SELECT status,
       COUNT(*) AS orders,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_order), 1) AS percentage
FROM customer_order
GROUP BY status
ORDER BY orders DESC;

-- 6. Quais clientes gastaram mais de R$ 5.000 no total?
--    Conceito: HAVING filtra depois do agrupamento.
SELECT c.name, SUM(i.quantity * i.unit_price_cents) / 100.0 AS total_spent
FROM customer AS c
JOIN customer_order AS o ON o.customer_id = c.id
JOIN order_item AS i ON i.order_id = o.id
WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY c.id, c.name
HAVING SUM(i.quantity * i.unit_price_cents) > 500000
ORDER BY total_spent DESC;

-- 7. Qual é o ticket médio dos pedidos faturados?
--    Conceito: subconsulta no FROM. É preciso somar por pedido antes de tirar a média.
SELECT ROUND(AVG(order_total) / 100.0, 2) AS average_ticket
FROM (
    SELECT SUM(i.quantity * i.unit_price_cents) AS order_total
    FROM customer_order AS o
    JOIN order_item AS i ON i.order_id = o.id
    WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    GROUP BY o.id
);

-- 8. Quais são os 10 produtos mais vendidos em unidades?
--    Conceito: agregação com JOIN e LIMIT.
SELECT p.sku, p.name, SUM(i.quantity) AS units_sold
FROM order_item AS i
JOIN customer_order AS o ON o.id = i.order_id
JOIN product AS p ON p.id = i.product_id
WHERE o.status <> 'CANCELLED'
GROUP BY p.id, p.sku, p.name
ORDER BY units_sold DESC, p.sku
LIMIT 10;

-- 9. Quais produtos estão abaixo do estoque mínimo, começando pelos mais críticos?
--    Conceito: comparação entre colunas e expressão na ordenação.
SELECT p.sku, p.name, inv.quantity, inv.minimum_quantity,
       inv.minimum_quantity - inv.quantity AS shortage
FROM inventory AS inv
JOIN product AS p ON p.id = inv.product_id
WHERE inv.quantity < inv.minimum_quantity
ORDER BY shortage DESC, p.sku;

-- 10. Como classificar os clientes por valor gasto?
--     Conceito: CASE para criar faixas.
SELECT tier, COUNT(*) AS customers
FROM (
    SELECT c.id,
           CASE
               WHEN COALESCE(SUM(i.quantity * i.unit_price_cents), 0) = 0 THEN '0. Sem compras'
               WHEN SUM(i.quantity * i.unit_price_cents) < 300000 THEN '1. Até R$ 3 mil'
               WHEN SUM(i.quantity * i.unit_price_cents) < 800000 THEN '2. Até R$ 8 mil'
               ELSE '3. Acima de R$ 8 mil'
           END AS tier
    FROM customer AS c
    LEFT JOIN customer_order AS o
           ON o.customer_id = c.id AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    LEFT JOIN order_item AS i ON i.order_id = o.id
    GROUP BY c.id
)
GROUP BY tier
ORDER BY tier;

-- 11. Qual é a nota média de cada produto com pelo menos 5 avaliações?
--     Conceito: dois agregados, um para exibir e outro para filtrar.
SELECT p.name, COUNT(*) AS reviews, ROUND(AVG(r.rating), 2) AS average_rating
FROM review AS r
JOIN product AS p ON p.id = r.product_id
GROUP BY p.id, p.name
HAVING COUNT(*) >= 5
ORDER BY average_rating DESC, reviews DESC, p.name;

-- 12. Quais produtos custam mais do que a média da própria categoria?
--     Conceito: subconsulta correlacionada, recalculada para cada linha externa.
SELECT p.sku, p.name, p.price_cents / 100.0 AS price
FROM product AS p
WHERE p.price_cents > (
    SELECT AVG(other.price_cents)
    FROM product AS other
    WHERE other.category_id = p.category_id
)
ORDER BY p.category_id, p.price_cents DESC;

-- 13. Quais produtos já foram entregues a alguém e ainda não têm nenhuma avaliação?
--     Conceito: EXISTS e NOT EXISTS. Param na primeira linha encontrada, sem precisar contar.
SELECT p.sku, p.name
FROM product AS p
WHERE EXISTS (
        SELECT 1
        FROM order_item AS i
        JOIN customer_order AS o ON o.id = i.order_id
        WHERE i.product_id = p.id AND o.status = 'DELIVERED'
    )
  AND NOT EXISTS (
        SELECT 1 FROM review AS r WHERE r.product_id = p.id
    )
ORDER BY p.sku;

-- 14. Quais pedidos tiveram um pagamento recusado antes de serem aprovados?
--     Conceito: agregação condicional. Em vez de duas consultas, um SUM com CASE.
SELECT p.order_id,
       SUM(CASE WHEN p.status = 'REFUSED' THEN 1 ELSE 0 END) AS refused_attempts,
       SUM(CASE WHEN p.status = 'APPROVED' THEN p.amount_cents ELSE 0 END) / 100.0 AS approved_amount
FROM payment AS p
GROUP BY p.order_id
HAVING refused_attempts > 0 AND approved_amount > 0
ORDER BY p.order_id
LIMIT 10;

-- 15. Quais vendas saíram por um preço diferente do preço atual do produto?
--     Conceito: o histórico de preços. É a prova de que copiar o preço para o item foi a decisão certa.
SELECT p.sku, i.order_id, i.unit_price_cents / 100.0 AS price_paid, p.price_cents / 100.0 AS current_price
FROM order_item AS i
JOIN product AS p ON p.id = i.product_id
WHERE i.unit_price_cents <> p.price_cents
ORDER BY i.order_id, p.sku
LIMIT 10;
