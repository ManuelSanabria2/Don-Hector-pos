-- ============================================================
-- RPC — ELIMINAR VENTA (atómica)
-- Revierte el stock devolviendo las cantidades de detalle_ventas
-- y luego elimina la cabecera de la venta (eliminando en cascada lo demás).
-- ============================================================
create or replace function eliminar_venta(
  p_venta_id uuid
)
returns void
language plpgsql
as $$
declare
  v_item record;
  v_stock_antes integer;
  v_stock_despues integer;
  v_venta_existe boolean;
begin
  -- Verificar que la venta existe
  select exists(select 1 from ventas where id = p_venta_id) into v_venta_existe;
  if not v_venta_existe then
    raise exception 'La venta especificada no existe.';
  end if;

  -- Iterar sobre cada detalle de la venta para devolver el stock
  for v_item in
    select producto_id, cantidad
    from detalle_ventas
    where venta_id = p_venta_id
  loop
    -- Bloquear el producto para actualizar su stock de forma segura
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
    for update;

    -- Aumentar el stock
    update productos
    set stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    -- Registrar el movimiento de auditoría
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
      'entrada',
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'eliminacion_venta',
      p_venta_id
    );
  end loop;

  -- Finalmente, eliminar la cabecera de la venta.
  -- Esto eliminará en cascada los registros en detalle_ventas y en cobros_mayoristas
  -- (y por consiguiente, sus pagos_mayoristas).
  delete from ventas where id = p_venta_id;

end;
$$;
