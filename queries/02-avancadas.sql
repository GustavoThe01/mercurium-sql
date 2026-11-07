-- Consultas avançadas: CTEs (inclusive recursivas) e window functions.
-- Rode depois de carregar o schema e os dados de exemplo.
--
-- Diferença central: GROUP BY junta várias linhas em uma só; uma window function calcula sobre um
-- grupo de linhas (a janela) e mantém todas elas no resultado.
--   PARTITION BY -> em quais grupos a janela é dividida
--   ORDER BY     -> em que ordem as linhas da janela são percorridas
--   ROWS/RANGE   -> o "framing": quais linhas, ao redor da atual, entram no cálculo
--
-- Regra usada em todo o arquivo: só conta como faturamento o pedido pago, enviado ou entregue.

-- 1. Como é a árvore de categorias, com o caminho completo e o nível de cada uma?
--    Conceito: CTE recursiva. A parte âncora pega as raízes; a parte recursiva desce um nível por vez.
WITH RECURSIVE tree (id, name, depth, path) AS (
    SELECT id, name, 0, name
    FROM category
    WHERE parent_id IS NULL
    UNION ALL
    SELECT child.id, child.name, tree.depth + 1, tree.path || ' > ' || child.name
    FROM category AS child
    JOIN tree ON child.parent_id = tree.id
)
SELECT depth, path
FROM tree
ORDER BY path;

-- 2. Qual é o faturamento de cada categoria raiz, somando todas as subcategorias abaixo dela?
--    Conceito: CTE recursiva que leva a raiz junto enquanto desce a árvore.
WITH RECURSIVE
    descendant (root_id, category_id) AS (
        SELECT id, id FROM category WHERE parent_id IS NULL
        UNION ALL
        SELECT descendant.root_id, child.id
        FROM category AS child
        JOIN descendant ON child.parent_id = descendant.category_id
    ),
    sold AS (
        SELECT p.category_id, i.quantity * i.unit_price_cents AS cents
        FROM order_item AS i
        JOIN customer_order AS o ON o.id = i.order_id
        JOIN product AS p ON p.id = i.product_id
        WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    )
SELECT root.name AS root_category, SUM(sold.cents) / 100.0 AS revenue
FROM descendant
JOIN category AS root ON root.id = descendant.root_id
JOIN sold ON sold.category_id = descendant.category_id
GROUP BY root.id, root.name
ORDER BY revenue DESC;

-- 3. Qual foi o último pedido de cada cliente?
--    Conceito: ROW_NUMBER() numera as linhas dentro de cada cliente; a mais recente recebe 1.
WITH ranked AS (
    SELECT o.customer_id, o.id AS order_id, o.created_at,
           ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.created_at DESC, o.id DESC) AS position
    FROM customer_order AS o
)
SELECT c.name, ranked.order_id, ranked.created_at
FROM ranked
JOIN customer AS c ON c.id = ranked.customer_id
WHERE ranked.position = 1
ORDER BY ranked.created_at DESC
LIMIT 10;

-- 4. Quais são os 3 produtos mais vendidos de cada categoria?
--    Conceito: top-N por grupo. RANK repete a posição em caso de empate e pula a seguinte (1, 1, 3);
--    DENSE_RANK não pula (1, 1, 2).
WITH sales AS (
    SELECT p.category_id, p.name, SUM(i.quantity) AS units
    FROM order_item AS i
    JOIN customer_order AS o ON o.id = i.order_id
    JOIN product AS p ON p.id = i.product_id
    WHERE o.status <> 'CANCELLED'
    GROUP BY p.id, p.category_id, p.name
),
ranked AS (
    SELECT category_id, name, units,
           RANK() OVER (PARTITION BY category_id ORDER BY units DESC) AS rank_position,
           DENSE_RANK() OVER (PARTITION BY category_id ORDER BY units DESC) AS dense_position
    FROM sales
)
SELECT c.name AS category, ranked.name AS product, ranked.units, ranked.rank_position, ranked.dense_position
FROM ranked
JOIN category AS c ON c.id = ranked.category_id
WHERE ranked.rank_position <= 3
ORDER BY c.name, ranked.rank_position, ranked.name;

-- 5. Quanto o faturamento cresceu ou caiu em relação ao mês anterior?
--    Conceito: LAG() lê a linha anterior da janela, sem autojunção.
WITH monthly AS (
    SELECT strftime('%Y-%m', o.created_at) AS month, SUM(i.quantity * i.unit_price_cents) AS cents
    FROM customer_order AS o
    JOIN order_item AS i ON i.order_id = o.id
    WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    GROUP BY month
)
SELECT month,
       cents / 100.0 AS revenue,
       LAG(cents) OVER (ORDER BY month) / 100.0 AS previous_month,
       ROUND((cents - LAG(cents) OVER (ORDER BY month)) * 100.0 / LAG(cents) OVER (ORDER BY month), 1) AS growth_percentage
FROM monthly
ORDER BY month;

-- 6. Qual é o faturamento acumulado do ano, mês a mês, e a média móvel de 3 meses?
--    Conceito: framing. O total acumulado vai do início até a linha atual; a média móvel olha só
--    a linha atual e as 2 anteriores. ROWS conta linhas; RANGE agruparia linhas com o mesmo valor de ORDER BY.
WITH monthly AS (
    SELECT strftime('%Y-%m', o.created_at) AS month, SUM(i.quantity * i.unit_price_cents) AS cents
    FROM customer_order AS o
    JOIN order_item AS i ON i.order_id = o.id
    WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    GROUP BY month
)
SELECT month,
       cents / 100.0 AS revenue,
       SUM(cents) OVER (ORDER BY month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / 100.0 AS running_total,
       ROUND(AVG(cents) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / 100.0, 2) AS moving_average_3m
FROM monthly
ORDER BY month;

-- 7. Quanto tempo cada cliente leva entre uma compra e a próxima?
--    Conceito: LEAD() lê a linha seguinte da janela do mesmo cliente.
WITH timeline AS (
    SELECT customer_id, created_at,
           LEAD(created_at) OVER (PARTITION BY customer_id ORDER BY created_at) AS next_order_at
    FROM customer_order
    WHERE status <> 'CANCELLED'
)
SELECT c.name,
       COUNT(*) AS intervals,
       ROUND(AVG(julianday(timeline.next_order_at) - julianday(timeline.created_at)), 1) AS average_days
FROM timeline
JOIN customer AS c ON c.id = timeline.customer_id
WHERE timeline.next_order_at IS NOT NULL
GROUP BY c.id, c.name
HAVING COUNT(*) >= 3
ORDER BY average_days
LIMIT 10;

-- 8. Quanto cada cliente representa do faturamento total, e em que quartil ele está?
--    Conceito: SUM() OVER () sem partição usa todas as linhas; NTILE(4) divide os clientes em 4 faixas.
WITH spent AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price_cents) AS cents
    FROM customer_order AS o
    JOIN order_item AS i ON i.order_id = o.id
    WHERE o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
    GROUP BY o.customer_id
)
SELECT c.name,
       spent.cents / 100.0 AS total_spent,
       ROUND(spent.cents * 100.0 / SUM(spent.cents) OVER (), 2) AS share_percentage,
       NTILE(4) OVER (ORDER BY spent.cents DESC) AS quartile
FROM spent
JOIN customer AS c ON c.id = spent.customer_id
ORDER BY spent.cents DESC
LIMIT 10;

-- 9. Quais clientes estão há mais de 90 dias sem comprar, considerando a data do pedido mais recente da loja?
--    Conceito: CTEs encadeadas, cada uma resolvendo um passo e dando nome a ele.
WITH
    store_today AS (
        SELECT MAX(created_at) AS reference FROM customer_order
    ),
    last_purchase AS (
        SELECT customer_id, MAX(created_at) AS last_order_at
        FROM customer_order
        WHERE status <> 'CANCELLED'
        GROUP BY customer_id
    )
SELECT c.name,
       last_purchase.last_order_at,
       CAST(julianday(store_today.reference) - julianday(last_purchase.last_order_at) AS INTEGER) AS days_without_buying
FROM last_purchase
JOIN customer AS c ON c.id = last_purchase.customer_id
CROSS JOIN store_today
WHERE julianday(store_today.reference) - julianday(last_purchase.last_order_at) > 90
ORDER BY days_without_buying DESC;

-- 10. Qual é o extrato de estoque de um produto, com o saldo depois de cada movimentação?
--     Conceito: soma acumulada sobre valores com sinal. O último saldo precisa bater com a tabela inventory.
SELECT m.created_at,
       m.type,
       m.quantity,
       SUM(CASE m.type WHEN 'OUT' THEN -m.quantity ELSE m.quantity END)
           OVER (ORDER BY m.created_at, m.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance_after
FROM stock_movement AS m
WHERE m.product_id = 12
ORDER BY m.created_at, m.id;
