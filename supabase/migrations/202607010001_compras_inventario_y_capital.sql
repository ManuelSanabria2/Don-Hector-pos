-- ============================================================
-- 1. TABLA: PROVEEDORES
-- ============================================================
create table proveedores (
  id          uuid primary key default uuid_generate_v4(),
  nombre      text not null,
  telefono    text,
  notas       text,
  activo      boolean not null default true,
  created_at  timestamptz default now()
);

alter table proveedores enable row level security;

create policy "acceso_autenticado" on proveedores
  for all to authenticated using (true) with check (true);


-- ============================================================
-- 2. TABLA: COMPRAS_INVENTARIO
-- ============================================================
create table compras_inventario (
  id              uuid primary key default uuid_generate_v4(),
  proveedor_id    uuid references proveedores(id) on delete set null,
  fecha           date not null default current_date,
  total           numeric(12,3) not null default 0,
  metodo_pago     metodo_pago not null default 'efectivo',
  notas           text,
  anulado         boolean not null default false,
  created_at      timestamptz default now()
);

alter table compras_inventario enable row level security;

create policy "acceso_autenticado" on compras_inventario
  for all to authenticated using (true) with check (true);


-- ============================================================
-- 3. TABLA: DETALLE_COMPRAS
-- ============================================================
create table detalle_compras (
  id              uuid primary key default uuid_generate_v4(),
  compra_id       uuid not null references compras_inventario(id) on delete cascade,
  producto_id     uuid not null references productos(id) on delete restrict,
  cantidad        integer not null check (cantidad > 0),
  costo_unitario  numeric(12,3) not null check (costo_unitario >= 0),
  subtotal        numeric(12,3) generated always as (cantidad * costo_unitario) stored
);

alter table detalle_compras enable row level security;

create policy "acceso_autenticado" on detalle_compras
  for all to authenticated using (true) with check (true);


-- ============================================================
-- 4. FUNCIÓN RPC: REGISTRAR_COMPRA
-- ============================================================
create or replace function registrar_compra(
  p_proveedor_id  uuid,
  p_fecha         date,
  p_metodo_pago   metodo_pago,
  p_notas         text,
  p_items         jsonb
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
begin
  -- a) Validar que p_items no esté vacío
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra debe incluir al menos un producto';
  end if;

  -- b) Insertar la fila en compras_inventario con total = 0 y capturar su id
  insert into compras_inventario (proveedor_id, fecha, metodo_pago, notas, total)
  values (p_proveedor_id, p_fecha, p_metodo_pago, p_notas, 0)
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

    -- Incrementar stock_actual del producto y actualizar costo
    update productos
    set stock_actual = stock_actual + v_item.cantidad,
        costo = v_item.costo_unitario
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

  update compras_inventario
  set total = v_total_real
  where id = v_compra_id;

  -- e) Retornar el id de la compra creada
  return v_compra_id;
end;
$$;


-- ============================================================
-- 5. FUNCIÓN RPC: ANULAR_COMPRA
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
  -- a) Seleccionar la compra con FOR UPDATE; validar que exista y no esté anulada
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

  -- b) Para cada línea en detalle_compras:
  for v_item in
    select producto_id, cantidad
    from detalle_compras
    where compra_id = p_compra_id
  loop
    -- Bloquear producto con FOR UPDATE
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
    for update;

    if not found then
      raise exception 'Producto con ID % no encontrado.', v_item.producto_id;
    end if;

    -- Decrementar stock_actual y validar que no quede negativo
    if v_stock_antes < v_item.cantidad then
      raise exception 'Stock insuficiente para anular la compra';
    end if;

    update productos
    set stock_actual = stock_actual - v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    -- Registrar en movimientos_stock (tipo='salida', motivo='anulacion_compra')
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

  -- c) Marcar compras_inventario.anulado = true y agregar motivo a notas
  update compras_inventario
  set anulado = true,
      notas = coalesce(notas || ' | ', '') || 'ANULADA: ' || coalesce(p_motivo, 'sin motivo')
  where id = p_compra_id;
end;
$$;


-- ============================================================
-- 6. TABLA: CAPITAL_NEGOCIO
-- ============================================================
create table capital_negocio (
  id                       uuid primary key default uuid_generate_v4(),
  efectivo_inicial         numeric(12,3) not null default 0,
  valor_inventario_inicial numeric(12,3) not null default 0,
  notas                    text,
  fecha_registro           date not null default current_date,
  created_at               timestamptz default now()
);

create unique index capital_negocio_singleton on capital_negocio ((true));

alter table capital_negocio enable row level security;

create policy "acceso_autenticado" on capital_negocio
  for all to authenticated using (true) with check (true);


-- ============================================================
-- 7. VISTA: RESUMEN_FINANCIERO_GENERAL
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
      coalesce((select sum(stock_actual * costo) from productos), 0) as inv_act
  )
  select
    cap_ef_ini as capital_efectivo_inicial,
    cap_inv_ini as capital_inventario_inicial,
    v_tot as total_ventas_historico,
    c_tot as total_compras_historico,
    g_tot as total_gastos_historico,
    inv_act as valor_inventario_actual,
    (cap_ef_ini + cap_inv_ini + v_tot - c_tot - g_tot) as patrimonio_estimado
  from data;
