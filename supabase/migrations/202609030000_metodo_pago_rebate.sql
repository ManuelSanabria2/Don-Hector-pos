-- ============================================================
-- MIGRATION: 202609030000_metodo_pago_rebate
--
-- Nuevo método de pago 'rebate': una compra pagada con el saldo a
-- favor que el proveedor otorga por cumplir metas.
--
-- Va SOLA en su propia migración a propósito. Postgres no permite
-- usar un valor de enum recién agregado dentro de la misma
-- transacción que lo agregó, y calcular_dinero_disponible (que sí
-- lo referencia) es `language sql`, o sea que se valida al crearse.
-- La tabla, los RPC y las vistas van en 202609030001.
-- ============================================================

alter type metodo_pago add value if not exists 'rebate';
