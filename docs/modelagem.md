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
| `order` | Pedido do cliente | status, data, endereço de entrega, total |
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
- Dia 02: DER em Mermaid ([der.md](der.md)) e normalização até a 3FN.
