-- ============================================================
-- MIGRATION: 202607140000_patrimonio_balance
--
-- Corrige patrimonio_estimado, que venía dando un número que no
-- correspondía a nada real.
--
-- La fórmula anterior era:
--   cap_ef_ini + cap_inv_ini + ventas_historicas
--     - compras_historicas - gastos_historicos
--
-- Tenía dos fallas:
--
-- 1. Restaba TODAS las compras de inventario, pero nunca volvía a
--    sumar la mercancía que sigue en bodega. Comprar mercancía
--    bajaba el patrimonio como si el dinero se hubiera evaporado.
--    (valor_inventario_actual se exponía pero no entraba en el
--    cálculo.)
--
-- 2. Mezclaba una foto con una película: cap_ef_ini es el conteo
--    físico de caja en capital_negocio.fecha_corte, pero ventas,
--    compras y gastos se sumaban desde el principio de los
--    tiempos. Todo lo ocurrido ANTES del corte ya está reflejado
--    en el conteo de caja, así que se contaba dos veces. En la
--    base real eso son ~136 millones en ventas previas al corte.
--
-- La segunda falla no se arregla cambiando compras por costo de
-- ventas: mientras se acumulen flujos históricos sobre una foto
-- reciente, el número seguirá inflado. Por eso se reemplaza por un
-- balance de verdad, medido sobre el estado ACTUAL:
--
--   patrimonio = dinero disponible
--              + inventario al costo
--              + cuentas por cobrar
--              - deuda con proveedores
--              - préstamos por pagar
--
-- Ventajas: no depende de cuándo se registró el capital, no se
-- descuadra al recalibrar la caja, y cada término es verificable
-- contra algo que se puede contar.
--
-- Con este enfoque los préstamos SÍ se restan (a diferencia de lo
-- que hacía 202607130000): la plata prestada ya está sumada dentro
-- del dinero disponible, así que restar la deuda deja el efecto
-- neto en cero, que es lo correcto.
-- ============================================================

-- ============================================================
-- 1. DINERO DISPONIBLE (efectivo + digital)
--
-- Hermana de calcular_efectivo_real(), que se deja intacta porque
-- responde otra pregunta: "cuánto debe haber en el cajón". Esta
-- responde "cuánta plata tiene el negocio en total".
--
-- La diferencia es el filtro de método de pago: aquí entra también
-- lo recibido por Nequi/transferencia, pero se sigue excluyendo el
-- crédito, porque un fiado o una compra a crédito no mueven plata
-- todavía.
--
-- Supuesto: el saldo digital en fecha_corte era cero. Hoy es
-- exacto (el negocio maneja efectivo: 580 ventas en efectivo
-- contra 1 por Nequi, anterior al corte). Si algún día el saldo
-- digital pesa, hay que agregarle un campo a capital_negocio.
-- ============================================================
create or replace function calcular_dinero_disponible()
returns numeric
language sql
stable
security definer
as $$
  with corte as (
    select
      coalesce((select efectivo_inicial from capital_negocio limit 1), 0) as efectivo_inicial,
      coalesce(
        (select coalesce(fecha_corte, created_at) from capital_negocio limit 1),
        '-infinity'::timestamptz
      ) as fecha_corte
  )
  select
    coalesce((select efectivo_inicial from corte), 0)
    -- Ventas al público cobradas (el fiado no entra: aún no hay plata).
    + coalesce((
        select sum(v.total) from ventas v, corte
        where v.estado = 'completada' and v.tipo = 'publico'
          and v.metodo_pago <> 'credito'
          and v.fecha > corte.fecha_corte
      ), 0)
    -- La plata de mayoristas entra solo cuando abonan.
    + coalesce((
        select sum(pm.monto) from pagos_mayoristas pm, corte
        where pm.anulado = false and pm.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(af.monto) from abonos_fiados af, corte
        where af.anulado = false and af.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(pr.monto) from prestamos pr, corte
        where pr.anulado = false and pr.fecha > corte.fecha_corte
      ), 0)
    -- Solo el capital: el interés ya sale como gasto.
    - coalesce((
        select sum(pp.abono_capital) from pagos_prestamos pp, corte
        where pp.anulado = false and pp.fecha > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(g.monto) from gastos g, corte
        where g.anulado = false and g.created_at > corte.fecha_corte
      ), 0)
    -- Las compras a crédito se pagan por pagos_compras.
    - coalesce((
        select sum(ci.total) from compras_inventario ci, corte
        where ci.anulado = false and ci.metodo_pago <> 'credito'
          and ci.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pc.monto) from pagos_compras pc, corte
        where pc.anulado = false and pc.fecha > corte.fecha_corte
      ), 0);
$$;

-- ============================================================
-- 2. LA VISTA
--
-- Se conservan las columnas históricas (ventas/compras/gastos):
-- siguen siendo útiles como resumen de actividad, solo dejan de
-- ser los ingredientes del patrimonio. Las columnas nuevas van al
-- final porque "create or replace view" no permite insertarlas en
-- medio de las existentes.
-- ============================================================
create or replace view resumen_financiero_general
with (security_invoker = true) as
  with data as (
    select
      coalesce((select efectivo_inicial from capital_negocio limit 1), 0) as cap_ef_ini,
      coalesce((select valor_inventario_inicial from capital_negocio limit 1), 0) as cap_inv_ini,
      coalesce((select sum(total) from ventas where estado = 'completada'), 0) as v_tot,
      coalesce((select sum(total) from compras_inventario where anulado = false), 0) as c_tot,
      coalesce((select sum(monto) from gastos where anulado = false), 0) as g_tot,
      coalesce((select sum(stock_actual * costo) from productos), 0) as inv_act,
      coalesce((select sum(saldo) from prestamos where anulado = false), 0) as prest_deuda,
      coalesce((select sum(interes_pagado) from prestamos where anulado = false), 0) as prest_interes,
      coalesce((select sum(saldo) from cobros_mayoristas where anulado = false), 0) as cxc_may,
      coalesce((select sum(saldo) from fiados_publico where anulado = false), 0) as cxc_fiados,
      coalesce((
        select sum(valor_deuda) from compras_inventario
        where anulado = false and metodo_pago = 'credito'
      ), 0) as deuda_prov,
      calcular_dinero_disponible() as dinero
  )
  select
    cap_ef_ini as capital_efectivo_inicial,
    cap_inv_ini as capital_inventario_inicial,
    v_tot as total_ventas_historico,
    c_tot as total_compras_historico,
    g_tot as total_gastos_historico,
    inv_act as valor_inventario_actual,
    -- Activos menos pasivos, todo medido sobre el estado actual.
    (dinero + inv_act + cxc_may + cxc_fiados - deuda_prov - prest_deuda)
      as patrimonio_estimado,
    prest_deuda as deuda_prestamos,
    prest_interes as interes_prestamos_pagado,
    dinero as dinero_disponible,
    (cxc_may + cxc_fiados) as cuentas_por_cobrar,
    deuda_prov as deuda_proveedores
  from data;
