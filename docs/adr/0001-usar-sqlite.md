# ADR 0001 — Usar SQLite como banco do laboratório

- **Status:** Aceita
- **Data:** 2026-11-03

## Contexto
O projeto é um laboratório de modelagem e SQL que precisa rodar em qualquer máquina e no CI
sem servidor, sem Docker e sem credenciais. O mesmo modelo será reaproveitado pelas APIs do portfólio.

## Decisão
Usar **SQLite 3** com tabelas `STRICT` e `PRAGMA foreign_keys = ON` em todas as conexões.

## Alternativas consideradas
- **PostgreSQL** — mais recursos (tipos ricos, `GENERATED`, particionamento, concorrência real),
  porém exige servidor/Docker e torna o setup e o CI mais pesados.
- **SQL Server / MySQL** — mesmos custos de infraestrutura, sem ganho para o objetivo didático.

## Consequências
- ✅ Banco é um único arquivo, recriável por script; CI trivial.
- ✅ Suporta CTEs, window functions, triggers, FTS5 e JSON — cobre todo o roadmap.
- ⚠️ Tipagem dinâmica por padrão: mitigada com `STRICT` e `CHECK`.
- ⚠️ Sem tipo `DECIMAL` nativo: valores monetários serão guardados em **centavos (`INTEGER`)**.
- ⚠️ Um único escritor por vez: aceitável para laboratório; uma migração para PostgreSQL
  seria registrada em um novo ADR.
