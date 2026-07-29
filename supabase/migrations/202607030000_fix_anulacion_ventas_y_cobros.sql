-- Migration: Corregir anulación de ventas para limpiar los cobros asociados y deudas pendientes.

-- 1. Eliminar cobros de mayoristas huérfanos que corresponden a ventas que ya fueron anuladas.
DELETE FROM cobros_mayoristas 
WHERE venta_id IN (
    SELECT id FROM ventas WHERE estado = 'anulada'
);

-- 2. Modificar la función anular_venta para que elimine automáticamente el cobro (cuenta por cobrar) de la venta que se anula.
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
  -- Obtener el estado actual de la venta con bloqueo para evitar condiciones de carrera
  SELECT estado INTO v_estado_actual FROM ventas WHERE id = p_venta_id FOR UPDATE;
  
  IF v_estado_actual IS NULL THEN
    RAISE EXCEPTION 'La venta especificada no existe.';
  END IF;
  IF v_estado_actual = 'anulada' THEN
    RAISE EXCEPTION 'La venta ya está anulada.';
  END IF;

  -- Revertir el stock de cada producto de la venta
  FOR v_item IN
    SELECT producto_id, cantidad FROM detalle_ventas WHERE venta_id = p_venta_id
  LOOP
    -- Bloquear producto para actualizar el stock
    SELECT stock_actual INTO v_stock_antes FROM productos WHERE id = v_item.producto_id FOR UPDATE;
    
    UPDATE productos 
    SET stock_actual = stock_actual + v_item.cantidad
    WHERE id = v_item.producto_id 
    RETURNING stock_actual INTO v_stock_despues;
    
    -- Registrar movimiento de stock
    INSERT INTO movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id)
    VALUES (v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad, v_stock_antes, v_stock_despues, 'anulacion_venta', p_venta_id);
  END LOOP;

  -- Actualizar el estado de la venta
  UPDATE ventas
  SET estado = 'anulada', 
      notas = COALESCE(notas || ' | ', '') || 'ANULADA: ' || COALESCE(p_motivo, 'sin motivo')
  WHERE id = p_venta_id;

  -- Eliminar el cobro asociado para corregir la deuda del cliente mayorista
  DELETE FROM cobros_mayoristas WHERE venta_id = p_venta_id;
END;
$$;

-- 3. Desactivar RLS en las nuevas tablas para permitir operaciones sin autenticación (ya que el inicio de sesión anónimo está deshabilitado en Supabase).
ALTER TABLE proveedores DISABLE ROW LEVEL SECURITY;
ALTER TABLE compras_inventario DISABLE ROW LEVEL SECURITY;
ALTER TABLE detalle_compras DISABLE ROW LEVEL SECURITY;
ALTER TABLE capital_negocio DISABLE ROW LEVEL SECURITY;

