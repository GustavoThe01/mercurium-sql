-- Busca textual (FTS5) e atributos em JSON. Rode depois da V004.

-- 1. Busca simples, da mais relevante para a menos relevante (bm25: quanto menor, melhor)
SELECT p.sku, p.name, round(bm25(product_search), 2) AS relevance
FROM product_search
JOIN product p ON p.id = product_search.rowid
WHERE product_search MATCH 'caneca'
ORDER BY bm25(product_search)
LIMIT 5;

-- 2. Sem acento também acha: "luminaria" encontra "Luminária" (remove_diacritics no tokenizer)
SELECT p.sku, p.name
FROM product_search
JOIN product p ON p.id = product_search.rowid
WHERE product_search MATCH 'luminaria'
LIMIT 3;

-- 3. Prefixo e coluna específica: tudo cujo nome começa com "fen" (Fênix)
SELECT p.sku, p.name
FROM product_search
JOIN product p ON p.id = product_search.rowid
WHERE product_search MATCH 'name: fen*'
ORDER BY p.sku;

-- 4. Operadores: produtos de áudio que não são fones, com o termo destacado
SELECT p.sku, highlight(product_search, 2, '[', ']') AS category
FROM product_search
JOIN product p ON p.id = product_search.rowid
WHERE product_search MATCH 'category: (caixas OR fones) NOT fone'
ORDER BY p.sku
LIMIT 5;

-- 5. JSON: canecas com mais de 400 ml, só os produtos ativos
SELECT sku, name, json_extract(attributes, '$.capacidade_ml') AS ml
FROM product
WHERE category_id = 120
  AND active = 1
  AND json_extract(attributes, '$.capacidade_ml') > 400
ORDER BY ml;

-- 6. JSON com índice de expressão: produtos pretos (o plano mostra o ix_product_color)
EXPLAIN QUERY PLAN
SELECT sku FROM product WHERE json_extract(attributes, '$.cor') = 'preto';

SELECT count(*) AS black_products FROM product WHERE json_extract(attributes, '$.cor') = 'preto';

-- 7. json_each: quais tamanhos de camiseta existem e em quantos produtos cada um aparece
SELECT size.value AS size, count(*) AS products
FROM product, json_each(product.attributes, '$.tamanhos') AS size
WHERE product.category_id = 140
GROUP BY size.value
ORDER BY min(size.key);

-- 8. json_each nas chaves: que atributos cada categoria usa
SELECT c.name AS category, group_concat(DISTINCT attribute.key) AS attributes
FROM product p
JOIN category c ON c.id = p.category_id,
     json_each(p.attributes) AS attribute
GROUP BY c.name
ORDER BY c.name;
