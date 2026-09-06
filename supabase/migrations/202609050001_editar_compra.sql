-- ============================================================
-- MIGRATION: 202609050001_editar_compra
--
-- Permite corregir una factura de compra ya registrada sin tener
-- que anularla y volver a digitarla entera.
--
-- Hasta ahora la única forma de arreglar una compra mal digitada
-- era anular_compra + registrar_compra. Eso falla justo cuando más
-- se necesita: anular devuelve el stock, y si la mercancía ya se
-- vendió el stock actual queda por debajo y la anulación se cae.
-- Además parte la factura en dos registros y se pierde el hilo.
--
-- editar_compra hace las dos mitades en una sola transacción y
-- conserva el id de la compra, así que los pagos ya registrados
-- siguen colgando de ella.
--
-- LIMITACIÓN CONOCIDA, la misma que ya tiene anular_compra: al
-- revertir las líneas viejas se devuelve el stock pero NO se
-- deshace el costo promedio ponderado que esas líneas dejaron en
-- el producto. Revertirlo exactamente solo es posible si esa fue la
-- última compra de ese producto, y no hay cómo saberlo sin llevar
-- historial de costos. El costo queda mezclado, igual que si se
-- hubiera anulado y vuelto a registrar a mano. Para dejarlo exacto
-- está ajustar_stock.
-- ============================================================
create or replace function editar_compra(
  p_compra_id    uuid,
  p_proveedor_id uuid,
  p_fecha        date,
  p_metodo_pago  metodo_pago,
  p_notas        text,
  p_items        jsonb,
  p_ajuste       numeric(12,3) default 0
)
returns numeric
language plpgsql
security definer
as $$
declare
  v_anulado        boolean;
  v_item           record;
  v_stock_antes    integer;
  v_stock_despues  integer;
  v_total_real     numeric(12,3);
  v_total          numeric(12,3);
  v_pagos          numeric(12,3);
  v_deuda          numeric(12,3);
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra debe incluir al menos un producto';
  end if;

  select anulado into v_anulado
  from compras_inventario
  where id = p_compra_id
  for update;

  if not found then
    raise exception 'La compra especificada no existe.';
  end if;

  if v_anulado then
    raise exception 'No se puede editar una compra anulada.';
  end if;

  -- Plata que ya se pagó de esta factura. Se respeta: editar la
  -- factura no puede borrar un desembolso que sí ocurrió.
  select coalesce(sum(monto), 0) into v_pagos
  from pagos_compras
  where compra_id = p_compra_id
    and anulado = false;

  if v_pagos > 0 and p_metodo_pago <> 'credito' then
    raise exception
      'La compra tiene % en pagos registrados, así que debe seguir siendo a crédito. Anula esos pagos primero si quieres cambiarle el método.',
      v_pagos;
  end if;

  -- ----------------------------------------------------------
  -- a) Deshacer las líneas viejas: sale el stock que entró.
  -- ----------------------------------------------------------
  for v_item in
    select producto_id, cantidad
    from detalle_compras
    where compra_id = p_compra_id
  loop
    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
    for update;

    if not found then
      raise exception 'Producto con ID % no encontrado.', v_item.producto_id;
    end if;

    if v_stock_antes < v_item.cantidad then
      raise exception
        'No se puede editar: para quitar la línea vieja hacen falta % unidades y solo hay % en stock. Ajusta el stock primero.',
        v_item.cantidad, v_stock_antes;
    end if;

    update productos
    set stock_actual = stock_actual - v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    insert into movimientos_stock (
      producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id
    )
    values (
      v_item.producto_id, 'salida'::tipo_movimiento, v_item.cantidad,
      v_stock_antes, v_stock_despues, 'edicion_compra', p_compra_id
    );
  end loop;

  delete from detalle_compras where compra_id = p_compra_id;

  -- ----------------------------------------------------------
  -- b) Aplicar las líneas nuevas, igual que registrar_compra.
  -- ----------------------------------------------------------
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

    select stock_actual into v_stock_antes
    from productos
    where id = v_item.producto_id
      and activo = true
    for update;

    if not found then
      raise exception 'Producto no existe o está inactivo: %', v_item.producto_id;
    end if;

    insert into detalle_compras (compra_id, producto_id, cantidad, costo_unitario)
    values (p_compra_id, v_item.producto_id, v_item.cantidad, v_item.costo_unitario);

    update productos
    set costo = case
                  when stock_actual > 0 then
                    round(((stock_actual * costo) + (v_item.cantidad * v_item.costo_unitario)) / (stock_actual + v_item.cantidad), 3)
                  else
                    v_item.costo_unitario
                end,
        stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    insert into movimientos_stock (
      producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id
    )
    values (
      v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad,
      v_stock_antes, v_stock_despues, 'edicion_compra', p_compra_id
    );
  end loop;

  -- ----------------------------------------------------------
  -- c) Recalcular el total. El ajuste puede ser negativo: así se
  --    registra un descuento del proveedor (por ejemplo el rebate
  --    que descuenta de la factura del pedido).
  -- ----------------------------------------------------------
  select coalesce(sum(subtotal), 0) into v_total_real
  from detalle_compras
  where compra_id = p_compra_id;

  v_total := v_total_real + coalesce(p_ajuste, 0);

  if v_total < 0 then
    raise exception 'El descuento (%) deja la factura en negativo. El total no puede ser menor a cero.', p_ajuste;
  end if;

  -- ----------------------------------------------------------
  -- d) La deuda es lo que falta por pagar: total menos lo pagado.
  -- ----------------------------------------------------------
  if p_metodo_pago = 'credito' then
    if v_pagos > v_total then
      raise exception
        'Ya se pagaron % de esta factura y el nuevo total es %. Baja los pagos o sube el total.',
        v_pagos, v_total;
    end if;
    v_deuda := v_total - v_pagos;
  else
    v_deuda := 0;
  end if;

  update compras_inventario
  set proveedor_id = p_proveedor_id,
      fecha        = p_fecha,
      metodo_pago  = p_metodo_pago,
      notas        = p_notas,
      ajuste       = coalesce(p_ajuste, 0),
      total        = v_total,
      valor_deuda  = v_deuda
  where id = p_compra_id;

  return v_total;
end;
$$;
