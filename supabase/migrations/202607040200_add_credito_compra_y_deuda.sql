-- ============================================================
-- AGREGAR MÉTODO DE PAGO 'CREDITO', COLUMNA VALOR_DEUDA Y RPC ACTUALIZADO
-- ============================================================

-- 1. Agregar 'credito' al enum metodo_pago si no existe
-- Nota: En Postgres se usa ALTER TYPE ... ADD VALUE. Esto no se puede revertir fácilmente en transacciones pero es soportado por Supabase.
alter type metodo_pago add value if not exists 'credito';

-- 2. Agregar la columna valor_deuda a compras_inventario
alter table compras_inventario 
add column if not exists valor_deuda numeric(12,3) not null default 0;

-- 3. Actualizar la función registrar_compra para soportar p_valor_deuda
create or replace function registrar_compra(
  p_proveedor_id  uuid,
  p_fecha         date,
  p_metodo_pago   metodo_pago,
  p_notas         text,
  p_items         jsonb,
  p_ajuste        numeric(12,3) default 0,
  p_valor_deuda   numeric(12,3) default 0
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
  insert into compras_inventario (proveedor_id, fecha, metodo_pago, notas, total, ajuste, valor_deuda)
  values (p_proveedor_id, p_fecha, p_metodo_pago, p_notas, 0, coalesce(p_ajuste, 0), coalesce(p_valor_deuda, 0))
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
  set total = v_total_real + coalesce(p_ajuste, 0)
  where id = v_compra_id;

  -- e) Retornar el id de la compra creada
  return v_compra_id;
end;
$$;
