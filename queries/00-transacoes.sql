-- Demonstração de transação e ROLLBACK. Rode depois de carregar o schema e os dados de exemplo.
-- Nada aqui altera o banco no final: é justamente esse o ponto.

-- 1) ROLLBACK proposital: a baixa de estoque é feita e depois desfeita.
SELECT 'antes' AS momento, quantity FROM inventory WHERE product_id = 1;

BEGIN TRANSACTION;
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 1;
SELECT 'dentro da transação' AS momento, quantity FROM inventory WHERE product_id = 1;
ROLLBACK;

SELECT 'depois do ROLLBACK' AS momento, quantity FROM inventory WHERE product_id = 1;

-- 2) Atomicidade: as duas primeiras baixas são válidas, mas a terceira deixaria o estoque negativo.
--    O CHECK recusa a linha, e OR ROLLBACK desfaz a transação inteira, inclusive o que já tinha dado certo.
BEGIN TRANSACTION;
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 1;
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 2;
UPDATE OR ROLLBACK inventory SET quantity = -1 WHERE product_id = 3;

SELECT 'nada mudou' AS momento, product_id, quantity FROM inventory WHERE product_id IN (1, 2, 3);
