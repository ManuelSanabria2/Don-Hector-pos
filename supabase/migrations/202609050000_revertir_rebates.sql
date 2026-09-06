-- ============================================================
-- MIGRATION: 202609050000_revertir_rebates
--
-- Elimina el módulo de rebates (202609030000, 202609030001 y
-- 202609040000) y devuelve las funciones de compras y contabilidad
-- a su versión anterior.
--
-- Por qué: el saldo aparte resultó ser más maquinaria de la que el
-- negocio necesita. En la práctica el proveedor no entrega un saldo
-- para gastar después: descuenta el rebate de la factura del pedido.
-- Eso se representa mejor con un ajuste negativo en la factura, que
-- baja el total y hace que salga de la caja exactamente la plata
-- que salió de verdad. Ver 202609050001 (editar_compra) y el
-- soporte de ajustes negativos en la app.
--
-- Consecuencia buscada: las compras vuelven a contar como efectivo
-- real, sin la exclusión que introdujo el módulo de rebates.
--
-- Nota sobre el enum: Postgres no permite quitar un valor de un
-- enum, así que 'rebate' se queda en metodo_pago sin que nada lo
-- use. No estorba: al restaurar calcular_dinero_disponible deja de
-- estar excluido y se comporta como cualquier otro método.
-- ============================================================


-- ============================================================
-- 1. LAS COMPRAS PAGADAS CON REBATE VUELVEN A SER DE CONTADO
-- Antes de borrar nada: si quedó alguna compra con ese método, se
-- pasa a efectivo para que cuente en el efectivo real, que es el
-- comportamiento que se quiere de aquí en adelante.
-- ============================================================
update compras_inventario
set metodo_pago = 'efectivo',
    notas = coalesce(notas || ' | ', '') || 'Registrada como pagada con rebate; el modulo se retiro'
where metodo_pago::text = 'rebate';


-- ============================================================
-- 2. FUERA EL MÓDULO
-- El drop de la tabla se lleva los movimientos que hubiera y, con
-- ellos, cualquier saldo acumulado.
--
-- La vista se tumba de primera: resumen_financiero_general lee
-- rebates_proveedor para exponer el saldo, así que mientras exista
-- la tabla no se puede borrar. Se vuelve a crear en el punto 6.
-- ============================================================
drop view if exists resumen_financiero_general;

drop function if exists convertir_compra_a_rebate(uuid, text);
drop trigger if exists trg_validar_rebate on rebates_proveedor;
drop function if exists validar_rebate();
drop view if exists saldos_rebates_proveedor;
drop function if exists saldo_rebate_proveedor(uuid);
drop table if exists rebates_proveedor;


-- ============================================================
-- 3. REGISTRAR_COMPRA SIN EL CANJE
-- Vuelve a la versión de 202607080000 (pago inicial de contado
-- auditable), sin el bloque que insertaba el canje.
-- ============================================================
create or replace function registrar_compra(
  p_proveedor_id        uuid,
  p_fecha               date,
  p_metodo_pago         metodo_pago,
  p_notas               text,
  p_items               jsonb,
  p_ajuste              numeric(12,3) default 0,
  p_valor_deuda         numeric(12,3) default 0,
  p_metodo_pago_contado metodo_pago default 'efectivo'
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_compra_id      uuid;
  v_item           record;
  v_stock_antes    integer;
  v_stock_despues  integer;
  v_total_real     numeric(12,3);
  v_total          numeric(12,3);
  v_pago_inicial   numeric(12,3);
  v_fecha_pago     timestamptz;
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra debe incluir al menos un producto';
  end if;

  if p_metodo_pago = 'credito' and coalesce(p_valor_deuda, 0) <= 0 then
    raise exception 'Una compra a crédito debe tener valor en deuda mayor a cero';
  end if;

  if p_metodo_pago_contado = 'credito' then
    raise exception 'El método de pago de la parte de contado no puede ser crédito';
  end if;

  insert into compras_inventario (proveedor_id, fecha, metodo_pago, notas, total, ajuste, valor_deuda)
  values (p_proveedor_id, p_fecha, p_metodo_pago, p_notas, 0, coalesce(p_ajuste, 0), 0)
  returning id into v_compra_id;

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as x(
      producto_id uuid,
      cantidad integer,
      costo_unitario numeric(12,3)
    )
  loop
    if v_item.producto_id is null then
      raise exception 'Cada ítem debe incluir producto_id';
    end if;

    if v_item.cantidad is null or v_item.cantidad <= 0 then
      raise exception 'Cantidad inválida para producto %', v_item.producto_id;
    end if;

    if v_item.costo_unitario is null or v_item.costo_unitario < 0 then
      raise exception 'Costo unitario inválido para producto %', v_item.producto_id;
    end if;

    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
      and activo = true
    for update;

    if not found then
      raise exception 'Producto no existe o está inactivo: %', v_item.producto_id;
    end if;

    insert into detalle_compras (compra_id, producto_id, cantidad, costo_unitario)
    values (v_compra_id, v_item.producto_id, v_item.cantidad, v_item.costo_unitario);

    update productos
    set costo = case
                  when stock_actual > 0 then
                    round(((stock_actual * costo) + (v_item.cantidad * v_item.costo_unitario)) / (stock_actual + v_item.cantidad), 3)
                  else
                    v_item.costo_unitario
                end,
        stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    insert into movimientos_stock (
      producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id
    )
    values (
      v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad,
      v_stock_antes, v_stock_despues, 'compra_inventario', v_compra_id
    );
  end loop;

  select coalesce(sum(subtotal), 0) into v_total_real
  from detalle_compras
  where compra_id = v_compra_id;

  v_total := v_total_real + coalesce(p_ajuste, 0);

  update compras_inventario
  set total = v_total
  where id = v_compra_id;

  if p_metodo_pago = 'credito' then
    if p_valor_deuda > v_total then
      raise exception 'El valor en deuda (%) no puede superar el total de la compra (%)', p_valor_deuda, v_total;
    end if;

    update compras_inventario
    set valor_deuda = v_total
    where id = v_compra_id;

    v_pago_inicial := v_total - p_valor_deuda;

    if v_pago_inicial > 0 then
      if p_fecha >= (now() at time zone 'America/Bogota')::date then
        v_fecha_pago := now();
      else
        v_fecha_pago := p_fecha::timestamp at time zone 'America/Bogota';
      end if;

      insert into pagos_compras (compra_id, monto, metodo_pago, fecha, notas)
      values (v_compra_id, v_pago_inicial, p_metodo_pago_contado, v_fecha_pago, 'Pago inicial de contado');
    end if;
  end if;

  return v_compra_id;
end;
$$;


-- ============================================================
-- 4. ANULAR_COMPRA SIN DEVOLVER SALDO
-- Vuelve a la versión de 202607080000.
-- ============================================================
create or replace function anular_compra(
  p_compra_id uuid,
  p_motivo    text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_anulado        boolean;
  v_item           record;
  v_stock_antes    integer;
  v_stock_despues  integer;
begin
  select anulado into v_anulado
  from compras_inventario
  where id = p_compra_id
  for update;

  if not found then
    raise exception 'La compra especificada no existe.';
  end if;

  if v_anulado then
    raise exception 'La compra ya está anulada.';
  end if;

  for v_item in
    select producto_id, cantidad
    from detalle_compras
    where compra_id = p_compra_id
  loop
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
    for update;

    if not found then
      raise exception 'Producto con ID % no encontrado.', v_item.producto_id;
    end if;

    if v_stock_antes < v_item.cantidad then
      raise exception 'Stock insuficiente para anular la compra';
    end if;

    update productos
    set stock_actual = stock_actual - v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    insert into movimientos_stock (
      producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id
    )
    values (
      v_item.producto_id, 'salida'::tipo_movimiento, v_item.cantidad,
      v_stock_antes, v_stock_despues, 'anulacion_compra', p_compra_id
    );
  end loop;

  update compras_inventario
  set anulado = true,
      notas = coalesce(notas || ' | ', '') || 'ANULADA: ' || coalesce(p_motivo, 'sin motivo')
  where id = p_compra_id;

  update pagos_compras
  set anulado = true
  where compra_id = p_compra_id
    and anulado = false;
end;
$$;


-- ============================================================
-- 5. CALCULAR_DINERO_DISPONIBLE: LAS COMPRAS VUELVEN A RESTAR
-- Vuelve a la versión de 202607140000: solo el crédito se excluye,
-- porque esas se pagan por pagos_compras.
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
    + coalesce((
        select sum(v.total) from ventas v, corte
        where v.estado = 'completada' and v.tipo = 'publico'
          and v.metodo_pago <> 'credito'
          and v.fecha > corte.fecha_corte
      ), 0)
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
        where ci.anulado = false and ci.metodo_pago::text <> 'credito'
          and ci.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pc.monto) from pagos_compras pc, corte
        where pc.anulado = false and pc.fecha > corte.fecha_corte
      ), 0);
$$;


-- ============================================================
-- 6. RESUMEN_FINANCIERO_GENERAL SIN LAS COLUMNAS DE REBATE
-- Se recrea desde cero (ya se tumbó en el punto 2): "create or
-- replace view" puede agregar columnas al final pero no quitarlas.
-- ============================================================
create view resumen_financiero_general
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
        where anulado = false and metodo_pago::text = 'credito'
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
