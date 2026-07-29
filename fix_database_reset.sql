-- ============================================================
-- CONSOLIDATED DATABASE RESTORATION SCRIPT — DON HÉCTOR
-- Run this script in the Supabase SQL Editor to apply all migrations
-- ============================================================

-- ------------------------------------------------------------
-- MIGRATION: 202605260000_eliminar_venta_rpc
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION eliminar_venta(p_venta_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_item record;
  v_stock_antes integer;
  v_stock_despues integer;
  v_venta_existe boolean;
BEGIN
  SELECT exists(SELECT 1 FROM ventas WHERE id = p_venta_id) INTO v_venta_existe;
  IF NOT v_venta_existe THEN
    RAISE EXCEPTION 'La venta especificada no existe.';
  END IF;

  FOR v_item IN
    SELECT producto_id, cantidad
    FROM detalle_ventas
    WHERE venta_id = p_venta_id
  LOOP
    SELECT stock_actual INTO v_stock_antes
    FROM productos
    WHERE id = v_item.producto_id
    FOR UPDATE;

    UPDATE productos
    SET stock_actual = stock_actual + v_item.cantidad
    WHERE id = v_item.producto_id
    RETURNING stock_actual INTO v_stock_despues;

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
      'entrada',
      v_item.cantidad,
      v_stock_antes,
      v_stock_despues,
      'eliminacion_venta',
      p_venta_id
    );
  END LOOP;

  DELETE FROM ventas WHERE id = p_venta_id;
END;
$$;

-- ------------------------------------------------------------
-- MIGRATION: 202605260001_add_categoria_cigarrillos
-- ------------------------------------------------------------
INSERT INTO categorias (nombre) 
VALUES ('Cigarrillos')
ON CONFLICT (nombre) DO NOTHING;

-- ------------------------------------------------------------
-- MIGRATION: 202606030000_update_categorias_gasto
-- ------------------------------------------------------------
UPDATE categorias_gasto 
SET nombre = 'Personales' 
WHERE nombre = 'Personal / Nómina';

UPDATE categorias_gasto 
SET nombre = 'Suministros' 
WHERE nombre = 'Suministros y empaques';

DELETE FROM categorias_gasto 
WHERE nombre = 'Arriendo';

DELETE FROM categorias_gasto 
WHERE nombre = 'Mantenimiento';

-- ------------------------------------------------------------
-- MIGRATION: 20260609000000_drop_netwars_table
-- ------------------------------------------------------------
DROP TABLE IF EXISTS "public"."netwars";

-- ------------------------------------------------------------
-- MIGRATION: 202606100000_add_ajustar_stock_rpc
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION ajustar_stock(
  p_producto_id uuid,
  p_cantidad integer,
  p_tipo text,
  p_motivo text
) RETURNS void AS $$
DECLARE
  v_stock_antes integer;
  v_stock_despues integer;
BEGIN
  SELECT stock_actual INTO v_stock_antes
  FROM productos
  WHERE id = p_producto_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto con ID % no encontrado', p_producto_id;
  END IF;

  IF p_tipo <> 'entrada' AND p_tipo <> 'salida' THEN
    RAISE EXCEPTION 'Tipo de movimiento invalido: %. Debe ser "entrada" o "salida"', p_tipo;
  END IF;

  IF p_tipo = 'entrada' THEN
    UPDATE productos
    SET stock_actual = stock_actual + p_cantidad
    WHERE id = p_producto_id
    RETURNING stock_actual INTO v_stock_despues;
  ELSE
    UPDATE productos
    SET stock_actual = stock_actual - p_cantidad
    WHERE id = p_producto_id
    RETURNING stock_actual INTO v_stock_despues;
  END IF;

  INSERT INTO movimientos_stock (
    producto_id,
    tipo,
    cantidad,
    stock_antes,
    stock_despues,
    motivo
  ) VALUES (
    p_producto_id,
    p_tipo::tipo_movimiento,
    p_cantidad,
    v_stock_antes,
    v_stock_despues,
    p_motivo
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------
-- MIGRATION: 202606130000_add_alimentos_mj_gasto_categorias
-- ------------------------------------------------------------
INSERT INTO categorias_gasto (nombre)
VALUES 
  ('Alimentos'),
  ('MJ')
ON CONFLICT (nombre) DO NOTHING;

-- ------------------------------------------------------------
-- MIGRATION: 202606170000_update_decimals
-- ------------------------------------------------------------
DROP VIEW IF EXISTS productos_mas_vendidos;
DROP VIEW IF EXISTS estado_cuenta_mayoristas;
DROP VIEW IF EXISTS resumen_ventas_dia;

ALTER TABLE detalle_ventas DROP COLUMN IF EXISTS subtotal;
ALTER TABLE cobros_mayoristas DROP COLUMN IF EXISTS saldo;

ALTER TABLE productos ALTER COLUMN precio_publico TYPE numeric(12, 3);
ALTER TABLE productos ALTER COLUMN precio_mayorista TYPE numeric(12, 3);
ALTER TABLE productos ALTER COLUMN costo TYPE numeric(12, 3);

ALTER TABLE detalle_ventas ALTER COLUMN precio_unitario TYPE numeric(12, 3);

ALTER TABLE ventas ALTER COLUMN subtotal TYPE numeric(12, 3);
ALTER TABLE ventas ALTER COLUMN descuento TYPE numeric(12, 3);
ALTER TABLE ventas ALTER COLUMN total TYPE numeric(12, 3);

ALTER TABLE cobros_mayoristas ALTER COLUMN total_venta TYPE numeric(12, 3);
ALTER TABLE cobros_mayoristas ALTER COLUMN total_pagado TYPE numeric(12, 3);

ALTER TABLE pagos_mayoristas ALTER COLUMN monto TYPE numeric(12, 3);

ALTER TABLE gastos ALTER COLUMN monto TYPE numeric(12, 3);

ALTER TABLE detalle_ventas ADD COLUMN subtotal numeric(12, 3) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED;
ALTER TABLE cobros_mayoristas ADD COLUMN saldo numeric(12, 3) GENERATED ALWAYS AS (total_venta - total_pagado) STORED;

CREATE OR REPLACE VIEW resumen_ventas_dia
WITH (security_invoker = true) AS
  SELECT
    date_trunc('day', fecha) as dia,
    count(*) as num_ventas,
    sum(total) as total_ventas,
    sum(case when tipo = 'publico' then total else 0 end) as ventas_publico,
    sum(case when tipo = 'mayorista' then total else 0 end) as ventas_mayorista
  FROM ventas
  WHERE estado = 'completada'
  GROUP BY 1
  ORDER BY 1 DESC;

CREATE OR REPLACE VIEW productos_mas_vendidos
WITH (security_invoker = true) AS
  SELECT
    p.id,
    p.nombre,
    c.nombre as categoria,
    sum(dv.cantidad) as unidades_vendidas,
    sum(dv.subtotal) as ingresos_totales
  FROM detalle_ventas dv
  JOIN productos p ON p.id = dv.producto_id
  JOIN ventas v ON v.id = dv.venta_id
  LEFT JOIN categorias c ON c.id = p.categoria_id
  WHERE v.estado = 'completada'
  GROUP BY p.id, p.nombre, c.nombre
  ORDER BY unidades_vendidas DESC;

CREATE OR REPLACE VIEW estado_cuenta_mayoristas
WITH (security_invoker = true) AS
  SELECT
    cm.id,
    cm.nombre,
    cm.telefono,
    count(c.id) as num_pedidos,
    coalesce(sum(c.total_venta), 0) as total_compras,
    coalesce(sum(c.total_pagado), 0) as total_pagado,
    coalesce(sum(c.saldo), 0) as deuda_pendiente
  FROM clientes_mayoristas cm
  LEFT JOIN cobros_mayoristas c ON c.cliente_id = cm.id
  WHERE cm.activo = true
  GROUP BY cm.id, cm.nombre, cm.telefono
  ORDER BY deuda_pendiente DESC;

-- ------------------------------------------------------------
-- MIGRATION: 202606170002_add_cogs_rango_rpc
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION cogs_rango(p_start timestamptz, p_end timestamptz)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT coalesce(sum(dv.cantidad * p.costo), 0)
  FROM detalle_ventas dv
  JOIN ventas v ON v.id = dv.venta_id
  JOIN productos p ON p.id = dv.producto_id
  WHERE v.estado = 'completada'
    AND v.fecha >= p_start
    AND v.fecha <= p_end;
$$;

-- ------------------------------------------------------------
-- MIGRATION: 202606170003_anulacion_logica_y_reglas
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION anular_venta(p_venta_id uuid, p_motivo text default null)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_stock_antes integer;
  v_stock_despues integer;
  v_estado_actual estado_venta;
BEGIN
  SELECT estado into v_estado_actual FROM ventas WHERE id = p_venta_id FOR UPDATE;
  
  IF v_estado_actual IS NULL THEN
    RAISE EXCEPTION 'La venta especificada no existe.';
  END IF;
  IF v_estado_actual = 'anulada' THEN
    RAISE EXCEPTION 'La venta ya está anulada.';
  END IF;

  FOR v_item IN
    SELECT producto_id, cantidad FROM detalle_ventas WHERE venta_id = p_venta_id
  LOOP
    SELECT stock_actual INTO v_stock_antes FROM productos WHERE id = v_item.producto_id FOR UPDATE;
    
    UPDATE productos 
    SET stock_actual = stock_actual + v_item.cantidad
    WHERE id = v_item.producto_id 
    RETURNING stock_actual INTO v_stock_despues;
    
    INSERT INTO movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id)
    VALUES (v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad, v_stock_antes, v_stock_despues, 'anulacion_venta', p_venta_id);
  END LOOP;

  UPDATE ventas
  SET estado = 'anulada', 
      notas = coalesce(notas || ' | ', '') || 'ANULADA: ' || coalesce(p_motivo, 'sin motivo')
  WHERE id = p_venta_id;
END;
$$;

ALTER TABLE gastos ADD COLUMN IF NOT EXISTS anulado boolean not null default false;

CREATE OR REPLACE FUNCTION validar_pago_no_excede_saldo()
RETURNS trigger as $$
DECLARE
  v_saldo_actual numeric;
BEGIN
  SELECT saldo INTO v_saldo_actual FROM cobros_mayoristas WHERE id = new.cobro_id;
  IF new.monto > v_saldo_actual THEN
    RAISE EXCEPTION 'El pago (%) excede el saldo pendiente (%)', new.monto, v_saldo_actual;
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pago_no_excede_saldo ON pagos_mayoristas;
CREATE TRIGGER pago_no_excede_saldo
  BEFORE INSERT ON pagos_mayoristas
  FOR EACH ROW EXECUTE FUNCTION validar_pago_no_excede_saldo();

CREATE OR REPLACE FUNCTION ajustar_stock(
  p_producto_id uuid, p_cantidad integer, p_tipo text, p_motivo text
) RETURNS void AS $$
DECLARE
  v_stock_antes integer;
  v_stock_despues integer;
BEGIN
  SELECT stock_actual INTO v_stock_antes FROM productos WHERE id = p_producto_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto con ID % no encontrado', p_producto_id;
  END IF;

  IF p_tipo <> 'entrada' AND p_tipo <> 'salida' THEN
    RAISE EXCEPTION 'Tipo de movimiento invalido: %. Debe ser "entrada" o "salida"', p_tipo;
  END IF;

  IF p_tipo = 'salida' AND v_stock_antes < p_cantidad THEN
    RAISE EXCEPTION 'Stock insuficiente: hay % unidades, se intentan retirar %', v_stock_antes, p_cantidad;
  END IF;

  IF p_tipo = 'entrada' THEN
    UPDATE productos SET stock_actual = stock_actual + p_cantidad WHERE id = p_producto_id RETURNING stock_actual INTO v_stock_despues;
  ELSE
    UPDATE productos SET stock_actual = stock_actual - p_cantidad WHERE id = p_producto_id RETURNING stock_actual INTO v_stock_despues;
  END IF;

  INSERT INTO movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo)
  VALUES (p_producto_id, p_tipo::tipo_movimiento, p_cantidad, v_stock_antes, v_stock_despues, p_motivo);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
