-- ============================================================
-- Creación de la función RPC cogs_rango para calcular el Costo de Ventas
-- ============================================================

create or replace function cogs_rango(p_start timestamptz, p_end timestamptz)
returns numeric
language sql
stable
security definer
as $$
  select coalesce(sum(dv.cantidad * p.costo), 0)
  from detalle_ventas dv
  join ventas v on v.id = dv.venta_id
  join productos p on p.id = dv.producto_id
  where v.estado = 'completada'
    and v.fecha >= p_start
    and v.fecha <= p_end;
$$;
