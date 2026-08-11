-- ============================================================
-- MIGRATION: 202607120000_fiados_publico
--
-- Fiados: deudas informales de ventas al público.
--
-- Hasta ahora registrar_venta rechazaba explícitamente las ventas
-- al público a crédito ('Las ventas al público no pueden ser a
-- crédito'), así que fiarle a alguien del barrio no se podía
-- registrar: o la venta no se anotaba (y el inventario quedaba
-- descuadrado) o se anotaba como pagada en efectivo (y el
-- Efectivo Real quedaba inflado con plata que no está en caja).
--
-- El deudor se identifica solo con un nombre escrito a mano: no
-- hay ficha de cliente. El panel agrupa por nombre normalizado
-- (lower(trim(...))) para poder sumar la deuda total de alguien.
--
-- Se espeja el modelo de cobros_mayoristas/pagos_mayoristas
-- (202607080000) corrigiendo dos huecos conocidos de ese modelo:
--   1. la validación de saldo no bloqueaba la fila (carrera entre
--      dos abonos simultáneos);
--   2. el recálculo de total_pagado solo disparaba en INSERT, así
--      que anular un abono suelto dejaba el cobro descuadrado.
-- ============================================================

-- ============================================================
-- 1. TABLAS
-- ============================================================
create table if not exists fiados_publico (
  id              uuid primary key default uuid_generate_v4(),
  venta_id        uuid not null unique references ventas(id) on delete cascade,
  deudor_nombre   text not null check (length(trim(deudor_nombre)) > 0),
  deudor_telefono text,
  total_venta     numeric(12,3) not null,
  total_pagado    numeric(12,3) not null default 0,
  saldo           numeric(12,3) generated always as (total_venta - total_pagado) stored,
  estado          estado_cobro not null default 'pendiente',
  anulado         boolean not null default false,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- El panel agrupa por nombre normalizado; el índice acompaña esa consulta.
create index if not exists fiados_publico_deudor_idx
  on fiados_publico (lower(trim(deudor_nombre)));

create index if not exists fiados_publico_venta_idx
  on fiados_publico (venta_id);

drop trigger if exists fiados_updated_at on fiados_publico;
create trigger fiados_updated_at
  before update on fiados_publico
  for each row execute function set_updated_at();

create table if not exists abonos_fiados (
  id          uuid primary key default uuid_generate_v4(),
  fiado_id    uuid not null references fiados_publico(id) on delete cascade,
  monto       numeric(12,3) not null check (monto > 0),
  metodo_pago metodo_pago not null default 'efectivo',
  fecha       timestamptz default now(),
  notas       text,
  anulado     boolean not null default false
);

create index if not exists abonos_fiados_fiado_idx
  on abonos_fiados (fiado_id);

-- Política igual a la del resto del esquema, pero con RLS deshabilitado:
-- es el estado real de todas las tablas del proyecto (ventas,
-- cobros_mayoristas, etc.), no una excepción de estas dos.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'fiados_publico' and policyname = 'acceso_autenticado'
  ) then
    create policy "acceso_autenticado" on fiados_publico
      for all to authenticated using (true) with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'abonos_fiados' and policyname = 'acceso_autenticado'
  ) then
    create policy "acceso_autenticado" on abonos_fiados
      for all to authenticated using (true) with check (true);
  end if;
end;
$$;

alter table fiados_publico disable row level security;
alter table abonos_fiados  disable row level security;

-- ============================================================
-- 2. TRIGGERS DE ABONOS
-- ============================================================

-- BEFORE INSERT: rechaza abonos sobre fiados anulados o que
-- excedan el saldo. A diferencia de validar_pago_no_excede_saldo,
-- bloquea la fila del fiado (for update) para que dos abonos
-- simultáneos no puedan sobrepasar el saldo entre ambos.
create or replace function validar_abono_fiado()
returns trigger as $$
declare
  v_saldo_actual numeric;
  v_anulado      boolean;
begin
  select saldo, anulado into v_saldo_actual, v_anulado
  from fiados_publico
  where id = new.fiado_id
  for update;

  if not found then
    raise exception 'El fiado especificado no existe.';
  end if;

  if v_anulado then
    raise exception 'No se puede registrar un abono sobre un fiado anulado.';
  end if;

  if new.monto > v_saldo_actual then
    raise exception 'El abono (%) excede el saldo pendiente (%)', new.monto, v_saldo_actual;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists abono_no_excede_saldo on abonos_fiados;
create trigger abono_no_excede_saldo
  before insert on abonos_fiados
  for each row execute function validar_abono_fiado();

-- AFTER INSERT OR UPDATE: recalcula total_pagado y estado contando
-- solo abonos vigentes. Dispara también en UPDATE para que anular
-- un abono suelto deje el fiado cuadrado.
create or replace function actualizar_fiado()
returns trigger as $$
declare
  v_fiado_id     uuid;
  v_total_pagado numeric;
  v_total_venta  numeric;
  v_estado       estado_cobro;
begin
  v_fiado_id := coalesce(new.fiado_id, old.fiado_id);

  select coalesce(sum(monto), 0) into v_total_pagado
  from abonos_fiados
  where fiado_id = v_fiado_id
    and anulado = false;

  select total_venta into v_total_venta
  from fiados_publico
  where id = v_fiado_id;

  if v_total_pagado >= v_total_venta then
    v_estado := 'pagado';
  elsif v_total_pagado > 0 then
    v_estado := 'parcial';
  else
    v_estado := 'pendiente';
  end if;

  update fiados_publico
  set total_pagado = v_total_pagado,
      estado       = v_estado
  where id = v_fiado_id;

  return null;
end;
$$ language plpgsql;

drop trigger if exists abono_registrado on abonos_fiados;
create trigger abono_registrado
  after insert or update on abonos_fiados
  for each row execute function actualizar_fiado();

-- ============================================================
-- 3. registrar_venta: permitir fiado al público
--
-- La firma cambia (7º parámetro p_deudor_nombre). Un
-- "create or replace" con un parámetro extra crearía una
-- SOBRECARGA y dejaría ambigua toda llamada de 6 argumentos, así
-- que hay que borrar la versión anterior primero.
-- ============================================================
drop function if exists registrar_venta(tipo_venta, uuid, metodo_pago, numeric, text, jsonb);

create or replace function registrar_venta(
  p_tipo          tipo_venta,
  p_cliente_id    uuid,
  p_metodo_pago   metodo_pago,
  p_descuento     numeric,
  p_notas         text,
  p_items         jsonb,  -- [{producto_id, cantidad, precio_unitario}]
  p_deudor_nombre text default null
)
returns uuid
language plpgsql
as $$
declare
  v_venta_id      uuid;
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

  -- Una venta al público a crédito es un fiado: se permite, pero
  -- exige saber a quién se le fió.
  if p_tipo = 'publico' and p_metodo_pago = 'credito'
     and (p_deudor_nombre is null or length(trim(p_deudor_nombre)) = 0) then
    raise exception 'Un fiado al público requiere el nombre de quien queda debiendo';
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

  -- Toda venta mayorista queda como cuenta por cobrar pendiente,
  -- sin importar el método de pago. El cobro se registra aparte,
  -- manualmente, cuando el cliente efectivamente paga.
  if p_tipo = 'mayorista' then
    insert into cobros_mayoristas (venta_id, cliente_id, total_venta)
    values (v_venta_id, p_cliente_id, v_total);
  end if;

  -- Venta al público a crédito: queda como fiado pendiente.
  if p_tipo = 'publico' and p_metodo_pago = 'credito' then
    insert into fiados_publico (venta_id, deudor_nombre, total_venta)
    values (v_venta_id, trim(p_deudor_nombre), v_total);
  end if;

  return v_venta_id;
end;
$$;

-- ============================================================
-- 4. anular_venta: anular también el fiado y sus abonos
-- ============================================================
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

  -- Anulación lógica del cobro mayorista y sus abonos (dinero devuelto al cliente).
  update pagos_mayoristas
  set anulado = true
  where anulado = false
    and cobro_id in (select id from cobros_mayoristas where venta_id = p_venta_id);

  update cobros_mayoristas
  set anulado = true
  where venta_id = p_venta_id;

  -- Mismo criterio para el fiado al público: lo abonado se devuelve.
  update abonos_fiados
  set anulado = true
  where anulado = false
    and fiado_id in (select id from fiados_publico where venta_id = p_venta_id);

  update fiados_publico
  set anulado = true
  where venta_id = p_venta_id;
end;
$$;

-- ============================================================
-- 5. registrar_abono_fiado: abono repartido FIFO, atómico
--
-- Reparte el abono entre las deudas pendientes de esa persona, de
-- la más antigua a la más nueva, dentro de UNA transacción. El
-- equivalente de mayoristas hace este reparto desde Dart con N
-- inserts sueltos: si el tercero falla, los dos primeros quedan
-- aplicados y el sobrante se descarta en silencio.
-- ============================================================
create or replace function registrar_abono_fiado(
  p_deudor_nombre text,
  p_monto         numeric,
  p_metodo_pago   metodo_pago default 'efectivo',
  p_notas         text default null
)
returns void
language plpgsql
as $$
declare
  v_clave     text;
  v_restante  numeric;
  v_deuda     numeric;
  v_abono     numeric;
  v_fiado     record;
begin
  if p_deudor_nombre is null or length(trim(p_deudor_nombre)) = 0 then
    raise exception 'Se requiere el nombre del deudor';
  end if;

  if p_monto is null or p_monto <= 0 then
    raise exception 'El abono debe ser mayor que cero';
  end if;

  v_clave := lower(trim(p_deudor_nombre));

  select coalesce(sum(saldo), 0) into v_deuda
  from fiados_publico
  where anulado = false
    and estado <> 'pagado'
    and lower(trim(deudor_nombre)) = v_clave;

  if v_deuda <= 0 then
    raise exception 'No hay deuda pendiente a nombre de %', trim(p_deudor_nombre);
  end if;

  if p_monto > v_deuda then
    raise exception 'El abono (%) excede la deuda total de % (%)',
      p_monto, trim(p_deudor_nombre), v_deuda;
  end if;

  v_restante := p_monto;

  for v_fiado in
    select id, saldo
    from fiados_publico
    where anulado = false
      and estado <> 'pagado'
      and saldo > 0
      and lower(trim(deudor_nombre)) = v_clave
    order by created_at, id
    for update
  loop
    exit when v_restante <= 0;

    v_abono := least(v_restante, v_fiado.saldo);

    insert into abonos_fiados (fiado_id, monto, metodo_pago, notas)
    values (v_fiado.id, v_abono, p_metodo_pago, p_notas);

    v_restante := v_restante - v_abono;
  end loop;

  if v_restante > 0 then
    raise exception 'No se pudo aplicar todo el abono; quedaron % sin asignar', v_restante;
  end if;
end;
$$;

-- ============================================================
-- 6. calcular_efectivo_real: contar los abonos de fiados
--
-- La venta fiada nunca suma efectivo (el filtro metodo_pago =
-- 'efectivo' ya la excluye); el dinero entra a caja cuando se
-- abona, igual que con los mayoristas.
-- ============================================================
create or replace function calcular_efectivo_real()
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
    + coalesce((
        select sum(af.monto)
        from abonos_fiados af, corte
        where af.anulado = false
          and af.metodo_pago = 'efectivo'
          and af.fecha > corte.fecha_corte
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

-- ============================================================
-- 7. Vista de estado de cuenta, agrupada por deudor
-- ============================================================
create or replace view estado_cuenta_fiados
with (security_invoker = true) as
  select
    lower(trim(deudor_nombre))  as deudor_clave,
    min(deudor_nombre)          as deudor_nombre,
    max(deudor_telefono)        as deudor_telefono,
    count(*)                    as num_ventas,
    coalesce(sum(total_venta), 0)  as total_fiado,
    coalesce(sum(total_pagado), 0) as total_pagado,
    coalesce(sum(saldo), 0)        as deuda_pendiente,
    max(created_at)             as ultima_venta
  from fiados_publico
  where anulado = false
  group by lower(trim(deudor_nombre))
  order by deuda_pendiente desc;
