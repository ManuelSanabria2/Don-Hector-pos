-- ============================================================
-- MIGRATION: 202607080000_flujo_caja_y_pagos
-- Corrección integral del cálculo de "Efectivo Real":
--   1. Método de pago en gastos.
--   2. Pagos de deuda de compras auditables (tabla pagos_compras).
--   3. Fecha de corte en capital_negocio (recalibración de caja).
--   4. Anulación lógica de cobros/pagos de mayoristas (sin DELETE).
--   5. Abono automático en ventas mayoristas de contado.
--   6. Función única calcular_efectivo_real().
-- ============================================================

-- ============================================================
-- 1. GASTOS: MÉTODO DE PAGO
-- ============================================================
alter table gastos
  add column if not exists metodo_pago metodo_pago not null default 'efectivo';

-- ============================================================
-- 2. CAPITAL: FECHA DE CORTE
-- El efectivo_inicial representa el conteo físico de caja en
-- fecha_corte; el efectivo real acumula flujos desde ese instante.
-- ============================================================
alter table capital_negocio
  add column if not exists fecha_corte timestamptz not null default now();

-- ============================================================
-- 3. TABLA PAGOS_COMPRAS
-- Todo dinero pagado a proveedores por compras a crédito pasa
-- por aquí (incluido el pago inicial de contado).
-- ============================================================
create table if not exists pagos_compras (
  id          uuid primary key default uuid_generate_v4(),
  compra_id   uuid not null references compras_inventario(id) on delete cascade,
  monto       numeric(12,3) not null check (monto > 0),
  metodo_pago metodo_pago not null default 'efectivo',
  fecha       timestamptz not null default now(),
  notas       text,
  anulado     boolean not null default false
);

-- RLS deshabilitado, consistente con compras_inventario (ver 202607030000).
alter table pagos_compras disable row level security;

create or replace function validar_pago_compra()
returns trigger as $$
declare
  v_deuda   numeric;
  v_anulada boolean;
begin
  select valor_deuda, anulado into v_deuda, v_anulada
  from compras_inventario
  where id = new.compra_id
  for update;

  if not found then
    raise exception 'La compra especificada no existe.';
  end if;

  if v_anulada then
    raise exception 'No se puede registrar un pago sobre una compra anulada.';
  end if;

  if new.monto > v_deuda then
    raise exception 'El pago (%) excede la deuda pendiente (%)', new.monto, v_deuda;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists pago_compra_valida on pagos_compras;
create trigger pago_compra_valida
  before insert on pagos_compras
  for each row execute function validar_pago_compra();

create or replace function aplicar_pago_compra()
returns trigger as $$
begin
  update compras_inventario
  set valor_deuda = valor_deuda - new.monto
  where id = new.compra_id;
  return new;
end;
$$ language plpgsql;

drop trigger if exists pago_compra_aplicado on pagos_compras;
create trigger pago_compra_aplicado
  after insert on pagos_compras
  for each row execute function aplicar_pago_compra();

-- ============================================================
-- 4. ANULACIÓN LÓGICA DE COBROS Y PAGOS DE MAYORISTAS
-- ============================================================
alter table cobros_mayoristas
  add column if not exists anulado boolean not null default false;

alter table pagos_mayoristas
  add column if not exists anulado boolean not null default false;

-- El total pagado solo considera pagos vigentes.
create or replace function actualizar_cobro()
returns trigger as $$
declare
  v_total_pagado numeric;
  v_total_venta  numeric;
  v_estado       estado_cobro;
begin
  select coalesce(sum(monto), 0) into v_total_pagado
  from pagos_mayoristas
  where cobro_id = new.cobro_id
    and anulado = false;

  select total_venta into v_total_venta
  from cobros_mayoristas
  where id = new.cobro_id;

  if v_total_pagado >= v_total_venta then
    v_estado := 'pagado';
  elsif v_total_pagado > 0 then
    v_estado := 'parcial';
  else
    v_estado := 'pendiente';
  end if;

  update cobros_mayoristas
  set total_pagado = v_total_pagado,
      estado       = v_estado
  where id = new.cobro_id;

  return new;
end;
$$ language plpgsql;

-- Rechazar pagos sobre cobros anulados o que excedan el saldo.
create or replace function validar_pago_no_excede_saldo()
returns trigger as $$
declare
  v_saldo_actual numeric;
  v_anulado      boolean;
begin
  select saldo, anulado into v_saldo_actual, v_anulado
  from cobros_mayoristas
  where id = new.cobro_id;

  if v_anulado then
    raise exception 'No se puede registrar un pago sobre un cobro anulado.';
  end if;

  if new.monto > v_saldo_actual then
    raise exception 'El pago (%) excede el saldo pendiente (%)', new.monto, v_saldo_actual;
  end if;

  return new;
end;
$$ language plpgsql;

-- anular_venta: marcar cobro y pagos como anulados en vez de borrarlos.
-- Semántica: al anular la venta, el dinero abonado se devuelve al cliente.
create or replace function anular_venta(p_venta_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
as $$
declare
  v_item record;
  v_stock_antes integer;
  v_stock_despues integer;
  v_estado_actual estado_venta;
begin
  select estado into v_estado_actual from ventas where id = p_venta_id for update;

  if v_estado_actual is null then
    raise exception 'La venta especificada no existe.';
  end if;
  if v_estado_actual = 'anulada' then
    raise exception 'La venta ya está anulada.';
  end if;

  for v_item in
    select producto_id, cantidad from detalle_ventas where venta_id = p_venta_id
  loop
    select stock_actual into v_stock_antes from productos where id = v_item.producto_id for update;

    update productos
    set stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    insert into movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id)
    values (v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad, v_stock_antes, v_stock_despues, 'anulacion_venta', p_venta_id);
  end loop;

  update ventas
  set estado = 'anulada',
      notas = coalesce(notas || ' | ', '') || 'ANULADA: ' || coalesce(p_motivo, 'sin motivo')
  where id = p_venta_id;

  -- Anulación lógica del cobro y sus abonos (dinero devuelto al cliente).
  update pagos_mayoristas
  set anulado = true
  where anulado = false
    and cobro_id in (select id from cobros_mayoristas where venta_id = p_venta_id);

  update cobros_mayoristas
  set anulado = true
  where venta_id = p_venta_id;
end;
$$;

-- La vista de estado de cuenta ignora cobros anulados.
create or replace view estado_cuenta_mayoristas
with (security_invoker = true) as
  select
    cm.id,
    cm.nombre,
    cm.telefono,
    count(c.id) as num_pedidos,
    coalesce(sum(c.total_venta), 0) as total_compras,
    coalesce(sum(c.total_pagado), 0) as total_pagado,
    coalesce(sum(c.saldo), 0) as deuda_pendiente
  from clientes_mayoristas cm
  left join cobros_mayoristas c
    on c.cliente_id = cm.id
   and c.anulado = false
  where cm.activo = true
  group by cm.id, cm.nombre, cm.telefono
  order by deuda_pendiente desc;

-- ============================================================
-- 5. REGISTRAR_VENTA: ABONO AUTOMÁTICO EN MAYORISTA DE CONTADO
-- Base: versión de 202607010002 (costo histórico). Cambios:
--   - 'credito' solo válido para ventas mayoristas.
--   - Venta mayorista con método distinto de 'credito' queda
--     pagada al instante (cobro + pago automático).
-- ============================================================
create or replace function registrar_venta(
  p_tipo          tipo_venta,
  p_cliente_id    uuid,
  p_metodo_pago   metodo_pago,
  p_descuento     numeric,
  p_notas         text,
  p_items         jsonb   -- [{producto_id, cantidad, precio_unitario}]
)
returns uuid
language plpgsql
as $$
declare
  v_venta_id      uuid;
  v_cobro_id      uuid;
  v_subtotal      numeric := 0;
  v_total         numeric;
  v_descuento     numeric := coalesce(p_descuento, 0);
  v_item          record;
  v_stock_antes   integer;
  v_stock_despues integer;
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta debe incluir al menos un producto';
  end if;

  if v_descuento < 0 then
    raise exception 'El descuento no puede ser negativo';
  end if;

  if p_tipo = 'mayorista' and p_cliente_id is null then
    raise exception 'Las ventas mayoristas requieren cliente_id';
  end if;

  if p_tipo = 'publico' and p_metodo_pago = 'credito' then
    raise exception 'Las ventas al público no pueden ser a crédito';
  end if;

  -- Validar líneas y calcular subtotal desde datos tipados.
  for v_item in
    select *
    from jsonb_to_recordset(p_items) as x(
      producto_id uuid,
      cantidad integer,
      precio_unitario numeric
    )
  loop
    if v_item.producto_id is null then
      raise exception 'Cada ítem debe incluir producto_id';
    end if;

    if v_item.cantidad is null or v_item.cantidad <= 0 then
      raise exception 'Cantidad inválida para producto %', v_item.producto_id;
    end if;

    if v_item.precio_unitario is null or v_item.precio_unitario < 0 then
      raise exception 'Precio inválido para producto %', v_item.producto_id;
    end if;

    v_subtotal := v_subtotal + v_item.cantidad * v_item.precio_unitario;
  end loop;

  v_total := v_subtotal - v_descuento;

  if v_total < 0 then
    raise exception 'El descuento no puede superar el subtotal';
  end if;

  -- Bloquear productos en orden estable para evitar sobreventa y reducir deadlocks.
  for v_item in
    select producto_id, sum(cantidad)::integer as cantidad
    from jsonb_to_recordset(p_items) as x(
      producto_id uuid,
      cantidad integer,
      precio_unitario numeric
    )
    group by producto_id
    order by producto_id
  loop
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
      and activo = true
    for update;

    if not found then
      raise exception 'Producto no existe o está inactivo: %', v_item.producto_id;
    end if;

    if v_stock_antes < v_item.cantidad then
      raise exception 'Stock insuficiente para producto %', v_item.producto_id;
    end if;
  end loop;

  -- Insertar cabecera de venta.
  insert into ventas (tipo, cliente_id, subtotal, descuento, total, metodo_pago, notas)
  values (p_tipo, p_cliente_id, v_subtotal, v_descuento, v_total, p_metodo_pago, p_notas)
  returning id into v_venta_id;

  -- Insertar detalles de venta incluyendo el costo histórico
  insert into detalle_ventas (venta_id, producto_id, cantidad, precio_unitario, costo_unitario_historico)
  select
    v_venta_id,
    producto_id,
    cantidad,
    precio_unitario,
    (select costo from productos where id = producto_id)
  from jsonb_to_recordset(p_items) as x(
    producto_id uuid,
    cantidad integer,
    precio_unitario numeric
  );

  -- Descontar stock e insertar auditoría.
  for v_item in
    select producto_id, sum(cantidad)::integer as cantidad
    from jsonb_to_recordset(p_items) as x(
      producto_id uuid,
      cantidad integer,
      precio_unitario numeric
    )
    group by producto_id
    order by producto_id
  loop
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id;

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
      'salida',
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'venta',
      v_venta_id
    );
  end loop;

  -- Toda venta mayorista genera cobro; si no es a crédito, queda
  -- pagada al instante con un abono automático por el total.
  if p_tipo = 'mayorista' then
    insert into cobros_mayoristas (venta_id, cliente_id, total_venta)
    values (v_venta_id, p_cliente_id, v_total)
    returning id into v_cobro_id;

    if p_metodo_pago <> 'credito' and v_total > 0 then
      insert into pagos_mayoristas (cobro_id, monto, metodo_pago, notas)
      values (v_cobro_id, v_total, p_metodo_pago, 'Pago inmediato (venta de contado)');
    end if;
  end if;

  return v_venta_id;
end;
$$;

-- ============================================================
-- 6. REGISTRAR_COMPRA: PAGO INICIAL DE CONTADO AUDITABLE
-- Base: versión de 202607060000 (costo promedio ponderado).
-- Cambios:
--   - Nuevo parámetro p_metodo_pago_contado (método de la parte
--     pagada de contado en compras a crédito).
--   - Compras a crédito: valor_deuda arranca en el total y el
--     pago inicial se registra en pagos_compras (el trigger deja
--     valor_deuda = p_valor_deuda).
-- Se eliminan las sobrecargas viejas para evitar ambigüedad en
-- las llamadas RPC de PostgREST.
-- ============================================================
drop function if exists registrar_compra(uuid, date, metodo_pago, text, jsonb);
drop function if exists registrar_compra(uuid, date, metodo_pago, text, jsonb, numeric);
drop function if exists registrar_compra(uuid, date, metodo_pago, text, jsonb, numeric, numeric);

create function registrar_compra(
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

  -- f) Retornar el id de la compra creada
  return v_compra_id;
end;
$$;

-- Al anular una compra, sus pagos quedan anulados (dinero devuelto).
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
end;
$$;

-- ============================================================
-- 7. CALCULAR_EFECTIVO_REAL
-- Fuente única del indicador: efectivo contado en fecha_corte
-- más/menos todos los flujos de efectivo posteriores.
-- Columnas timestamptz se comparan contra el corte exacto;
-- columnas date contra el día local del corte.
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
      ) as fecha_corte,
      coalesce(
        (select (coalesce(fecha_corte, created_at) at time zone 'America/Bogota')::date
         from capital_negocio limit 1),
        '-infinity'::date
      ) as fecha_corte_dia
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
          and g.fecha >= corte.fecha_corte_dia
      ), 0)
    - coalesce((
        select sum(ci.total)
        from compras_inventario ci, corte
        where ci.anulado = false
          and ci.metodo_pago = 'efectivo'
          and ci.fecha >= corte.fecha_corte_dia
      ), 0)
    - coalesce((
        select sum(pc.monto)
        from pagos_compras pc, corte
        where pc.anulado = false
          and pc.metodo_pago = 'efectivo'
          and pc.fecha > corte.fecha_corte
      ), 0);
$$;
