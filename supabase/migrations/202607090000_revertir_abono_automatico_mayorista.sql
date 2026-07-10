-- ============================================================
-- MIGRATION: 202607090000_revertir_abono_automatico_mayorista
-- La migración 202607080000 agregó un abono automático por el
-- total en ventas mayoristas que no fueran a crédito, dejando el
-- cobro "pagado" al instante. Esto rompió el flujo esperado: toda
-- venta mayorista debe quedar como cuenta por cobrar pendiente,
-- sin importar el método de pago; el cobro se registra aparte,
-- manualmente, cuando el cliente efectivamente paga.
-- Se revierte a la semántica de 202607010002.
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

  if p_tipo = 'publico' and p_metodo_pago = 'credito' then
    raise exception 'Las ventas al público no pueden ser a crédito';
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

  return v_venta_id;
end;
$$;
