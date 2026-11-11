-- Testes de integridade: cada consulta procura dados que quebram uma regra.
-- Banco saudável = nenhuma linha. Cada linha que aparecer traz o nome do teste e quantos registros falharam.
-- Rode com scripts/test.sh (ou test.ps1), depois do build.

-- Regra 2: estoque nunca negativo
SELECT 'estoque negativo' AS failed_test, count(*) AS rows
FROM inventory WHERE quantity < 0
HAVING count(*) > 0

UNION ALL
-- Regra 7: o saldo é exatamente a soma das movimentações
SELECT 'saldo diferente das movimentações', count(*)
FROM inventory inv
WHERE inv.quantity <> (
    SELECT COALESCE(SUM(CASE type WHEN 'OUT' THEN -quantity ELSE quantity END), 0)
    FROM stock_movement m WHERE m.product_id = inv.product_id)
HAVING count(*) > 0

UNION ALL
-- Todo produto tem linha de estoque
SELECT 'produto sem estoque', count(*)
FROM product p WHERE NOT EXISTS (SELECT 1 FROM inventory i WHERE i.product_id = p.id)
HAVING count(*) > 0

UNION ALL
-- Regra 5: pedido pago, enviado ou entregue tem pagamentos aprovados que fecham o total
SELECT 'pedido pago sem pagamento que feche o total', count(*)
FROM vw_order_summary
WHERE status IN ('PAID', 'SHIPPED', 'DELIVERED') AND paid_cents <> total_cents
HAVING count(*) > 0

UNION ALL
-- Pedido cancelado não tem pagamento aprovado
SELECT 'pedido cancelado com pagamento aprovado', count(*)
FROM customer_order o
WHERE o.status = 'CANCELLED'
  AND EXISTS (SELECT 1 FROM payment p WHERE p.order_id = o.id AND p.status = 'APPROVED')
HAVING count(*) > 0

UNION ALL
-- Todo pedido tem pelo menos um item
SELECT 'pedido sem itens', count(*)
FROM customer_order o WHERE NOT EXISTS (SELECT 1 FROM order_item i WHERE i.order_id = o.id)
HAVING count(*) > 0

UNION ALL
-- Regra 6: só avalia quem recebeu o produto
SELECT 'avaliação sem entrega', count(*)
FROM review r
WHERE NOT EXISTS (
    SELECT 1 FROM customer_order o JOIN order_item i ON i.order_id = o.id
    WHERE o.customer_id = r.customer_id AND i.product_id = r.product_id AND o.status = 'DELIVERED')
HAVING count(*) > 0

UNION ALL
-- Cada cliente tem exatamente um endereço principal
SELECT 'cliente sem endereço principal', count(*)
FROM customer c
WHERE (SELECT count(*) FROM address a WHERE a.customer_id = c.id AND a.is_primary = 1) <> 1
HAVING count(*) > 0

UNION ALL
-- Categoria não pode ser ancestral dela mesma (ciclo na árvore)
SELECT 'ciclo na árvore de categorias', count(*)
FROM category c
WHERE EXISTS (
    WITH RECURSIVE ancestor (id) AS (
        SELECT parent_id FROM category WHERE id = c.id
        UNION
        SELECT parent_id FROM category JOIN ancestor ON category.id = ancestor.id WHERE parent_id IS NOT NULL
    )
    SELECT 1 FROM ancestor WHERE id = c.id)
HAVING count(*) > 0

UNION ALL
-- A busca FTS5 tem exatamente um registro por produto
SELECT 'busca fora de sincronia com os produtos', count(*)
FROM (
    SELECT id FROM product EXCEPT SELECT rowid FROM product_search
    UNION ALL
    SELECT rowid FROM product_search EXCEPT SELECT id FROM product)
HAVING count(*) > 0

UNION ALL
-- Atributos e auditoria em JSON válido
SELECT 'JSON inválido', count(*)
FROM (
    SELECT attributes AS doc FROM product
    UNION ALL SELECT old_values FROM audit_log WHERE old_values IS NOT NULL
    UNION ALL SELECT new_values FROM audit_log WHERE new_values IS NOT NULL)
WHERE NOT json_valid(doc)
HAVING count(*) > 0

UNION ALL
-- Datas em ISO 8601 UTC (comparáveis como texto)
SELECT 'data fora do formato ISO 8601', count(*)
FROM (SELECT created_at AS value FROM customer_order UNION ALL SELECT created_at FROM payment
      UNION ALL SELECT created_at FROM stock_movement UNION ALL SELECT created_at FROM customer)
WHERE value NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
HAVING count(*) > 0;
