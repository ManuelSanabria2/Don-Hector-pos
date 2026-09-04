-- ============================================================
-- MIGRATION: 202609030001_rebates_proveedor
--
-- REBATES DE PROVEEDOR (bonificación por cumplir metas)
--
-- El proveedor reconoce un porcentaje por volumen, pero ese dinero
-- NO se puede retirar: solo se canjea en mercancía del mismo
-- proveedor. Contablemente es un saldo a favor restringido, no
-- efectivo y no una cuenta por cobrar normal.
--
-- Criterio elegido: el saldo acumulado es una CUENTA DE ORDEN
-- (memorando). No entra al patrimonio mientras está acumulado —si
-- nunca se canjea no vale nada— y se convierte en utilidad el día
-- del canje, cuando entra mercancía sin que salga plata de la caja.
--
-- El canje se registra como una compra normal con
-- metodo_pago = 'rebate' y el costo REAL de lista de cada producto,
-- nunca a costo cero: registrar_compra recalcula costo promedio
-- ponderado, así que meter unidades a costo 0 diluiría el costo del
-- producto e inflaría la utilidad de sus ventas futuras. Lo que
-- cambia no es el costo de la mercancía, es de dónde salió la plata.
-- ============================================================


-- ============================================================
-- 1. TABLA: REBATES_PROVEEDOR
--
-- Libro de movimientos del saldo, no un campo `saldo` mutable: el
-- saldo se deriva sumando, igual que cobros/pagos de mayoristas, y
-- así queda auditable de dónde salió cada peso.
--
-- Tipos (todos con monto > 0; el signo lo pone el tipo):
--   acumulacion (+) el proveedor reconoce la bonificación
--   ajuste      (+) corrección a favor del negocio
--   canje       (-) se consume comprando mercancía
--   vencimiento (-) el proveedor lo caduca sin usarse
-- ============================================================
create table if not exists rebates_proveedor (
  id           uuid primary key default uuid_generate_v4(),
  proveedor_id uuid not null references proveedores(id) on delete restrict,
  fecha        date not null default current_date,
  tipo         text not null check (tipo in ('acumulacion', 'ajuste', 'canje', 'vencimiento')),
  monto        numeric(12,3) not null check (monto > 0),
  compra_id    uuid references compras_inventario(id) on delete cascade,
  notas        text,
  anulado      boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists idx_rebates_proveedor_proveedor
  on rebates_proveedor (proveedor_id, anulado);

create index if not exists idx_rebates_proveedor_compra
  on rebates_proveedor (compra_id);

-- RLS deshabilitado, consistente con compras_inventario y
-- pagos_compras (ver 202607030000).
alter table rebates_proveedor disable row level security;


-- ============================================================
-- 2. SALDO DISPONIBLE
-- ============================================================
create or replace function saldo_rebate_proveedor(p_proveedor_id uuid)
returns numeric
language sql
stable
security definer
as $$
  select coalesce(sum(
    case when tipo in ('acumulacion', 'ajuste') then monto else -monto end
  ), 0)
  from rebates_proveedor
  where proveedor_id = p_proveedor_id
    and anulado = false;
$$;

-- Una fila por proveedor activo, aunque nunca haya tenido rebates:
-- la pantalla los lista todos y muestra 0 en los que no aplican.
create or replace view saldos_rebates_proveedor
with (security_invoker = true) as
  select
    p.id     as proveedor_id,
    p.nombre as proveedor,
    coalesce(sum(r.monto) filter (where r.tipo = 'acumulacion'), 0) as acumulado,
    coalesce(sum(r.monto) filter (where r.tipo = 'ajuste'), 0)      as ajustado,
    coalesce(sum(r.monto) filter (where r.tipo = 'canje'), 0)       as canjeado,
    coalesce(sum(r.monto) filter (where r.tipo = 'vencimiento'), 0) as vencido,
    coalesce(sum(
      case when r.tipo in ('acumulacion', 'ajuste') then r.monto else -r.monto end
    ), 0) as saldo
  from proveedores p
  left join rebates_proveedor r
    on r.proveedor_id = p.id
   and r.anulado = false
  where p.activo = true
  group by p.id, p.nombre;


-- ============================================================
-- 3. VALIDACIÓN: NO SE GASTA MÁS DE LO QUE HAY
--
-- Mismo patrón que validar_pago_no_excede_saldo en mayoristas.
-- El lock sobre la fila del proveedor serializa dos canjes
-- simultáneos del mismo saldo.
-- ============================================================
create or replace function validar_rebate()
returns trigger
language plpgsql
as $$
declare
  v_saldo numeric;
begin
  if new.tipo = 'canje' and new.compra_id is null then
    raise exception 'Un canje de rebate debe referenciar la compra que lo consume.';
  end if;

  if new.tipo <> 'canje' and new.compra_id is not null then
    raise exception 'Solo los canjes se asocian a una compra.';
  end if;

  if new.anulado = false and new.tipo in ('canje', 'vencimiento') then
    perform 1 from proveedores where id = new.proveedor_id for update;

    select coalesce(sum(
      case when tipo in ('acumulacion', 'ajuste') then monto else -monto end
    ), 0)
    into v_saldo
    from rebates_proveedor
    where proveedor_id = new.proveedor_id
      and anulado = false
      and id <> new.id;

    if new.monto > v_saldo then
      raise exception
        'El saldo de rebate del proveedor es % y se intentó descontar %.',
        v_saldo, new.monto;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_rebate on rebates_proveedor;

create trigger trg_validar_rebate
  before insert or update on rebates_proveedor
  for each row execute function validar_rebate();


-- ============================================================
-- 4. REGISTRAR_COMPRA: CANJE DE REBATE
-- Base: versión de 202607080000 (pago inicial de contado auditable).
-- Cambio: metodo_pago = 'rebate' descuenta el total del saldo a
-- favor del proveedor en vez de salir de la caja.
--
-- Un canje es siempre por el total de la compra. Una compra pagada
-- mitad rebate y mitad efectivo se registra como dos compras: así
-- cada una queda con un solo origen de fondos y los reportes de
-- caja no tienen que partir totales.
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
  -- a) Validar que p_items no esté vacío
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

  if p_metodo_pago = 'rebate' and p_proveedor_id is null then
    raise exception 'Un canje de rebate debe indicar el proveedor que lo otorga';
  end if;

  -- b) Insertar la fila en compras_inventario con total = 0 y capturar su id
  insert into compras_inventario (proveedor_id, fecha, metodo_pago, notas, total, ajuste, valor_deuda)
  values (p_proveedor_id, p_fecha, p_metodo_pago, p_notas, 0, coalesce(p_ajuste, 0), 0)
  returning id into v_compra_id;

  -- c) Para cada item en p_items:
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

    -- Validar que producto_id exista con FOR UPDATE
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
      and activo = true
    for update;

    if not found then
      raise exception 'Producto no existe o está inactivo: %', v_item.producto_id;
    end if;

    -- Insertar en detalle_compras
    insert into detalle_compras (compra_id, producto_id, cantidad, costo_unitario)
    values (v_compra_id, v_item.producto_id, v_item.cantidad, v_item.costo_unitario);

    -- Incrementar stock_actual del producto y actualizar a costo promedio ponderado
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

    -- Registrar en movimientos_stock (tipo='entrada', motivo='compra_inventario', referencia_id=compra_id)
    insert into movimientos_stock (
      producto_id,
      tipo,
      cantidad,
      stock_antes,
      stock_despues,
      motivo,
      referencia_id
    )
    values (
      v_item.producto_id,
      'entrada'::tipo_movimiento,
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'compra_inventario',
      v_compra_id
    );
  end loop;

  -- d) Calcular el total real (sum de subtotales de detalle_compras) y actualizar compras_inventario.total
  select coalesce(sum(subtotal), 0) into v_total_real
  from detalle_compras
  where compra_id = v_compra_id;

  v_total := v_total_real + coalesce(p_ajuste, 0);

  update compras_inventario
  set total = v_total
  where id = v_compra_id;

  -- e) Compras a crédito: la deuda arranca en el total y el pago
  --    inicial de contado (si lo hay) queda auditado en pagos_compras.
  if p_metodo_pago = 'credito' then
    if p_valor_deuda > v_total then
      raise exception 'El valor en deuda (%) no puede superar el total de la compra (%)', p_valor_deuda, v_total;
    end if;

    update compras_inventario
    set valor_deuda = v_total
    where id = v_compra_id;

    v_pago_inicial := v_total - p_valor_deuda;

    if v_pago_inicial > 0 then
      -- Compras retroactivas: el pago inicial conserva la fecha de la
      -- compra para no contaminar el corte de caja vigente.
      if p_fecha >= (now() at time zone 'America/Bogota')::date then
        v_fecha_pago := now();
      else
        v_fecha_pago := p_fecha::timestamp at time zone 'America/Bogota';
      end if;

      insert into pagos_compras (compra_id, monto, metodo_pago, fecha, notas)
      values (v_compra_id, v_pago_inicial, p_metodo_pago_contado, v_fecha_pago, 'Pago inicial de contado');
    end if;
  end if;

  -- f) Canje de rebate: consume el saldo a favor. El trigger de
  --    rebates_proveedor aborta la compra entera si no alcanza.
  if p_metodo_pago = 'rebate' then
    if v_total <= 0 then
      raise exception 'Un canje de rebate debe tener un total mayor a cero';
    end if;

    insert into rebates_proveedor (proveedor_id, fecha, tipo, monto, compra_id, notas)
    values (p_proveedor_id, p_fecha, 'canje', v_total, v_compra_id,
            'Canje en compra de inventario');
  end if;

  -- g) Retornar el id de la compra creada
  return v_compra_id;
end;
$$;


-- ============================================================
-- 5. ANULAR_COMPRA: DEVOLVER EL SALDO CANJEADO
-- Base: versión de 202607080000.
-- Cambio: si la compra consumió rebate, el canje se anula y el
-- saldo vuelve a estar disponible.
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
      producto_id,
      tipo,
      cantidad,
      stock_antes,
      stock_despues,
      motivo,
      referencia_id
    )
    values (
      v_item.producto_id,
      'salida'::tipo_movimiento,
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'anulacion_compra',
      p_compra_id
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

  -- El rebate canjeado vuelve al saldo del proveedor.
  update rebates_proveedor
  set anulado = true
  where compra_id = p_compra_id
    and anulado = false;
end;
$$;


-- ============================================================
-- 6. CALCULAR_DINERO_DISPONIBLE: EL CANJE NO TOCA LA CAJA
-- Base: versión de 202607140000.
-- Cambio: las compras pagadas con rebate se excluyen, igual que
-- las de crédito. Restarlas descontaría plata que nunca salió.
--
-- calcular_efectivo_real no necesita cambio: ya filtra por
-- metodo_pago = 'efectivo', así que 'rebate' queda fuera solo.
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
    -- Las compras a crédito se pagan por pagos_compras; las de
    -- rebate no se pagan con plata.
    --
    -- La comparación va sobre ::text a propósito: esta función es
    -- `language sql`, así que su cuerpo se valida al crearse, y un
    -- literal 'rebate' del enum no se puede usar en la misma
    -- transacción que lo agregó. Con el cast, esta migración corre
    -- igual así el CLI agrupe ambos archivos en una transacción.
    - coalesce((
        select sum(ci.total) from compras_inventario ci, corte
        where ci.anulado = false
          and ci.metodo_pago::text not in ('credito', 'rebate')
          and ci.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pc.monto) from pagos_compras pc, corte
        where pc.anulado = false and pc.fecha > corte.fecha_corte
      ), 0);
$$;


-- ============================================================
-- 7. RESUMEN_FINANCIERO_GENERAL: EL SALDO A FAVOR, APARTE
-- Base: versión de 202607140000.
--
-- saldo_rebates va FUERA de patrimonio_estimado: no es plata ni
-- mercancía todavía, y puede caducar sin usarse. El patrimonio
-- sube solo en el canje, cuando el inventario entra sin que baje
-- la caja — que es exactamente la utilidad del rebate.
--
-- total_compras_historico sí incluye los canjes: sigue siendo un
-- resumen de mercancía comprada, no de plata desembolsada (las
-- compras a crédito ya estaban ahí con el mismo criterio).
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
        where anulado = false and metodo_pago::text = 'credito'
      ), 0) as deuda_prov,
      -- Directo de la tabla, no de saldos_rebates_proveedor: esa
      -- vista solo lista proveedores activos y aquí interesa todo
      -- el saldo vivo.
      coalesce((
        select sum(case when tipo in ('acumulacion', 'ajuste') then monto else -monto end)
        from rebates_proveedor where anulado = false
      ), 0) as reb_saldo,
      coalesce((
        select sum(monto) from rebates_proveedor
        where anulado = false and tipo = 'canje'
      ), 0) as reb_canjeado,
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
    deuda_prov as deuda_proveedores,
    reb_saldo as saldo_rebates,
    reb_canjeado as total_rebates_canjeado
  from data;
