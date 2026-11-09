# Performance: medir antes de criar índice

Nenhum índice da [`V003`](../migrations/V003__performance.sql) entrou "por garantia". Medi sete consultas
típicas sem índice, criei os índices e medi de novo. Aqui estão os planos lado a lado e o que aprendi,
inclusive onde o índice quase não ajudou.

## Como medi

- **Volume:** com os 320 pedidos do seed, toda consulta leva menos de 1 ms, e não dá para ver diferença.
  Por isso criei a carga [`P001`](../perf/P001__carga_de_volume.sql), num banco separado: cerca de
  5.000 clientes, 200.000 pedidos, 500.000 itens, pagamentos e movimentações.
- **Ordem:** `V001 → S001 → P001 → V002`, mede; aplica a `V003`, roda `ANALYZE` e mede de novo.
- **Consultas:** as sete de [`perf/consultas-medidas.sql`](../perf/consultas-medidas.sql). Os resultados
  conferem antes e depois.
- **Tempo:** mediana de até 7 execuções, com o módulo `sqlite3` do Python (SQLite 3.49.1) no meu notebook.
  O número exato muda de máquina para máquina; a ordem de grandeza e o plano, não.

Para repetir com o CLI do SQLite (o arquivo já liga `.eqp on` e `.timer on`):

```bash
sqlite3 mercurium-perf.db < perf/consultas-medidas.sql
```

## Resultado

| Consulta | Antes | Depois | Ganho |
|---|---:|---:|---|
| Q1. Últimos 10 pedidos de um cliente | 34,3 ms | 0,09 ms | ~380× |
| Q2. Faturamento mensal de 2026 | 288,8 ms | 283,3 ms | quase nenhum |
| Q3. Últimas 20 compras de um produto | 75,3 ms | 18,6 ms | ~4× |
| Q4. Resumo de um pedido pela view | 29,1 ms | 0,08 ms | ~360× |
| Q5. Extrato de estoque de um produto | 68,7 ms | 25,3 ms | ~2,7× |
| Q6. Fila de pedidos pendentes | 42,1 ms | 0,14 ms | ~300× |
| Q7. Top 10 lifetime value | **> 30 s** (interrompi) | 2,8 s | índice + reescrita da view |

E o preço:

| | Sem os índices | Com os índices |
|---|---:|---:|
| Inserir 20.000 pedidos e 20.000 itens (com os triggers) | 557 ms | 931 ms |
| Tamanho do banco de carga | 60,5 MB | 100,0 MB |

## Consulta por consulta

### Q1. Histórico do cliente → índice composto `(customer_id, created_at)`

```
antes:  SCAN customer_order | USE TEMP B-TREE FOR ORDER BY
depois: SEARCH customer_order USING INDEX ix_customer_order_customer_created (customer_id=?)
```

Antes, o SQLite lia os 200.000 pedidos e ainda ordenava. Com o índice, ele vai direto ao cliente e já lê os pedidos
na ordem de `created_at`: o `USE TEMP B-TREE FOR ORDER BY` some do plano. A ordem das colunas importa:
**igualdade primeiro, ordenação ou intervalo depois**. Com `(created_at, customer_id)`, o índice não ajudaria a achar o cliente.

### Q6. Fila de pendentes → `(status, created_at)`

```
antes:  SCAN customer_order | USE TEMP B-TREE FOR ORDER BY
depois: SEARCH customer_order USING INDEX ix_customer_order_status_created (status=?)
```

Mesma regra da Q1. Aqui a **seletividade** ajuda: só 1 em cada 20 pedidos está pendente, então o índice descarta 95% da tabela.

### Q2. Faturamento mensal → quase nada, e está certo

```
antes:  SCAN o | SEARCH i USING PRIMARY KEY (order_id=?) | USE TEMP B-TREE FOR GROUP BY
depois: SEARCH o USING COVERING INDEX ix_customer_order_status_created (status=? AND created_at>?) | ...
```

O plano mudou e o tempo quase não mudou. A consulta precisa de quase metade dos pedidos e de todos os itens deles.
Quando o filtro devolve uma fatia grande da tabela, ler pelo índice custa quase o mesmo que ler tudo.
Índice resolve consulta **seletiva**. Para relatório que agrega muito, o caminho é outro (veja a Q7).

Nas rodadas que fiz, a Q2 variou entre 230 e 290 ms com ou sem índice: a diferença fica dentro da variação normal.

Também testei um índice parcial só com os pedidos que contam como receita
(`WHERE status IN ('PAID', 'SHIPPED', 'DELIVERED')`). Com ele criado, o planejador continuou escolhendo o
`(status, created_at)`, com exatamente o mesmo plano. Não fiquei com ele: seria mais um índice para manter,
sem nenhuma consulta que o use.

### Q3. Compras de um produto → índice de cobertura `(product_id, quantity, unit_price_cents)`

```
antes:  SCAN i | ...
depois: SEARCH i USING COVERING INDEX ix_order_item_product (product_id=?) | ...
```

`COVERING INDEX` quer dizer que a resposta saiu inteira do índice: `quantity` e `unit_price_cents` estão nele, e o
`order_id` vem junto porque faz parte da chave primária. A tabela `order_item` nem é lida. Sobra a ordenação por data,
que está em outra tabela (`customer_order`), e por isso o ganho fica em 4×.

### Q4. A view com subconsulta → índice em `payment (order_id, status, amount_cents)`

```
antes:  CORRELATED SCALAR SUBQUERY 3 | SCAN p
depois: CORRELATED SCALAR SUBQUERY 3 | SEARCH p USING COVERING INDEX ix_payment_order (order_id=? AND status=?)
```

A `vw_order_summary` soma os pagamentos aprovados de cada pedido com uma subconsulta. Sem índice, **cada execução da
subconsulta varre a tabela de pagamentos**. Para um pedido, isso custa 29 ms; para todos, é o desastre da Q7.
O SQLite não cria índice para chave estrangeira sozinho: `payment.order_id` estava sem índice desde a `V001`.

### Q5. Extrato de estoque → `(product_id, created_at)`

O índice entrega as movimentações já em ordem. O ganho é menor (2,7×) porque o produto 42 tem 7.544 movimentações:
o tempo vai para ler e devolver as linhas, não para encontrá-las.

### Q7. Lifetime value → o índice não bastava; a view precisava mudar

```
antes:  MATERIALIZE vw_order_summary | SCAN o | ... | CORRELATED SCALAR SUBQUERY 4 | SCAN p | ...
```

A versão da `V002` montava o LTV em cima da `vw_order_summary`. Para cada um dos 200.000 pedidos, a subconsulta
de pagamentos varria a tabela de pagamentos: algo na casa de 200.000 × 200.000 leituras. Interrompi depois de 30 s.

Com o índice em `payment`, caiu para 4,5 s, mas o problema estava na consulta: o LTV nem usa o valor pago.
Na `V003`, a view passou a somar direto os itens dos pedidos que contam como receita. Conferi que as duas versões
devolvem as mesmas linhas, no banco normal e no de carga. Com isso, ficou em 2,8 s.

2,8 s ainda é muito para uma tela, porque a consulta agrega 500.000 itens toda vez. Se esse relatório for usado com
frequência, o próximo passo é uma **tabela de resumo por cliente**, mantida por trigger. Não fiz isso agora: seria
mais escrita em toda venda, e por enquanto ninguém consome esse relatório em tempo real.

## O que fica

- **Medir antes:** a Q2 mostra que um índice pode mudar o plano sem mudar o tempo.
- **Ordem das colunas:** igualdade primeiro, ordenação ou intervalo depois.
- **Índice de cobertura** evita ler a tabela, quando as colunas certas cabem no índice.
- **Chave estrangeira sem índice** é armadilha: o SQLite não cria esse índice sozinho.
- **Às vezes a consulta é que precisa mudar.** Na Q7, o índice ajudou, mas a reescrita fez mais diferença.
- **Índice custa:** com os seis índices, a escrita ficou cerca de 1,7× mais lenta e o banco de carga cresceu 65%.
  Num sistema que grava muito mais do que lê, essa conta pode virar ao contrário.
