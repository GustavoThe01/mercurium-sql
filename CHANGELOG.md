# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Estrutura do repositório (`docs/`, `migrations/`, `seeds/`, `queries/`, `tests/`, `scripts/`).
- Documento de requisitos e regras de negócio (`docs/modelagem.md`).
- ADR 0001 — escolha do SQLite.
- DER completo em `docs/der.md`: 10 tabelas, cardinalidades, decisões de modelagem e normalização até a 3FN passo a passo.
- Schema físico em `migrations/V001__create_schema.sql`: 10 tabelas `STRICT`, com `CHECK`, `UNIQUE`, chaves estrangeiras e `ON DELETE` justificado em `docs/der.md`.
- Índice único parcial que garante no máximo um endereço principal por cliente.
- Dados de exemplo em `seeds/S001__dados_de_exemplo.sql`: 19 categorias em 3 níveis, 100 produtos, 60 clientes, 320 pedidos e 211 avaliações, gerados por CTEs recursivas e reproduzíveis.
- Demonstração de `ROLLBACK` e atomicidade em `queries/00-transacoes.sql`.
- 15 perguntas de negócio respondidas em `queries/01-fundamentos.sql`, com `JOIN`, `GROUP BY`, `HAVING`, `CASE`, subconsultas correlacionadas e `EXISTS`.
- 10 consultas analíticas em `queries/02-avancadas.sql`: CTE recursiva da árvore de categorias, `ROW_NUMBER`, `RANK`/`DENSE_RANK`, `LAG`/`LEAD`, `NTILE`, total acumulado e média móvel com framing `ROWS`.
- Extrato de estoque por produto com saldo acumulado, conferido contra o estoque atual.
- Migration `V002` com as views `vw_order_summary`, `vw_customer_lifetime_value` e `vw_low_stock`.
- Estoque guiado pelas movimentações: inserir em `stock_movement` atualiza `inventory`, saída sem saldo é abortada com `RAISE(ABORT)` e o histórico não pode ser alterado nem excluído.
- Triggers de venda (item de pedido baixa o estoque), cancelamento (devolve o estoque), transições de status, pagamento que fecha o total e avaliação só de quem recebeu o produto.
- Tabela `audit_log` com o antes e o depois em JSON, e `updated_at` automático em `product` e `customer_order`.
- Script `queries/03-views-e-triggers.sql`, que mostra cada regra em ação dentro de uma transação desfeita no fim.
- ADR 0002 — regras críticas no banco, com triggers.

### Alterado
- A tabela de pedidos passa a se chamar `customer_order`, porque `order` é palavra reservada do SQL.
- O total do pedido deixa de ser coluna e passa a ser calculado a partir dos itens.
- O endereço de entrega passa a ser copiado para o pedido (snapshot), em vez de apontar para `address`.
