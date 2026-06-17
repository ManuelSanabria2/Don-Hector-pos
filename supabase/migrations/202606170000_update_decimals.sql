-- 1. Eliminar vistas dependientes primero
DROP VIEW IF EXISTS productos_mas_vendidos;
DROP VIEW IF EXISTS estado_cuenta_mayoristas;
DROP VIEW IF EXISTS resumen_ventas_dia;

-- 2. Eliminar las columnas generadas dependientes
ALTER TABLE detalle_ventas DROP COLUMN subtotal;
ALTER TABLE cobros_mayoristas DROP COLUMN saldo;

-- 3. Modificar precisión decimal a 3 decimales en productos
ALTER TABLE productos ALTER COLUMN precio_publico TYPE numeric(12, 3);
ALTER TABLE productos ALTER COLUMN precio_mayorista TYPE numeric(12, 3);
ALTER TABLE productos ALTER COLUMN costo TYPE numeric(12, 3);

-- 4. Modificar precisión en detalle_ventas (precio_unitario)
ALTER TABLE detalle_ventas ALTER COLUMN precio_unitario TYPE numeric(12, 3);

-- 5. Modificar precisión en ventas
ALTER TABLE ventas ALTER COLUMN subtotal TYPE numeric(12, 3);
ALTER TABLE ventas ALTER COLUMN descuento TYPE numeric(12, 3);
ALTER TABLE ventas ALTER COLUMN total TYPE numeric(12, 3);

-- 6. Modificar precisión en cobros_mayoristas
ALTER TABLE cobros_mayoristas ALTER COLUMN total_venta TYPE numeric(12, 3);
ALTER TABLE cobros_mayoristas ALTER COLUMN total_pagado TYPE numeric(12, 3);

-- 7. Modificar precisión en pagos_mayoristas
ALTER TABLE pagos_mayoristas ALTER COLUMN monto TYPE numeric(12, 3);

-- 8. Modificar precisión en gastos
ALTER TABLE gastos ALTER COLUMN monto TYPE numeric(12, 3);

-- 9. Recrear las columnas generadas con la nueva precisión (3 decimales)
ALTER TABLE detalle_ventas ADD COLUMN subtotal numeric(12, 3) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED;
ALTER TABLE cobros_mayoristas ADD COLUMN saldo numeric(12, 3) GENERATED ALWAYS AS (total_venta - total_pagado) STORED;

-- 10. Recrear las vistas dependientes
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
