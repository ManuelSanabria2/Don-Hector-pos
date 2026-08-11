-- ============================================================
-- MIGRATION: 202607130000_prestamos
--
-- Préstamos que RECIBE el negocio (bancos, prestamistas).
--
-- Un préstamo es un PASIVO, no un ingreso. Es lo contrario de un
-- fiado: allá alguien le debe al negocio, aquí el negocio debe.
-- Sin un lugar propio, esa plata solo puede anotarse mal: como
-- venta (infla utilidad y margen) o las cuotas como gasto (hunde
-- la utilidad, cuando devolver plata prestada no empobrece al
-- negocio: cambia deuda por menos efectivo).
--
-- Regla que gobierna el diseño:
--
--   Movimiento          | Efectivo | Utilidad | Deuda
--   --------------------|----------|----------|-------
--   Recibe el préstamo  |   sube   |    --    | sube
--   Abona al capital    |   baja   |    --    | baja
--   Paga interés        |   baja   |   baja   |  --
--
-- El interés se registra como un gasto real (categoría
-- "Intereses de préstamos") creado por trigger, así que impacta
-- utilidad, gráficas de gastos, punto de equilibrio y patrimonio
-- sin tener que tocar ninguna de esas fórmulas.
--
-- Se sigue el molde de fiados (202607120000), no el de
-- pagos_compras: aquel resta a mano (valor_deuda = valor_deuda -
-- monto) y se descuadra si un pago se anula por fuera de
-- anular_compra. Aquí se recalcula desde los pagos vigentes.
-- ============================================================

-- ============================================================
-- 1. CATEGORÍA DE GASTO PARA LOS INTERESES
-- ============================================================
insert into categorias_gasto (nombre) values ('Intereses de préstamos')
on conflict (nombre) do nothing;

-- ============================================================
-- 2. TABLAS
-- ============================================================
create table if not exists prestamos (
  id             uuid primary key default uuid_generate_v4(),
  acreedor       text not null check (length(trim(acreedor)) > 0),
  tipo           text not null default 'prestamista'
                   check (tipo in ('banco','prestamista','familiar','otro')),
  monto          numeric(12,3) not null check (monto > 0),
  capital_pagado numeric(12,3) not null default 0,
  saldo          numeric(12,3) generated always as (monto - capital_pagado) stored,
  interes_pagado numeric(12,3) not null default 0,
  tasa_interes   numeric(6,3),
  metodo_pago    metodo_pago not null default 'efectivo',
  fecha          timestamptz not null default now(),
  estado         estado_cobro not null default 'pendiente',
  notas          text,
  anulado        boolean not null default false,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

create index if not exists prestamos_estado_idx on prestamos (anulado, estado);

drop trigger if exists prestamos_updated_at on prestamos;
create trigger prestamos_updated_at
  before update on prestamos
  for each row execute function set_updated_at();

-- Cada cuota separa lo que baja la deuda de lo que es costo del
-- crédito, para que una cuota real ("pagué 150.000, de los cuales
-- 30.000 son interés") se registre de una sola vez.
create table if not exists pagos_prestamos (
  id            uuid primary key default uuid_generate_v4(),
  prestamo_id   uuid not null references prestamos(id) on delete cascade,
  abono_capital numeric(12,3) not null default 0 check (abono_capital >= 0),
  interes       numeric(12,3) not null default 0 check (interes >= 0),
  monto         numeric(12,3) generated always as (abono_capital + interes) stored,
  metodo_pago   metodo_pago not null default 'efectivo',
  fecha         timestamptz not null default now(),
  notas         text,
  anulado       boolean not null default false,
  constraint pago_prestamo_no_vacio_chk check (abono_capital + interes > 0)
);

create index if not exists pagos_prestamos_prestamo_idx
  on pagos_prestamos (prestamo_id);

-- Enlace del gasto de interés con la cuota que lo generó.
alter table gastos add column if not exists pago_prestamo_id uuid
  references pagos_prestamos(id) on delete cascade;

-- Política igual a la del resto del esquema, con RLS deshabilitado:
-- es el estado real de todas las tablas del proyecto.
do $do$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'prestamos' and policyname = 'acceso_autenticado'
  ) then
    create policy "acceso_autenticado" on prestamos
      for all to authenticated using (true) with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'pagos_prestamos' and policyname = 'acceso_autenticado'
  ) then
    create policy "acceso_autenticado" on pagos_prestamos
      for all to authenticated using (true) with check (true);
  end if;
end;
$do$;

alter table prestamos       disable row level security;
alter table pagos_prestamos disable row level security;

-- ============================================================
-- 3. TRIGGERS DE AMORTIZACIÓN
-- ============================================================

-- BEFORE INSERT: bloquea la fila del préstamo para que dos cuotas
-- simultáneas no puedan pasarse del saldo entre ambas.
-- El interés no se valida contra el saldo: se puede pagar solo
-- interés sin abonar nada al capital.
create or replace function validar_pago_prestamo()
returns trigger as $$
declare
  v_saldo   numeric;
  v_anulado boolean;
begin
  select saldo, anulado into v_saldo, v_anulado
  from prestamos
  where id = new.prestamo_id
  for update;

  if not found then
    raise exception 'El préstamo especificado no existe.';
  end if;

  if v_anulado then
    raise exception 'No se puede registrar una cuota sobre un préstamo anulado.';
  end if;

  if new.abono_capital > v_saldo then
    raise exception 'El abono a capital (%) excede el saldo pendiente (%)',
      new.abono_capital, v_saldo;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists pago_prestamo_valido on pagos_prestamos;
create trigger pago_prestamo_valido
  before insert on pagos_prestamos
  for each row execute function validar_pago_prestamo();

-- AFTER INSERT OR UPDATE: recalcula desde las cuotas vigentes.
-- Disparar también en UPDATE es lo que permite anular una cuota
-- suelta sin descuadrar el saldo.
create or replace function actualizar_prestamo()
returns trigger as $$
declare
  v_prestamo_id    uuid;
  v_capital_pagado numeric;
  v_interes_pagado numeric;
  v_monto          numeric;
  v_estado         estado_cobro;
begin
  v_prestamo_id := coalesce(new.prestamo_id, old.prestamo_id);

  select coalesce(sum(abono_capital), 0), coalesce(sum(interes), 0)
    into v_capital_pagado, v_interes_pagado
  from pagos_prestamos
  where prestamo_id = v_prestamo_id
    and anulado = false;

  select monto into v_monto from prestamos where id = v_prestamo_id;

  if v_capital_pagado >= v_monto then
    v_estado := 'pagado';
  elsif v_capital_pagado > 0 then
    v_estado := 'parcial';
  else
    v_estado := 'pendiente';
  end if;

  update prestamos
  set capital_pagado = v_capital_pagado,
      interes_pagado = v_interes_pagado,
      estado         = v_estado
  where id = v_prestamo_id;

  return null;
end;
$$ language plpgsql;

drop trigger if exists pago_prestamo_aplicado on pagos_prestamos;
create trigger pago_prestamo_aplicado
  after insert or update on pagos_prestamos
  for each row execute function actualizar_prestamo();

-- ============================================================
-- 4. EL INTERÉS ES UN GASTO
--
-- Se crea la fila en gastos para que el interés aparezca solo en
-- utilidad, distribución de gastos, punto de equilibrio y
-- patrimonio. gastos sigue siendo la única fuente de verdad.
-- ============================================================
create or replace function registrar_gasto_interes()
returns trigger as $$
declare
  v_categoria_id uuid;
  v_acreedor     text;
begin
  if tg_op = 'INSERT' then
    if new.interes <= 0 then
      return null;
    end if;

    select id into v_categoria_id
    from categorias_gasto
    where nombre = 'Intereses de préstamos';

    select acreedor into v_acreedor from prestamos where id = new.prestamo_id;

    insert into gastos (
      descripcion, monto, categoria_id, fecha, metodo_pago, notas, pago_prestamo_id
    )
    values (
      'Interés préstamo - ' || coalesce(v_acreedor, 'sin acreedor'),
      new.interes,
      v_categoria_id,
      new.fecha::date,
      new.metodo_pago,
      'Registrado automáticamente al pagar una cuota del préstamo.',
      new.id
    );

    return null;
  end if;

  -- UPDATE: propagar la anulación al gasto enlazado.
  if new.anulado is distinct from old.anulado then
    update gastos
    set anulado = new.anulado
    where pago_prestamo_id = new.id;
  end if;

  return null;
end;
$$ language plpgsql;

drop trigger if exists pago_prestamo_gasto_interes on pagos_prestamos;
create trigger pago_prestamo_gasto_interes
  after insert or update on pagos_prestamos
  for each row execute function registrar_gasto_interes();

-- ============================================================
-- 5. calcular_efectivo_real: el préstamo entra y las cuotas salen
--
-- Se resta abono_capital, NO monto: la parte de interés ya sale de
-- la caja por el bloque de gastos (el gasto que crea el trigger).
-- Restar monto la contaría dos veces.
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
        select sum(v.total) from ventas v, corte
        where v.estado = 'completada' and v.tipo = 'publico'
          and v.metodo_pago = 'efectivo' and v.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(pm.monto) from pagos_mayoristas pm, corte
        where pm.anulado = false and pm.metodo_pago = 'efectivo'
          and pm.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(af.monto) from abonos_fiados af, corte
        where af.anulado = false and af.metodo_pago = 'efectivo'
          and af.fecha > corte.fecha_corte
      ), 0)
    + coalesce((
        select sum(pr.monto) from prestamos pr, corte
        where pr.anulado = false and pr.metodo_pago = 'efectivo'
          and pr.fecha > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pp.abono_capital) from pagos_prestamos pp, corte
        where pp.anulado = false and pp.metodo_pago = 'efectivo'
          and pp.fecha > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(g.monto) from gastos g, corte
        where g.anulado = false and g.metodo_pago = 'efectivo'
          and g.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(ci.total) from compras_inventario ci, corte
        where ci.anulado = false and ci.metodo_pago = 'efectivo'
          and ci.created_at > corte.fecha_corte
      ), 0)
    - coalesce((
        select sum(pc.monto) from pagos_compras pc, corte
        where pc.anulado = false and pc.metodo_pago = 'efectivo'
          and pc.fecha > corte.fecha_corte
      ), 0);
$$;

-- ============================================================
-- 6. resumen_financiero_general: exponer la deuda, no restarla
--
-- patrimonio_estimado se deja INTACTO a propósito. La fórmula no
-- tiene término de efectivo vivo y resta las compras de inventario
-- sin volver a sumar el inventario comprado. Ejemplo: pido 1M
-- prestado y compro mercancía por 1M; en la realidad el patrimonio
-- no cambia, pero la fórmula ya lo baja 1M por las compras. Si
-- además restara la deuda lo bajaría 2M. Restarla empeoraría el
-- número, así que la deuda se muestra como su propia fila.
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
      coalesce((select sum(interes_pagado) from prestamos where anulado = false), 0) as prest_interes
  )
  select
    cap_ef_ini as capital_efectivo_inicial,
    cap_inv_ini as capital_inventario_inicial,
    v_tot as total_ventas_historico,
    c_tot as total_compras_historico,
    g_tot as total_gastos_historico,
    inv_act as valor_inventario_actual,
    (cap_ef_ini + cap_inv_ini + v_tot - c_tot - g_tot) as patrimonio_estimado,
    -- Columnas nuevas al final: "create or replace view" no permite
    -- insertarlas en medio de las existentes.
    prest_deuda as deuda_prestamos,
    prest_interes as interes_prestamos_pagado
  from data;
