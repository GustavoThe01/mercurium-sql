# ADR 0002 — Regras críticas no banco, com triggers

- **Status:** Aceita
- **Data:** 2026-11-08

## Contexto
Algumas regras do Mercurium dependem de outras tabelas, e um `CHECK` não as alcança: baixar o estoque na venda,
só marcar o pedido como pago quando os pagamentos fecham o total, só aceitar avaliação de quem recebeu o produto
e seguir o ciclo de status do pedido.

Essas regras podem viver na aplicação, no banco ou nos dois. O banco do Mercurium é o laboratório de dados do
portfólio e pode ser usado por mais de uma aplicação, além de scripts e de quem abre o arquivo direto no
DB Browser.

## Decisão
As regras que protegem a **integridade dos dados** ficam no banco, em triggers da migration `V002`:

- **Estoque:** a movimentação é a fonte da verdade. Inserir em `stock_movement` atualiza `inventory`; saída sem
  saldo é abortada com `RAISE(ABORT)`; o histórico não pode ser alterado nem excluído.
- **Venda:** inserir um item de pedido grava a saída de estoque. Cancelar o pedido devolve o que saiu.
- **Pedido:** só transições válidas de status, e `PAID` só com os pagamentos aprovados fechando o total.
- **Avaliação:** só de quem tem um pedido entregue com aquele produto.
- **Auditoria e `updated_at`:** mudanças de preço, status e estoque mínimo vão para `audit_log`, com o antes e o
  depois em JSON.

O que é **fluxo de tela ou de negócio** continua na aplicação: mensagens para o usuário, permissões, e-mails,
integração com pagamento.

## Alternativas consideradas
- **Tudo na aplicação** — mais fácil de testar e de ler, mas qualquer outro cliente do banco pode furar a regra.
- **Tudo no banco, com procedures** — o SQLite não tem stored procedures, e a regra de negócio ficaria
  presa a SQL, difícil de evoluir.
- **Saldo calculado sempre pela soma das movimentações** — sem risco de divergência, mas toda consulta de estoque
  passaria a somar o histórico inteiro.

## Consequências
- ✅ Nenhum cliente do banco consegue vender sem estoque, pular status ou editar o histórico.
- ✅ A auditoria acontece mesmo quando a alteração é feita direto no banco.
- ⚠️ Trigger é lógica "escondida": quem lê só a aplicação não vê que um `INSERT` em `order_item` mexe no estoque.
  Por isso documento cada trigger na própria migration e mantenho o script `queries/03-views-e-triggers.sql`
  mostrando cada um em ação.
- ⚠️ A ordem de carga importa: a `V002` roda depois do seed, porque os pedidos históricos do seed não devem
  baixar um estoque que só é montado no fim dele. O script de build do Dia 09 vai seguir essa ordem.
- ⚠️ A aplicação ainda deve validar antes de gravar, para dar uma mensagem boa ao usuário. O trigger é a última
  linha de defesa, não a primeira.
