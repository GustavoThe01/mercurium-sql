-- V004: busca textual de produtos com FTS5 e atributos em JSON.
-- Rode depois da V003. Os atributos são preenchidos a partir dos produtos do seed.

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ===========================================================================
-- Atributos em JSON
-- Cada categoria tem atributos diferentes (capacidade da caneca, numeração do tênis...).
-- Uma coluna por atributo deixaria a tabela cheia de NULL; uma tabela chave-valor complicaria toda consulta.
-- O JSON fica no meio: flexível, validado pelo CHECK e consultável com json_extract e json_each.
-- ===========================================================================

ALTER TABLE product ADD COLUMN attributes TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(attributes));

-- Cor para todos, mais os atributos de cada categoria. O número do modelo (1 a 10) é o resto de id por 10.
UPDATE product
SET attributes = json_patch(
    json_object('cor', CASE (id - 1) % 10 % 5
        WHEN 0 THEN 'preto' WHEN 1 THEN 'branco' WHEN 2 THEN 'azul' WHEN 3 THEN 'verde' ELSE 'vermelho' END),
    CASE category_id
        WHEN 100 THEN json_object('conexao', CASE WHEN id % 2 = 0 THEN 'bluetooth' ELSE 'cabo' END,
                                  'bateria_horas', CASE WHEN id % 2 = 0 THEN 10 + (id % 10) * 2 ELSE NULL END)
        WHEN 101 THEN json_object('potencia_w', 10 + (id % 10) * 5, 'a_prova_dagua', json(CASE WHEN id % 3 = 0 THEN 'true' ELSE 'false' END))
        WHEN 110 THEN json_object('layout', 'ABNT2', 'mecanico', json(CASE WHEN id % 2 = 0 THEN 'true' ELSE 'false' END))
        WHEN 111 THEN json_object('notebook_polegadas', CASE WHEN id % 2 = 0 THEN 15.6 ELSE 14 END, 'litros', 18 + id % 10)
        WHEN 120 THEN json_object('capacidade_ml', 250 + (id % 10) * 25, 'material', 'cerâmica')
        WHEN 121 THEN json_object('material', CASE WHEN id % 2 = 0 THEN 'inox' ELSE 'ferro fundido' END, 'diametro_cm', 16 + (id % 10) * 2)
        WHEN 130 THEN json_object('lampada', 'LED', 'potencia_w', 5 + id % 10)
        WHEN 131 THEN json_object('largura_cm', 30 + (id % 10) * 10, 'altura_cm', 40 + (id % 10) * 10)
        WHEN 140 THEN json_object('tecido', 'algodão', 'tamanhos', json_array('P', 'M', 'G', 'GG'))
        WHEN 150 THEN json_object('uso', CASE WHEN id % 2 = 0 THEN 'corrida' ELSE 'casual' END,
                                  'numeracao', json_array(37, 38, 39, 40, 41, 42, 43, 44))
        ELSE '{}'
    END);

-- Índice sobre uma expressão: o filtro por cor usa o índice, sem ler o JSON de cada produto.
-- Só funciona se a consulta usar exatamente a mesma expressão.
CREATE INDEX ix_product_color ON product (json_extract(attributes, '$.cor'));

-- ===========================================================================
-- Busca textual com FTS5
-- LIKE '%caneca%' não usa índice, não ordena por relevância e não ignora acentos.
-- A tabela FTS5 tem um índice invertido próprio, ranking por bm25 e remoção de acentos no tokenizer.
-- ===========================================================================

CREATE VIRTUAL TABLE product_search USING fts5(
    name,
    description,
    category,
    tokenize = 'unicode61 remove_diacritics 2'
);

-- O rowid da busca é o id do produto. A sincronização é feita pelos triggers abaixo.
INSERT INTO product_search (rowid, name, description, category)
SELECT p.id, p.name, p.description, c.name
FROM product p
JOIN category c ON c.id = p.category_id;

CREATE TRIGGER trg_product_search_insert
AFTER INSERT ON product
BEGIN
    INSERT INTO product_search (rowid, name, description, category)
    SELECT NEW.id, NEW.name, NEW.description, name FROM category WHERE id = NEW.category_id;
END;

CREATE TRIGGER trg_product_search_update
AFTER UPDATE OF name, description, category_id ON product
BEGIN
    DELETE FROM product_search WHERE rowid = OLD.id;
    INSERT INTO product_search (rowid, name, description, category)
    SELECT NEW.id, NEW.name, NEW.description, name FROM category WHERE id = NEW.category_id;
END;

CREATE TRIGGER trg_product_search_delete
AFTER DELETE ON product
BEGIN
    DELETE FROM product_search WHERE rowid = OLD.id;
END;

-- Renomear uma categoria muda a busca de todos os produtos dela.
CREATE TRIGGER trg_product_search_category
AFTER UPDATE OF name ON category
BEGIN
    UPDATE product_search SET category = NEW.name
    WHERE rowid IN (SELECT id FROM product WHERE category_id = NEW.id);
END;

COMMIT;

ANALYZE;
