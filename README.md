# Mercurium · sql-ecommerce-lab

> *Mercúrio, deus romano do comércio, guarda os dados de uma loja virtual.*

Laboratório de **modelagem e consultas SQL** com **SQLite**, usando o domínio de um e-commerce
(clientes, produtos, categorias, pedidos, pagamentos, estoque e avaliações).

> Este schema é a base conceitual do projeto [Bifrost](../bifrost-orders/).

## Competências demonstradas
- Modelagem conceitual → lógica → física (DER em Mermaid)
- Normalização (1FN, 2FN, 3FN) e quando desnormalizar
- Restrições: `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `CHECK`, `NOT NULL`, tabelas `STRICT`
- Consultas: `JOIN`s, agregações, subconsultas, **CTEs** (inclusive recursivas), **window functions**
- **Views**, **triggers** (auditoria, estoque), transações
- Performance: **índices** (composto, parcial, de cobertura) e `EXPLAIN QUERY PLAN`
- Recursos do SQLite: **FTS5** (busca textual) e funções **JSON**
- Migrações versionadas, scripts de build e testes de integridade em CI

## Estrutura planejada
```
mercurium-sql/
├── docs/
│   ├── adr/
│   ├── der.md             # diagrama entidade-relacionamento (Mermaid)
│   ├── modelagem.md       # decisões de normalização
│   └── performance.md     # análises antes/depois de índices
├── migrations/            # V001__create_schema.sql, V002__...
├── seeds/                 # dados de exemplo
├── queries/               # exercícios resolvidos, por nível
├── tests/                 # asserts de integridade
└── scripts/               # build.ps1 / build.sh (recria o banco do zero)
```

## Como rodar
_A preencher no Dia 09 (script de build)._

## Status
Veja o [ROADMAP.md](ROADMAP.md).
