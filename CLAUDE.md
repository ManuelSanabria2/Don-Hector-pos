# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"DH POS" — a POS/inventory/accounting system for a liquor store, built as a Flutter app (Android + Windows, single user, always online) backed by Supabase (PostgreSQL). UI text, models, tables, and commit messages are in Spanish. Currency is Colombian pesos (see `lib/core/utils/currency_formatter.dart`).

Two top-level pieces:
- `licores_app/` — the Flutter app (all commands below run from this directory)
- `supabase/migrations/` — versioned SQL migrations applied with `supabase db push` (or pasted into the Supabase SQL Editor). Loose `.sql` files at the repo root are ad-hoc scripts, not migrations.

## Commands

Run from `licores_app/`:

```
flutter pub get                 # install dependencies
flutter run -d windows          # run on Windows desktop
flutter run -d <android-id>     # run on Android device
flutter analyze                 # lint (flutter_lints defaults)
flutter test                    # run tests
flutter test test/check_db_test.dart   # run a single test file
flutter build apk               # Android release build
```

The app requires a `licores_app/.env` file (copied from `.env.example`) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`; `GEMINI_API_KEY` is also read for the voice assistant. `.env` is bundled as a Flutter asset, and the app signs in to Supabase anonymously at startup.

## Architecture

State management is Riverpod 2.x; navigation is go_router with all routes declared in `main.dart` and path constants in `lib/core/constants/app_routes.dart`. The main UI is a single `HomeScreen` shell with tabs (dashboard, inventario, POS, mayoristas, gastos, compras, contabilidad) selected via `homeTabIndexProvider` — most "screens" are tabs inside that shell, not routes. `PosTurboScreen` is a separate full-screen overlay (not a tab) launched from the dashboard for fast walk-up sales.

Layering per feature:
- `lib/data/models/` — plain Dart models with `fromJson`/`toJson` mapping snake_case table columns.
- `lib/data/repositories/` — one repository class per domain wrapping `SupabaseClient` (obtained from `supabaseClientProvider` in `supabase_providers.dart`), each exposed via a `Provider`.
- `lib/features/<feature>/` — screens plus a `<feature>_providers.dart` file holding the Riverpod providers (FutureProvider/StateNotifier) that screens watch.

### Business logic lives in Postgres

Anything transactional or invariant-enforcing is a SQL function called via `client.rpc(...)`, not Dart: `registrar_venta` (sale + stock decrement + historical cost snapshot), `registrar_compra` (purchase + weighted-average cost + capital movement), `anular_venta` / `anular_compra` (logical voiding — records are marked `anulada`, never deleted, and stock/receivables are reversed), `ajustar_stock`, `cogs_rango`. Triggers validate things like payments not exceeding receivable balance.

Consequences for changes:
- A change to sale/purchase/stock/capital behavior usually means a **new migration** in `supabase/migrations/` (named `YYYYMMDDNNNN_description.sql`, using `create or replace function`) plus matching repository/model updates in Dart.
- Later migrations redefine earlier functions — always read the **latest** migration touching a function to know its current signature.
- Reports (contabilidad) exclude voided records; keep the `estado = 'anulada'` filtering convention when adding queries.

### Domain notes

- Sales have two price tiers: `publico` and `mayorista`; wholesale sales require a client and feed cuentas por cobrar (receivables) with partial payments (`cobros`/`pagos_mayoristas`).
- `detalle_ventas` stores the product cost at sale time (historical cost); profit calculations use that, not current product cost.
- Product prices/costs allow decimals; only some categories (e.g. Cerveza) are intended to use them.
- Capital del negocio (`capital_negocio`) tracks money in/out and is updated by purchase/sale flows.
- Supplier rebates (`rebates_proveedor`): a supplier credit earned by hitting volume targets that can *only* be redeemed in that supplier's merchandise. It is a memorandum balance — deliberately outside `patrimonio_estimado` and outside cash — derived from movements (`acumulacion`/`ajuste` add, `canje`/`vencimiento` subtract), never a mutable `saldo` column. Redemption is a normal purchase with `metodo_pago = 'rebate'` **at real list costs** (zero costs would dilute the weighted-average cost and inflate future margins); `registrar_compra` inserts the `canje` in the same transaction, and `anular_compra` gives the balance back.
- The POS voice assistant (`pos_asistente_provider.dart`) uses speech_to_text + flutter_tts and calls the Gemini API over HTTP.
