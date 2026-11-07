# Roadmap — Mercurium (10 dias)

## Semana 1 — Modelagem e estrutura

### Dia 01 — Repositório e requisitos
- [x] Criar repositório, `.gitignore`, `CHANGELOG.md`, pasta `docs/adr/`
- [x] Listar requisitos do domínio em `docs/modelagem.md` (entidades, regras de negócio)
- [x] ADR 0001 — Por que SQLite (prós, limitações, quando trocaria por PostgreSQL)
- **Conceitos:** levantamento de requisitos, ADR

### Dia 02 — Modelo conceitual e lógico
- [x] DER em Mermaid (`erDiagram`) em `docs/der.md`
- [x] Cardinalidades (1:N, N:N com tabela associativa)
- [x] Documentar a normalização até a 3FN, com um exemplo de tabela "antes/depois"
- **Conceitos:** cardinalidade, chaves naturais vs. surrogate, normalização

### Dia 03 — Schema físico (DDL)
- [x] `migrations/V001__create_schema.sql` com tabelas `STRICT`
- [x] `PRAGMA foreign_keys = ON`, `CHECK` (preço > 0, status válidos), `UNIQUE` (e-mail, SKU)
- [x] `ON DELETE` adequado em cada FK (RESTRICT vs CASCADE) e justificativa
- **Conceitos:** integridade referencial, tipos no SQLite (type affinity)

### Dia 04 — Dados de exemplo
- [x] `seeds/` com dados realistas (≥ 50 clientes, 100 produtos, 300 pedidos)
- [x] Inserções dentro de `BEGIN/COMMIT`; testar um `ROLLBACK` proposital
- [x] Categorias hierárquicas (categoria pai/filha) para usar no Dia 06
- **Conceitos:** transações, ACID

### Dia 05 — Consultas fundamentais
- [x] `queries/01-fundamentos.sql`: 15 perguntas de negócio com enunciado + solução
- [x] `INNER/LEFT JOIN`, `GROUP BY`, `HAVING`, `CASE`, subconsultas correlacionadas, `EXISTS`
- **Conceitos:** ordem lógica de execução do SELECT

## Semana 2 — SQL avançado, performance e entrega

### Dia 06 — CTEs e window functions
- [x] `queries/02-avancadas.sql`
- [x] CTE recursiva para árvore de categorias
- [x] `ROW_NUMBER`, `RANK`, `LAG/LEAD`, total acumulado, média móvel, top-N por grupo
- **Conceitos:** particionamento e framing de janelas

### Dia 07 — Views e triggers
- [ ] Views: `vw_order_summary`, `vw_customer_lifetime_value`, `vw_low_stock`
- [ ] Trigger de baixa de estoque ao inserir item de pedido (com `RAISE(ABORT)` se faltar)
- [ ] Tabela `audit_log` + triggers de auditoria; `updated_at` automático
- **Conceitos:** regras no banco vs. na aplicação (registrar em ADR 0002)

### Dia 08 — Performance
- [ ] Medir consultas lentas com `EXPLAIN QUERY PLAN` (antes)
- [ ] Criar índices compostos, parciais e de cobertura (depois)
- [ ] Documentar tudo em `docs/performance.md` com os planos lado a lado
- **Conceitos:** seletividade, ordem de colunas em índice composto, custo de escrita

### Dia 09 — Migrações, FTS5 e JSON
- [ ] `V002__add_product_search.sql` com tabela virtual **FTS5** para busca de produtos
- [ ] Coluna de atributos em JSON (`json_extract`, `json_each`)
- [ ] `scripts/build.ps1` e `scripts/build.sh`: recriam o banco aplicando migrations + seeds
- [ ] Preencher "Como rodar" no README
- **Conceitos:** versionamento de schema, migrações idempotentes

### Dia 10 — Testes, CI e release
- [ ] `tests/integrity.sql`: consultas que devem retornar 0 linhas (órfãos, estoque negativo...)
- [ ] GitHub Actions: instala sqlite3, roda build + testes
- [ ] README final com DER, exemplos de consultas e resultados
- [ ] `CHANGELOG.md` + tag `v1.0.0`
- **Conceitos:** testes de banco, CI

## Ideias de evolução (opcional)
- Particionar histórico de pedidos por ano em tabelas de arquivo
- Comparar o mesmo schema em PostgreSQL (diferenças de tipos e de recursos)
