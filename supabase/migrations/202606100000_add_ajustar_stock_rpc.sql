-- Crear la funcion/RPC ajustar_stock para auditar cambios de inventario
create or replace function ajustar_stock(
  p_producto_id uuid,
  p_cantidad integer,
  p_tipo text, -- 'entrada' o 'salida'
  p_motivo text
) returns void as $$
declare
  v_stock_antes integer;
  v_stock_despues integer;
begin
  -- Obtener stock antes del ajuste
  select stock_actual into v_stock_antes
  from productos
  where id = p_producto_id;

  if not found then
    raise exception 'Producto con ID % no encontrado', p_producto_id;
  end if;

  -- Validar tipo de movimiento
  if p_tipo <> 'entrada' and p_tipo <> 'salida' then
    raise exception 'Tipo de movimiento invalido: %. Debe ser "entrada" o "salida"', p_tipo;
  end if;

  -- Actualizar stock
  if p_tipo = 'entrada' then
    update productos
    set stock_actual = stock_actual + p_cantidad
    where id = p_producto_id
    returning stock_actual into v_stock_despues;
  else
    update productos
    set stock_actual = stock_actual - p_cantidad
    where id = p_producto_id
    returning stock_actual into v_stock_despues;
  end if;

  -- Insertar movimiento de stock para auditoria
  insert into movimientos_stock (
    producto_id,
    tipo,
    cantidad,
    stock_antes,
    stock_despues,
    motivo
  ) values (
    p_producto_id,
    p_tipo,
    p_cantidad,
    v_stock_antes,
    v_stock_despues,
    p_motivo
  );
end;
$$ language plpgsql security definer;
