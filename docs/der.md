# DER — Mercurium

Aqui está o modelo entidade-relacionamento que desenhei a partir dos requisitos em [modelagem.md](modelagem.md).
É o modelo **lógico**: o schema físico (DDL) entra no Dia 03 e segue exatamente estas definições.

## 1. Diagrama

```mermaid
erDiagram
    CUSTOMER ||--o{ ADDRESS : "possui"
    CUSTOMER ||--o{ CUSTOMER_ORDER : "faz"
    CUSTOMER ||--o{ REVIEW : "escreve"
    ADDRESS ||--o{ CUSTOMER_ORDER : "recebe a entrega de"
    CATEGORY |o--o{ CATEGORY : "é pai de"
    CATEGORY ||--o{ PRODUCT : "agrupa"
    PRODUCT ||--|| INVENTORY : "tem saldo em"
    PRODUCT ||--o{ STOCK_MOVEMENT : "é movimentado por"
    PRODUCT ||--o{ ORDER_ITEM : "aparece em"
    PRODUCT ||--o{ REVIEW : "recebe"
    CUSTOMER_ORDER ||--|{ ORDER_ITEM : "contém"
    CUSTOMER_ORDER ||--o{ PAYMENT : "é pago por"
    CUSTOMER_ORDER |o--o{ STOCK_MOVEMENT : "origina"

    CUSTOMER {
        INTEGER id PK
        TEXT name
        TEXT email UK
        TEXT document UK "CPF, só dígitos"
        TEXT created_at
    }
    ADDRESS {
        INTEGER id PK
        INTEGER customer_id FK
        TEXT street
        TEXT number
        TEXT city
        TEXT state "UF"
        TEXT zip_code "CEP, só dígitos"
        INTEGER is_primary "0 ou 1"
    }
    CATEGORY {
        INTEGER id PK
        TEXT name UK
        INTEGER parent_id FK "nulo na raiz"
    }
    PRODUCT {
        INTEGER id PK
        TEXT sku UK
        TEXT name
        TEXT description
        INTEGER price_cents
        INTEGER category_id FK
        INTEGER active "0 ou 1"
    }
    INVENTORY {
        INTEGER product_id PK, FK
        INTEGER quantity
        INTEGER minimum_quantity
    }
    STOCK_MOVEMENT {
        INTEGER id PK
        INTEGER product_id FK
        INTEGER order_id FK "nulo em ajustes e entradas"
        TEXT type "IN, OUT, ADJUSTMENT"
        INTEGER quantity
        TEXT reason
        TEXT created_at
    }
    CUSTOMER_ORDER {
        INTEGER id PK
        INTEGER customer_id FK
        INTEGER shipping_address_id FK
        TEXT status
        TEXT created_at
    }
    ORDER_ITEM {
        INTEGER order_id PK, FK
        INTEGER product_id PK, FK
        INTEGER quantity
        INTEGER unit_price_cents "preço no momento da compra"
    }
    PAYMENT {
        INTEGER id PK
        INTEGER order_id FK
        TEXT method "PIX, CARD, BOLETO"
        INTEGER amount_cents
        TEXT status "PENDING, APPROVED, REFUSED"
        TEXT created_at
    }
    REVIEW {
        INTEGER id PK
        INTEGER customer_id FK
        INTEGER product_id FK
        INTEGER rating "1 a 5"
        TEXT comment
        TEXT created_at
    }
```

## 2. Cardinalidades

| Relação | Cardinalidade | Por quê |
|---|---|---|
| Cliente → Endereço | 1 : N | Um cliente pode ter vários endereços; cada endereço pertence a um único cliente |
| Cliente → Pedido | 1 : N | O cliente pode ainda não ter comprado (0) ou ter muitos pedidos |
| Endereço → Pedido | 1 : N | O pedido guarda **qual** endereço recebeu a entrega |
| Categoria → Categoria | 0..1 : N | Auto-relacionamento: a categoria raiz não tem pai |
| Categoria → Produto | 1 : N | Todo produto está em exatamente uma categoria |
| Produto → Estoque | 1 : 1 | Cada produto tem um único saldo; separei em outra tabela porque o saldo muda o tempo todo e o cadastro quase nunca |
| Pedido ↔ Produto | N : N | Resolvido pela tabela associativa `order_item` |
| Pedido → Pagamento | 1 : N | Um pedido pode ser pago em partes (ex.: PIX + cartão) ou ter tentativas recusadas |
| Produto → Movimentação | 1 : N | Histórico completo de entradas, saídas e ajustes |
| Cliente/Produto → Avaliação | 1 : N | Uma avaliação por cliente e produto (regra garantida no Dia 03) |

## 3. Decisões de modelagem

1. **`customer_order` em vez de `order`.** `ORDER` é palavra reservada do SQL (`ORDER BY`). Usar esse nome
   me obrigaria a escrever `"order"` entre aspas em toda consulta, o que é fonte de erro. Mantive o nome
   `order_item` porque ali não há conflito.
2. **Chaves surrogate (`INTEGER PRIMARY KEY`)** em todas as tabelas principais. Chaves naturais (e-mail, CPF, SKU)
   continuam únicas com `UNIQUE`, mas podem mudar; a chave técnica não muda nunca.
3. **Chave composta em `order_item`** (`order_id`, `product_id`): o mesmo produto não aparece duas vezes
   no mesmo pedido, a quantidade é que aumenta.
4. **Dinheiro em centavos (`INTEGER`)**, como decidi no [ADR 0001](adr/0001-usar-sqlite.md).
5. **Datas em `TEXT` no formato ISO 8601** (`2026-11-03T14:30:00Z`), o padrão recomendado pelo SQLite para
   usar as funções `date()`, `datetime()` e `strftime()`.
6. **O total do pedido não é coluna.** Ele é derivado de `SUM(quantity * unit_price_cents)`. Guardar o total
   criaria uma dependência transitiva (ver a 3FN abaixo) e o risco de o valor ficar diferente da soma dos itens.
   Se a consulta ficar lenta, uma view ou uma coluna mantida por trigger resolve, de forma consciente.
7. **`unit_price_cents` é cópia proposital.** Parece duplicação do preço do produto, mas não é: é o preço
   **histórico**, que não pode mudar quando o produto for reajustado.

## 4. Normalização, passo a passo

Para mostrar de onde o modelo veio, parti de uma planilha "ingênua" de pedidos, do jeito que muita loja
pequena controla as vendas.

### Antes: tudo numa linha só (não normalizado)

| pedido | data | cliente | email | produtos | categorias | total |
|---|---|---|---|---|---|---|
| 1001 | 2026-11-01 | Ana Lima | ana@mail.com | Caneca (2x R$ 30), Camiseta (1x R$ 80) | Cozinha, Vestuário | R$ 140 |
| 1002 | 2026-11-02 | Ana Lima | ana@mail.com | Caneca (1x R$ 32) | Cozinha | R$ 32 |

Problemas: a coluna `produtos` guarda vários valores numa célula só, o e-mail da Ana se repete em cada
pedido e o total pode facilmente divergir dos itens.

### 1FN — valores atômicos, sem grupos repetidos

Separei cada produto do pedido numa linha própria.

| pedido | data | cliente | email | produto | categoria | qtd | preço |
|---|---|---|---|---|---|---|---|
| 1001 | 2026-11-01 | Ana Lima | ana@mail.com | Caneca | Cozinha | 2 | 30 |
| 1001 | 2026-11-01 | Ana Lima | ana@mail.com | Camiseta | Vestuário | 1 | 80 |
| 1002 | 2026-11-02 | Ana Lima | ana@mail.com | Caneca | Cozinha | 1 | 32 |

A chave agora é composta: (`pedido`, `produto`).

### 2FN — nada depende só de parte da chave

`data`, `cliente` e `email` dependem só de `pedido`; `categoria` depende só de `produto`.
Separei em três tabelas:

- **pedido** (`pedido`, `data`, `cliente`, `email`)
- **produto** (`produto`, `categoria`)
- **item_pedido** (`pedido`, `produto`, `qtd`, `preço`) → depende da chave inteira

### 3FN — nada depende de outro atributo que não seja a chave

Em **pedido**, o `email` depende do `cliente`, e não do pedido (dependência transitiva
`pedido → cliente → email`). Movi os dados do cliente para uma tabela própria:

- **cliente** (`id`, `nome`, `email`)
- **pedido** (`id`, `cliente_id`, `data`)

Com o mesmo raciocínio, a categoria virou tabela própria e o `total` saiu do pedido (é calculado).
O resultado é exatamente o DER da seção 1.

### Onde aceitei desnormalizar (de propósito)

| Dado | Por que fica "duplicado" |
|---|---|
| `order_item.unit_price_cents` | É o preço histórico da compra, não uma cópia do preço atual |
| `customer_order.shipping_address_id` | Aponta para o endereço usado; se o cliente editar o endereço depois, o pedido não pode mudar. No Dia 03 decido se o endereço de entrega vira cópia (snapshot) no próprio pedido |

## 5. Próximos passos
- **Dia 03:** transformar este modelo em `migrations/V001__create_schema.sql` com `STRICT`, `CHECK`, `UNIQUE` e `ON DELETE`.
