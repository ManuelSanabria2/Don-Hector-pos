-- ============================================================
-- MIGRATION: 202607090001_menu_turbo_edicion
-- El menú del Turbo POS pasa de un filtro de nombres hardcodeado
-- en la app a ser configurable por el usuario:
--   1. Columnas en_turbo / orden_turbo en productos.
--   2. Seed que replica el filtro hardcodeado actual para que el
--      menú no cambie tras la migración (orden inicial alfabético).
--   3. RPC set_producto_turbo: agregar/quitar del menú con
--      asignación atómica de orden (max + 1).
--   4. RPC actualizar_orden_turbo: persistir el reorden manual
--      (drag-and-drop) en batch atómico.
-- ============================================================

-- 1. Columnas
alter table productos
  add column if not exists en_turbo boolean not null default false,
  add column if not exists orden_turbo integer;

create index if not exists idx_productos_turbo
  on productos (orden_turbo) where en_turbo;

-- 2. Seed: replicar el filtro hardcodeado de pos_providers.dart
update productos set en_turbo = true
where coalesce(activo, false) = true and (
     lower(trim(nombre)) = 'agua'
  or nombre ilike '%gatorade%'
  or nombre ilike '%budweiser%'
  or nombre ilike '%electrolit%'
  or nombre ilike '%coronita%'
  or nombre ilike '%master%'
  or nombre ilike '%deluxe%'
  or (nombre ilike '%lider%'      and (nombre ilike '%375%' or nombre ilike '%750%'))
  or (nombre ilike '%manzanares%' and (nombre ilike '%375%' or nombre ilike '%750%'))
  or (nombre ilike '%onix%' and nombre ilike '%amarillo%' and (nombre ilike '%375%' or nombre ilike '%750%'))
  or (nombre ilike '%onix%' and nombre ilike '%100%'      and (nombre ilike '%375%' or nombre ilike '%750%'))
  or (nombre ilike '%aguila%' and nombre ilike '%269%')
  or (nombre ilike '%coste%'  and nombre ilike '%269%')
  or (nombre ilike '%antioque%' and (nombre ilike '%azul%' or nombre ilike '%verde%')
                                and (nombre ilike '%375%' or nombre ilike '%750%'))
  or (nombre ilike '%ron%' and nombre ilike '%caldas%' and (nombre ilike '%375%' or nombre ilike '%750%'))
  or nombre ilike '%mustang%'
  or nombre ilike '%luki%' or nombre ilike '%lucky%'
  or nombre ilike '%rothmans%'
);

-- 3. Orden inicial alfabético
with ordenados as (
  select id, row_number() over (order by nombre) as rn
  from productos
  where en_turbo
)
update productos p
set orden_turbo = o.rn
from ordenados o
where p.id = o.id;

-- 4. RPC: agregar/quitar un producto del menú turbo
create or replace function set_producto_turbo(p_producto_id uuid, p_en_turbo boolean)
returns void
language plpgsql
security definer
as $$
begin
  if p_en_turbo then
    update productos
    set en_turbo = true,
        orden_turbo = coalesce((select max(orden_turbo) from productos where en_turbo), 0) + 1
    where id = p_producto_id
      and en_turbo = false;
  else
    update productos
    set en_turbo = false,
        orden_turbo = null
    where id = p_producto_id;
  end if;
end;
$$;

-- 5. RPC: persistir el reorden manual en batch atómico
create or replace function actualizar_orden_turbo(p_ids uuid[])
returns void
language plpgsql
security definer
as $$
begin
  update productos p
  set orden_turbo = t.ord
  from unnest(p_ids) with ordinality as t(id, ord)
  where p.id = t.id
    and p.en_turbo = true;
end;
$$;
