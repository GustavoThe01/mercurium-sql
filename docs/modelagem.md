# Modelagem — Mercurium

> *Mercurium* vem de Mercúrio, deus romano do comércio. É o "cofre" de dados de uma loja virtual fictícia.

## 1. Visão do negócio
Uma loja virtual vende produtos organizados em categorias hierárquicas. Clientes fazem pedidos,
pagam por um ou mais meios de pagamento e podem avaliar o que compraram. O estoque é controlado
por produto e toda movimentação deve ser rastreável.

## 2. Entidades (primeira versão)

| Entidade | Descrição | Atributos principais |
|----------|-----------|----------------------|
| `customer` | Cliente cadastrado | nome, e-mail (único), documento (único), data de cadastro |
| `address` | Endereço do cliente (1 cliente : N endereços) | logradouro, cidade, UF, CEP, se é o principal |
| `category` | Categoria de produto, com categoria pai opcional | nome, `parent_id` |
| `product` | Item vendável | SKU (único), nome, descrição, preço, ativo |
| `inventory` | Saldo de estoque por produto (1:1) | quantidade disponível, estoque mínimo |
| `stock_movement` | Histórico de entradas e saídas | tipo, quantidade, motivo, data |
| `customer_order` | Pedido do cliente (`order` é palavra reservada do SQL) | status, data, endereço de entrega (o total é calculado a partir dos itens) |
| `order_item` | Itens do pedido (N:N pedido ↔ produto) | quantidade, preço unitário **no momento da compra** |
| `payment` | Pagamento do pedido (1 pedido : N pagamentos) | método, valor, status, data |
| `review` | Avaliação de produto por cliente | nota (1–5), comentário, data |

## 3. Regras de negócio
1. E-mail e documento do cliente são únicos.
2. Preço do produto deve ser maior que zero; estoque nunca pode ficar negativo.
3. O preço do item é **copiado** para `order_item` — mudar o preço do produto não altera pedidos antigos.
4. Status do pedido: `PENDING → PAID → SHIPPED → DELIVERED`, ou `CANCELLED` antes do envio.
5. A soma dos pagamentos aprovados deve ser igual ao total do pedido para ele virar `PAID`.
6. O cliente só pode avaliar um produto que comprou e recebeu, uma única vez por produto.
7. Toda alteração de estoque gera um registro em `stock_movement`.
8. Produtos são desativados, nunca excluídos, se já aparecem em algum pedido.

## 4. Perguntas de negócio que o banco deve responder
- Quais os 10 produtos mais vendidos no mês, por categoria?
- Qual o ticket médio e o valor total gasto por cliente (*lifetime value*)?
- Quais produtos estão abaixo do estoque mínimo?
- Qual a evolução mensal do faturamento e o crescimento em relação ao mês anterior?
- Quais clientes não compram há mais de 90 dias?

## 5. Próximos passos
- ✅ Dia 02: DER, cardinalidades e normalização até a 3FN em [der.md](der.md).
- ✅ Dia 03: schema físico em [`V001__create_schema.sql`](../migrations/V001__create_schema.sql).
- ✅ Dia 04: dados de exemplo em [`S001__dados_de_exemplo.sql`](../seeds/S001__dados_de_exemplo.sql).
- ✅ Dia 05: 15 perguntas respondidas em [`01-fundamentos.sql`](../queries/01-fundamentos.sql).
- ✅ Dia 06: 10 consultas analíticas em [`02-avancadas.sql`](../queries/02-avancadas.sql), com CTEs e window functions.
- ✅ Dia 07: views, triggers das regras 2, 4, 5, 6 e 7 e auditoria, na [`V002`](../migrations/V002__views_e_triggers.sql).
- ✅ Dia 08: seis índices e uma view reescrita, todos medidos em [`performance.md`](performance.md).
- ✅ Dia 09: busca com FTS5 e atributos em JSON na [`V004`](../migrations/V004__busca_e_atributos.sql), e o build em [`scripts/`](../scripts).
- Dia 10: testes de integridade e CI.
