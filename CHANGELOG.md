# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Estrutura do repositório (`docs/`, `migrations/`, `seeds/`, `queries/`, `tests/`, `scripts/`).
- Documento de requisitos e regras de negócio (`docs/modelagem.md`).
- ADR 0001 — escolha do SQLite.
- DER completo em `docs/der.md`: 10 tabelas, cardinalidades, decisões de modelagem e normalização até a 3FN passo a passo.

### Alterado
- A tabela de pedidos passa a se chamar `customer_order`, porque `order` é palavra reservada do SQL.
- O total do pedido deixa de ser coluna e passa a ser calculado a partir dos itens.
