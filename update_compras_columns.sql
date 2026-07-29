-- ============================================================
-- CONSOLIDATED PATCH FOR COMPRAS_INVENTARIO AND CAPITAL
-- Run this script in the Supabase SQL Editor (https://supabase.com)
-- ============================================================

-- 1. Agregar 'credito' al enum metodo_pago si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t 
    JOIN pg_enum e ON t.oid = e.enumtypid 
    WHERE t.typname = 'metodo_pago' AND e.enumlabel = 'credito'
  ) THEN
    ALTER TYPE metodo_pago ADD VALUE 'credito';
  END IF;
END
$$;

-- 2. Agregar la columna 'ajuste' a compras_inventario si no existe
ALTER TABLE compras_inventario 
ADD COLUMN IF NOT EXISTS ajuste numeric(12,3) NOT null DEFAULT 0;

-- 3. Agregar la columna 'valor_deuda' a compras_inventario si no existe
ALTER TABLE compras_inventario 
ADD COLUMN IF NOT EXISTS valor_deuda numeric(12,3) NOT null DEFAULT 0;

-- 4. Actualizar la función registrar_compra para soportar p_ajuste, p_valor_deuda y costo promedio ponderado
CREATE OR REPLACE FUNCTION registrar_compra(
  p_proveedor_id  uuid,
  p_fecha         date,
  p_metodo_pago   metodo_pago,
  p_notas         text,
  p_items         jsonb,
  p_ajuste        numeric(12,3) DEFAULT 0,
  p_valor_deuda   numeric(12,3) DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_compra_id      uuid;
  v_item           record;
  v_stock_antes    integer;
  v_stock_despues  integer;
  v_total_real     numeric(12,3);
BEGIN
  -- a) Validar que p_items no esté vacío
  IF p_items IS null
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La compra debe incluir al menos un producto';
  END IF;

  -- b) Insertar la fila en compras_inventario con total = 0 y capturar su id
  INSERT INTO compras_inventario (proveedor_id, fecha, metodo_pago, notas, total, ajuste, valor_deuda)
  VALUES (p_proveedor_id, p_fecha, p_metodo_pago, p_notas, 0, coalesce(p_ajuste, 0), coalesce(p_valor_deuda, 0))
  RETURNING id INTO v_compra_id;

  -- c) Para cada item en p_items:
  FOR v_item IN
    SELECT *
    FROM jsonb_to_recordset(p_items) AS x(
      producto_id uuid,
      cantidad integer,
      costo_unitario numeric(12,3)
    )
  LOOP
    IF v_item.producto_id IS null THEN
      RAISE EXCEPTION 'Cada ítem debe incluir producto_id';
    END IF;

    IF v_item.cantidad IS null OR v_item.cantidad <= 0 THEN
      RAISE EXCEPTION 'Cantidad inválida para producto %', v_item.producto_id;
    END IF;

    IF v_item.costo_unitario IS null OR v_item.costo_unitario < 0 THEN
      RAISE EXCEPTION 'Costo unitario inválido para producto %', v_item.producto_id;
    END IF;

    -- Validar que producto_id exista con FOR UPDATE
    SELECT stock_actual INTO v_stock_antes
    FROM productos
    WHERE id = v_item.producto_id
      AND activo = true
    FOR UPDATE;

    IF NOT found THEN
      RAISE EXCEPTION 'Producto no existe o está inactivo: %', v_item.producto_id;
    END IF;

    -- Insertar en detalle_compras
    INSERT INTO detalle_compras (compra_id, producto_id, cantidad, costo_unitario)
    VALUES (v_compra_id, v_item.producto_id, v_item.cantidad, v_item.costo_unitario);

    -- Incrementar stock_actual del producto y actualizar a costo promedio ponderado
    UPDATE productos
    SET costo = CASE 
                  WHEN stock_actual > 0 THEN
                    round(((stock_actual * costo) + (v_item.cantidad * v_item.costo_unitario)) / (stock_actual + v_item.cantidad), 3)
                  ELSE 
                    v_item.costo_unitario
                END,
        stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id
    returning stock_actual into v_stock_despues;

    -- Registrar en movimientos_stock (tipo='entrada', motivo='compra_inventario', referencia_id=compra_id)
    INSERT INTO movimientos_stock (
      producto_id,
      tipo,
      cantidad,
      stock_antes,
      stock_despues,
      motivo,
      referencia_id
    )
    VALUES (
      v_item.producto_id,
      'entrada'::tipo_movimiento,
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'compra_inventario',
      v_compra_id
    );
  END LOOP;

  -- d) Calcular el total real (sum de subtotales de detalle_compras) y actualizar compras_inventario.total
  SELECT coalesce(sum(subtotal), 0) INTO v_total_real
  FROM detalle_compras
  WHERE compra_id = v_compra_id;

  UPDATE compras_inventario
  SET total = v_total_real + coalesce(p_ajuste, 0)
  WHERE id = v_compra_id;

  -- e) Retornar el id de la compra creada
  RETURN v_compra_id;
END;
$$;
