-- ============================================================
-- MIGRATION: 202608310000_top_mayorista_dia
-- Acceso rapido en la pestana de VENTA: los mas vendidos a
-- MAYORISTAS dentro de un dia.
--
-- Reemplaza a productos_mas_vendidos_anio (202608280000), que
-- rankeaba por todo el anio y sobre todas las ventas. El criterio
-- que pidio el cliente es distinto: solo ventas tipo 'mayorista'
-- y en una ventana de un dia.
--
-- El rango llega como timestamptz desde la app (convencion del
-- repo: Dart calcula el dia local y lo manda en UTC, rango
-- semiabierto [desde, hasta)). Asi "hoy" es el dia local del
-- negocio y no el dia UTC.
--
-- Devuelve filas completas de productos (setof productos) para
-- poder mapearlas al modelo Producto y armar el carrito.
-- ============================================================

drop function if exists productos_mas_vendidos_anio(integer, integer);

create or replace function productos_mas_vendidos_mayorista_dia(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_limit integer default 10
)
returns setof productos
language sql
stable
security definer
as $$
  select p.*
  from productos p
  join detalle_ventas dv on dv.producto_id = p.id
  join ventas v on v.id = dv.venta_id
  where v.estado = 'completada'
    and v.tipo = 'mayorista'
    and v.fecha >= p_desde
    and v.fecha < p_hasta
    and coalesce(p.activo, false) = true
  group by p.id
  order by sum(dv.cantidad) desc, p.nombre
  limit greatest(coalesce(p_limit, 10), 0);
$$;

-- Índice de apoyo: el join agrupa detalle_ventas por producto.
create index if not exists idx_detalle_ventas_producto
  on detalle_ventas (producto_id);
