-- ============================================================
-- 1. EXTENSIONES
-- ============================================================
create extension if not exists "uuid-ossp";


-- ============================================================
-- 2. CATEGORÍAS DE PRODUCTOS
-- ============================================================
create table categorias (
  id        uuid primary key default uuid_generate_v4(),
  nombre    text not null unique,
  created_at timestamptz default now()
);

insert into categorias (nombre) values
  ('Aguardiente'),
  ('Ron'),
  ('Whisky'),
  ('Vodka'),
  ('Cerveza'),
  ('Vino'),
  ('Brandy'),
  ('Tequila'),
  ('Otros');


-- ============================================================
-- 3. PRODUCTOS
-- ============================================================
create table productos (
  id               uuid primary key default uuid_generate_v4(),
  nombre           text not null,
  categoria_id     uuid references categorias(id) on delete set null,
  descripcion      text,
  precio_publico   numeric(12, 2) not null default 0,
  precio_mayorista numeric(12, 2) not null default 0,
  costo            numeric(12, 2) not null default 0,   -- precio de compra
  stock_actual     integer not null default 0,
  stock_minimo     integer not null default 5,           -- umbral de alerta
  unidad           text default 'unidad',                -- unidad, caja, botella
  imagen_url       text,
  codigo_barras    text unique,
  activo           boolean default true,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  constraint productos_precios_no_negativos_chk
    check (precio_publico >= 0 and precio_mayorista >= 0 and costo >= 0),
  constraint productos_stock_no_negativo_chk
    check (stock_actual >= 0 and stock_minimo >= 0)
);

-- Trigger: actualizar updated_at automáticamente
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger productos_updated_at
  before update on productos
  for each row execute function set_updated_at();

-- Vista: productos con stock bajo
create view productos_stock_bajo
with (security_invoker = true) as
  select
    p.id,
    p.nombre,
    c.nombre as categoria,
    p.stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock_actual) as unidades_faltantes
  from productos p
  left join categorias c on c.id = p.categoria_id
  where p.stock_actual < p.stock_minimo
    and p.activo = true;


-- ============================================================
-- 4. CLIENTES MAYORISTAS
-- ============================================================
create table clientes_mayoristas (
  id           uuid primary key default uuid_generate_v4(),
  nombre       text not null,
  nit          text,
  telefono     text,
  direccion    text,
  email        text,
  notas        text,
  activo       boolean default true,
  created_at   timestamptz default now()
);


-- ============================================================
-- 5. VENTAS
-- ============================================================
create type tipo_venta as enum ('publico', 'mayorista');
create type metodo_pago as enum ('efectivo', 'nequi', 'daviplata', 'transferencia', 'otro');
create type estado_venta as enum ('completada', 'anulada');

create table ventas (
  id              uuid primary key default uuid_generate_v4(),
  tipo            tipo_venta not null default 'publico',
  cliente_id      uuid references clientes_mayoristas(id) on delete set null,
  fecha           timestamptz default now(),
  subtotal        numeric(12, 2) not null default 0,
  descuento       numeric(12, 2) not null default 0,
  total           numeric(12, 2) not null default 0,
  metodo_pago     metodo_pago not null default 'efectivo',
  estado          estado_venta not null default 'completada',
  notas           text,
  created_at      timestamptz default now(),
  constraint ventas_montos_no_negativos_chk
    check (subtotal >= 0 and descuento >= 0 and total >= 0),
  constraint ventas_mayorista_cliente_chk
    check (tipo <> 'mayorista' or cliente_id is not null)
);

create table detalle_ventas (
  id              uuid primary key default uuid_generate_v4(),
  venta_id        uuid not null references ventas(id) on delete cascade,
  producto_id     uuid not null references productos(id) on delete restrict,
  cantidad        integer not null check (cantidad > 0),
  precio_unitario numeric(12, 2) not null check (precio_unitario >= 0),
  subtotal        numeric(12, 2) generated always as (cantidad * precio_unitario) stored,
  created_at      timestamptz default now()
);

-- ============================================================
-- 6. CUENTAS POR COBRAR — MAYORISTAS
-- ============================================================
create type estado_cobro as enum ('pendiente', 'parcial', 'pagado');

create table cobros_mayoristas (
  id           uuid primary key default uuid_generate_v4(),
  venta_id     uuid not null references ventas(id) on delete cascade,
  cliente_id   uuid not null references clientes_mayoristas(id) on delete cascade,
  total_venta  numeric(12, 2) not null,
  total_pagado numeric(12, 2) not null default 0,
  saldo        numeric(12, 2) generated always as (total_venta - total_pagado) stored,
  estado       estado_cobro not null default 'pendiente',
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create trigger cobros_updated_at
  before update on cobros_mayoristas
  for each row execute function set_updated_at();

create table pagos_mayoristas (
  id          uuid primary key default uuid_generate_v4(),
  cobro_id    uuid not null references cobros_mayoristas(id) on delete cascade,
  monto       numeric(12, 2) not null check (monto > 0),
  metodo_pago metodo_pago not null default 'efectivo',
  fecha       timestamptz default now(),
  notas       text
);

-- Trigger: actualizar total_pagado y estado al registrar un pago
create or replace function actualizar_cobro()
returns trigger as $$
declare
  v_total_pagado numeric;
  v_total_venta  numeric;
  v_estado       estado_cobro;
begin
  select sum(monto) into v_total_pagado
  from pagos_mayoristas
  where cobro_id = new.cobro_id;

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

create trigger pago_registrado
  after insert on pagos_mayoristas
  for each row execute function actualizar_cobro();


-- ============================================================
-- 7. GASTOS PERSONALES
-- ============================================================
create table categorias_gasto (
  id     uuid primary key default uuid_generate_v4(),
  nombre text not null unique
);

insert into categorias_gasto (nombre) values
  ('Transporte'),
  ('Servicios (luz, agua, internet)'),
  ('Personal / Nómina'),
  ('Suministros y empaques'),
  ('Arriendo'),
  ('Mantenimiento'),
  ('Otros');

create table gastos (
  id           uuid primary key default uuid_generate_v4(),
  descripcion  text not null,
  monto        numeric(12, 2) not null check (monto > 0),
  categoria_id uuid references categorias_gasto(id) on delete set null,
  fecha        date not null default current_date,
  notas        text,
  created_at   timestamptz default now()
);


-- ============================================================
-- 8. MOVIMIENTOS DE STOCK (auditoría)
-- ============================================================
create type tipo_movimiento as enum ('entrada', 'salida', 'ajuste');

create table movimientos_stock (
  id           uuid primary key default uuid_generate_v4(),
  producto_id  uuid not null references productos(id) on delete cascade,
  tipo         tipo_movimiento not null,
  cantidad     integer not null,
  stock_antes  integer not null,
  stock_despues integer not null,
  motivo       text,            -- 'venta', 'compra', 'ajuste manual'
  referencia_id uuid,           -- id de la venta o compra relacionada
  created_at   timestamptz default now()
);


-- ============================================================
-- 9. RPC — REGISTRAR VENTA (atómica)
-- Descuenta stock, registra auditoría y crea cobro mayorista.
-- Llamar desde Flutter: supabase.rpc('registrar_venta', params: {...})
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

  -- Insertar detalles de venta.
  insert into detalle_ventas (venta_id, producto_id, cantidad, precio_unitario)
  select
    v_venta_id,
    producto_id,
    cantidad,
    precio_unitario
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

  -- Las ventas mayoristas quedan automáticamente como cuenta por cobrar.
  if p_tipo = 'mayorista' then
    insert into cobros_mayoristas (venta_id, cliente_id, total_venta)
    values (v_venta_id, p_cliente_id, v_total);
  end if;

  return v_venta_id;
end;
$$;


-- ============================================================
-- 10. VISTAS DE REPORTES
-- ============================================================

-- Resumen de ventas por día
create view resumen_ventas_dia
with (security_invoker = true) as
  select
    date_trunc('day', fecha) as dia,
    count(*) as num_ventas,
    sum(total) as total_ventas,
    sum(case when tipo = 'publico' then total else 0 end) as ventas_publico,
    sum(case when tipo = 'mayorista' then total else 0 end) as ventas_mayorista
  from ventas
  where estado = 'completada'
  group by 1
  order by 1 desc;

-- Productos más vendidos
create view productos_mas_vendidos
with (security_invoker = true) as
  select
    p.id,
    p.nombre,
    c.nombre as categoria,
    sum(dv.cantidad) as unidades_vendidas,
    sum(dv.subtotal) as ingresos_totales
  from detalle_ventas dv
  join productos p on p.id = dv.producto_id
  join ventas v on v.id = dv.venta_id
  left join categorias c on c.id = p.categoria_id
  where v.estado = 'completada'
  group by p.id, p.nombre, c.nombre
  order by unidades_vendidas desc;

-- Estado de cuenta mayoristas
create view estado_cuenta_mayoristas
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
  left join cobros_mayoristas c on c.cliente_id = cm.id
  where cm.activo = true
  group by cm.id, cm.nombre, cm.telefono
  order by deuda_pendiente desc;


-- ============================================================
-- 11. ROW LEVEL SECURITY (RLS)
-- Activar después de configurar Auth en Supabase.
-- Para un solo usuario, lo más simple es permitir solo
-- al usuario autenticado (el dueño del negocio).
-- ============================================================
alter table categorias           enable row level security;
alter table productos             enable row level security;
alter table ventas                enable row level security;
alter table detalle_ventas        enable row level security;
alter table clientes_mayoristas   enable row level security;
alter table cobros_mayoristas     enable row level security;
alter table pagos_mayoristas      enable row level security;
alter table categorias_gasto      enable row level security;
alter table gastos                enable row level security;
alter table movimientos_stock     enable row level security;

-- Política: solo usuarios autenticados tienen acceso total
-- (ajustar si en el futuro se agregan más roles)
do $$
declare
  t text;
begin
  foreach t in array array[
    'categorias','productos','ventas','detalle_ventas',
    'clientes_mayoristas','cobros_mayoristas','pagos_mayoristas',
    'categorias_gasto','gastos','movimientos_stock'
  ]
  loop
    execute format(
      'create policy "acceso_autenticado" on %I
       for all to authenticated using (true) with check (true);', t
    );
  end loop;
end;
$$;
