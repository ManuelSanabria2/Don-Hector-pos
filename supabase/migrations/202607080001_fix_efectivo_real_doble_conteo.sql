-- ============================================================
-- MIGRATION: 202607080001_fix_efectivo_real_doble_conteo
-- Corrige calcular_efectivo_real(): gastos y compras_inventario
-- de contado se comparaban contra el DÍA del corte (fecha, tipo
-- date) en vez del INSTANTE exacto (fecha_corte, timestamptz).
--
-- Efecto del bug: al recalibrar caja (fecha_corte = now()), todo
-- gasto o compra en efectivo registrado ESE MISMO DÍA pero ANTES
-- de la recalibración ya estaba reflejado en el conteo físico
-- (efectivo_inicial), y sin embargo la función lo restaba una
-- segunda vez por comparar día completo en vez de instante. Esto
-- hacía que "Efectivo Real" quedara por debajo del efectivo físico
-- real en caja.
--
-- Fix: usar created_at (timestamptz, momento real de registro)
-- comparado contra fecha_corte, igual que ventas/pagos_mayoristas/
-- pagos_compras.
-- ============================================================
create or replace function calcular_efectivo_real()
returns numeric
language sql
stable
security definer
as $$
  with corte as (
    -- Siempre produce una fila: sin capital registrado se acumula
    -- todo el historial sobre una base de cero.
    select
      coalesce((select efectivo_inicial from capital_negocio limit 1), 0) as efectivo_inicial,
      coalesce(
        (select coalesce(fecha_corte, created_at) from capital_negocio limit 1),
        '-infinity'::timestamptz
      ) as fecha_corte
  )
  select
    coalesce((select efectivo_inicial from corte), 0)
    + coalesce((
        select sum(v.total)
        from ventas v, corte
        where v.estado = 'completada'
          and v.tipo = 'publico'
          and v.metodo_pago = 'efectivo'
          and v.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(pm.monto)
        from pagos_mayoristas pm, corte
        where pm.anulado = false
          and pm.metodo_pago = 'efectivo'
          and pm.fecha > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(g.monto)
        from gastos g, corte
        where g.anulado = false
          and g.metodo_pago = 'efectivo'
          and g.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(ci.total)
        from compras_inventario ci, corte
        where ci.anulado = false
          and ci.metodo_pago = 'efectivo'
          and ci.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pc.monto)
        from pagos_compras pc, corte
        where pc.anulado = false
          and pc.metodo_pago = 'efectivo'
          and pc.fecha > corte.fecha_corte
      ), 0);
$$;
