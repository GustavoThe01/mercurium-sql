-- S001: dados de exemplo do Mercurium. Todos os nomes, documentos e endereços são inventados.
-- Rode depois de V001__create_schema.sql, em um banco vazio.
--
-- Os volumes vêm de CTEs recursivas, e a variação vem de aritmética com módulo, sem RANDOM():
-- quem rodar o script terá exatamente os mesmos dados, e os resultados das consultas ficam reproduzíveis.
--
-- Tudo está em uma única transação: se qualquer linha violar uma regra, o banco continua vazio.

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- Categorias: 3 níveis, para a CTE recursiva do Dia 06
-- ---------------------------------------------------------------------------
INSERT INTO category (id, name, parent_id) VALUES
    (1,  'Eletrônicos', NULL),
    (2,  'Casa',        NULL),
    (3,  'Vestuário',   NULL),
    (10, 'Áudio',       1),
    (11, 'Informática', 1),
    (12, 'Cozinha',     2),
    (13, 'Decoração',   2),
    (14, 'Camisetas',   3),
    (15, 'Calçados',    3),
    (100, 'Fones de ouvido',  10),
    (101, 'Caixas de som',    10),
    (110, 'Teclados',         11),
    (111, 'Mochilas para notebook', 11),
    (120, 'Canecas',          12),
    (121, 'Panelas',          12),
    (130, 'Luminárias',       13),
    (131, 'Quadros',          13),
    (140, 'Camisetas básicas', 14),
    (150, 'Tênis',            15);

-- ---------------------------------------------------------------------------
-- Produtos: 10 categorias finais x 10 modelos = 100 produtos, com ids de 1 a 100
-- ---------------------------------------------------------------------------
WITH
    leaf (position, category_id, code, label, base_cents, step_cents) AS (
        VALUES
            (0, 100, 'FON', 'Fone',          8900, 3500),
            (1, 101, 'CXS', 'Caixa de som',  14900, 4500),
            (2, 110, 'TEC', 'Teclado',       11900, 2500),
            (3, 111, 'MOC', 'Mochila',       12900, 2000),
            (4, 120, 'CAN', 'Caneca',        2900, 500),
            (5, 121, 'PAN', 'Panela',        7900, 2500),
            (6, 130, 'LUM', 'Luminária',     6900, 1500),
            (7, 131, 'QUA', 'Quadro',        4900, 1000),
            (8, 140, 'CAM', 'Camiseta',      3900, 800),
            (9, 150, 'TEN', 'Tênis',         15900, 3000)
    ),
    model (number, label) AS (
        VALUES (1, 'Aurora'), (2, 'Brisa'), (3, 'Cometa'), (4, 'Duna'), (5, 'Eclipse'),
               (6, 'Fênix'), (7, 'Granito'), (8, 'Horizonte'), (9, 'Ícaro'), (10, 'Jade')
    )
INSERT INTO product (id, sku, name, description, price_cents, category_id, active)
SELECT
    leaf.position * 10 + model.number,
    printf('%s-%03d', leaf.code, model.number),
    leaf.label || ' ' || model.label,
    'Linha ' || model.label || ', categoria ' || leaf.label || '.',
    -- Preço sempre terminado em ,90, como em uma loja de verdade
    (leaf.base_cents + model.number * leaf.step_cents) / 100 * 100 + 90,
    leaf.category_id,
    -- Três produtos saíram de linha, para testar consultas que filtram os ativos
    CASE WHEN leaf.position * 10 + model.number IN (10, 47, 83) THEN 0 ELSE 1 END
FROM leaf CROSS JOIN model;

-- ---------------------------------------------------------------------------
-- Clientes: 10 nomes x 6 sobrenomes = 60 clientes
-- ---------------------------------------------------------------------------
WITH
    first_name (position, name, slug) AS (
        VALUES (0, 'Ana', 'ana'), (1, 'Bruno', 'bruno'), (2, 'Carla', 'carla'), (3, 'Diego', 'diego'),
               (4, 'Elisa', 'elisa'), (5, 'Fábio', 'fabio'), (6, 'Gabriela', 'gabriela'),
               (7, 'Heitor', 'heitor'), (8, 'Iara', 'iara'), (9, 'João', 'joao')
    ),
    last_name (position, name, slug) AS (
        VALUES (0, 'Lima', 'lima'), (1, 'Souza', 'souza'), (2, 'Araújo', 'araujo'),
               (3, 'Nunes', 'nunes'), (4, 'Moreira', 'moreira'), (5, 'Teixeira', 'teixeira')
    )
INSERT INTO customer (id, name, email, document, created_at)
SELECT
    first_name.position * 6 + last_name.position + 1,
    first_name.name || ' ' || last_name.name,
    first_name.slug || '.' || last_name.slug || '@exemplo.test',
    printf('%011d', 90000000000 + first_name.position * 6 + last_name.position + 1),
    strftime('%Y-%m-%dT%H:%M:%SZ', '2025-06-01',
             '+' || ((first_name.position * 6 + last_name.position) * 2) || ' days')
FROM first_name CROSS JOIN last_name;

-- ---------------------------------------------------------------------------
-- Endereços: todo cliente tem o principal; 1 em cada 4 tem um segundo
-- ---------------------------------------------------------------------------
WITH city (position, name, state, zip_prefix) AS (
    VALUES (0, 'Fortaleza', 'CE', '60'), (1, 'Recife', 'PE', '50'), (2, 'São Paulo', 'SP', '01'),
           (3, 'Curitiba', 'PR', '80'), (4, 'Belo Horizonte', 'MG', '30'), (5, 'Salvador', 'BA', '40')
)
INSERT INTO address (customer_id, street, number, city, state, zip_code, is_primary)
SELECT customer.id, 'Rua das Flores', printf('%d', customer.id * 7), city.name, city.state,
       city.zip_prefix || printf('%06d', customer.id * 111), 1
FROM customer JOIN city ON city.position = customer.id % 6
UNION ALL
SELECT customer.id, 'Avenida Central', printf('%d', customer.id * 3), city.name, city.state,
       city.zip_prefix || printf('%06d', customer.id * 222), 0
FROM customer JOIN city ON city.position = (customer.id + 1) % 6
WHERE customer.id % 4 = 0;

-- ---------------------------------------------------------------------------
-- Pedidos: 320 pedidos ao longo de 12 meses
-- Os antigos já foram entregues; só os 40 mais recentes ainda estão em andamento.
-- Os clientes de id acima de 55 não têm pedidos, para as consultas com LEFT JOIN.
-- ---------------------------------------------------------------------------
WITH RECURSIVE sequence (n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM sequence WHERE n < 320
)
INSERT INTO customer_order (id, customer_id, status, shipping_street, shipping_number, shipping_city,
                            shipping_state, shipping_zip_code, created_at)
SELECT
    n,
    address.customer_id,
    CASE
        WHEN n % 17 = 0 THEN 'CANCELLED'
        WHEN n <= 280 THEN 'DELIVERED'
        WHEN n % 3 = 0 THEN 'SHIPPED'
        WHEN n % 3 = 1 THEN 'PAID'
        ELSE 'PENDING'
    END,
    address.street, address.number, address.city, address.state, address.zip_code,
    strftime('%Y-%m-%dT%H:%M:%SZ', '2025-11-01',
             '+' || (n * 365 / 320) || ' days', '+' || (n * 13 % 24) || ' hours')
FROM sequence
-- 1 em cada 4 pedidos vai para os 10 primeiros clientes, que acabam comprando mais do que os outros
JOIN address ON address.is_primary = 1
            AND address.customer_id = 1 + (n * 37 % CASE WHEN n % 4 = 0 THEN 10 ELSE 55 END);

-- ---------------------------------------------------------------------------
-- Itens: de 1 a 4 por pedido, sem repetir produto (17, 34, 51 e 68 são distintos no módulo 100)
-- Os pedidos da primeira metade guardam um preço 5% menor: o preço histórico não acompanha o atual.
-- ---------------------------------------------------------------------------
WITH position (value) AS (VALUES (1), (2), (3), (4))
INSERT INTO order_item (order_id, product_id, quantity, unit_price_cents)
SELECT
    customer_order.id,
    product.id,
    1 + (customer_order.id + position.value) % 3,
    CASE WHEN customer_order.id <= 160 THEN product.price_cents * 95 / 100 ELSE product.price_cents END
FROM customer_order
JOIN position ON position.value <= 1 + customer_order.id % 4
JOIN product ON product.id = 1 + (customer_order.id * 31 + position.value * 17) % 100;

-- ---------------------------------------------------------------------------
-- Pagamentos: a soma dos aprovados fecha o total de cada pedido pago (regra 5)
-- ---------------------------------------------------------------------------
WITH order_total AS (
    SELECT order_id, SUM(quantity * unit_price_cents) AS total_cents
    FROM order_item
    GROUP BY order_id
)
INSERT INTO payment (order_id, method, amount_cents, status, created_at)
-- Pagamento único nos pedidos pagos
SELECT customer_order.id,
       CASE customer_order.id % 3 WHEN 0 THEN 'PIX' WHEN 1 THEN 'CARD' ELSE 'BOLETO' END,
       order_total.total_cents, 'APPROVED',
       strftime('%Y-%m-%dT%H:%M:%SZ', customer_order.created_at, '+30 minutes')
FROM customer_order JOIN order_total ON order_total.order_id = customer_order.id
WHERE customer_order.status IN ('PAID', 'SHIPPED', 'DELIVERED') AND customer_order.id % 5 <> 0
UNION ALL
-- 1 em cada 5 paga em duas partes: metade no PIX...
SELECT customer_order.id, 'PIX', order_total.total_cents / 2, 'APPROVED',
       strftime('%Y-%m-%dT%H:%M:%SZ', customer_order.created_at, '+30 minutes')
FROM customer_order JOIN order_total ON order_total.order_id = customer_order.id
WHERE customer_order.status IN ('PAID', 'SHIPPED', 'DELIVERED') AND customer_order.id % 5 = 0
UNION ALL
-- ...e o restante no cartão
SELECT customer_order.id, 'CARD', order_total.total_cents - order_total.total_cents / 2, 'APPROVED',
       strftime('%Y-%m-%dT%H:%M:%SZ', customer_order.created_at, '+35 minutes')
FROM customer_order JOIN order_total ON order_total.order_id = customer_order.id
WHERE customer_order.status IN ('PAID', 'SHIPPED', 'DELIVERED') AND customer_order.id % 5 = 0
UNION ALL
-- 1 em cada 7 teve uma tentativa recusada antes de aprovar
SELECT customer_order.id, 'CARD', order_total.total_cents, 'REFUSED',
       strftime('%Y-%m-%dT%H:%M:%SZ', customer_order.created_at, '+10 minutes')
FROM customer_order JOIN order_total ON order_total.order_id = customer_order.id
WHERE customer_order.status IN ('PAID', 'SHIPPED', 'DELIVERED') AND customer_order.id % 7 = 0
UNION ALL
-- Pedidos pendentes aguardam o pagamento, e os cancelados tiveram o pagamento recusado
SELECT customer_order.id, 'BOLETO', order_total.total_cents,
       CASE customer_order.status WHEN 'PENDING' THEN 'PENDING' ELSE 'REFUSED' END,
       strftime('%Y-%m-%dT%H:%M:%SZ', customer_order.created_at, '+5 minutes')
FROM customer_order JOIN order_total ON order_total.order_id = customer_order.id
WHERE customer_order.status IN ('PENDING', 'CANCELLED');

-- ---------------------------------------------------------------------------
-- Movimentações de estoque: uma saída para cada item vendido...
-- ---------------------------------------------------------------------------
INSERT INTO stock_movement (product_id, order_id, type, quantity, reason, created_at)
SELECT order_item.product_id, order_item.order_id, 'OUT', order_item.quantity, 'Venda', customer_order.created_at
FROM order_item
JOIN customer_order ON customer_order.id = order_item.order_id
WHERE customer_order.status <> 'CANCELLED';

-- ...e uma entrada inicial que cobre as saídas e deixa uma sobra diferente por produto.
INSERT INTO stock_movement (product_id, type, quantity, reason, created_at)
SELECT product.id, 'IN',
       COALESCE((SELECT SUM(quantity) FROM stock_movement WHERE product_id = product.id AND type = 'OUT'), 0)
           + (product.id * 7) % 60 + 2,
       'Compra inicial do fornecedor', '2025-10-15T09:00:00Z'
FROM product;

-- Ajuste de inventário: dois produtos perderam uma unidade na contagem física
INSERT INTO stock_movement (product_id, type, quantity, reason, created_at) VALUES
    (12, 'ADJUSTMENT', -1, 'Divergência na contagem física', '2026-06-30T18:00:00Z'),
    (58, 'ADJUSTMENT', -1, 'Unidade avariada no depósito', '2026-08-15T18:00:00Z');

-- ---------------------------------------------------------------------------
-- Saldo: sempre igual à soma das movimentações (regra 7)
-- ---------------------------------------------------------------------------
INSERT INTO inventory (product_id, quantity, minimum_quantity)
SELECT product.id,
       (SELECT SUM(CASE type WHEN 'OUT' THEN -quantity ELSE quantity END)
        FROM stock_movement WHERE stock_movement.product_id = product.id),
       15
FROM product;

-- ---------------------------------------------------------------------------
-- Avaliações: só de quem recebeu o produto (regra 6), e uma por cliente e produto
-- ---------------------------------------------------------------------------
INSERT INTO review (customer_id, product_id, rating, comment, created_at)
SELECT customer_id, product_id,
       CASE WHEN (customer_id + product_id) % 11 = 0 THEN 1 + (product_id % 2) ELSE 3 + (customer_id * 2 + product_id) % 3 END,
       CASE WHEN (customer_id + product_id) % 11 = 0 THEN 'Não atendeu ao que eu esperava.' ELSE 'Produto conforme o anúncio.' END,
       strftime('%Y-%m-%dT%H:%M:%SZ', MIN(created_at), '+10 days')
FROM (
    SELECT customer_order.customer_id, order_item.product_id, customer_order.created_at
    FROM order_item
    JOIN customer_order ON customer_order.id = order_item.order_id
    WHERE customer_order.status = 'DELIVERED'
)
WHERE (customer_id + product_id) % 3 = 0
GROUP BY customer_id, product_id;

COMMIT;
