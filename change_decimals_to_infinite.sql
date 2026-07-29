-- ============================================================
-- ALTER DATABASE COLUMNS TO SUPPORT INFINITE PRECISION DECIMALS
-- Run this script in the Supabase SQL Editor
-- ============================================================

-- 1. Drop dependent views first
DROP VIEW IF EXISTS productos_mas_vendidos;
DROP VIEW IF EXISTS estado_cuenta_mayoristas;
DROP VIEW IF EXISTS resumen_ventas_dia;

-- 2. Drop generated columns
ALTER TABLE detalle_ventas DROP COLUMN IF EXISTS subtotal;
ALTER TABLE cobros_mayoristas DROP COLUMN IF EXISTS saldo;

-- 3. Alter columns to unconstrained numeric
ALTER TABLE productos ALTER COLUMN precio_publico TYPE numeric;
ALTER TABLE productos ALTER COLUMN precio_mayorista TYPE numeric;
ALTER TABLE productos ALTER COLUMN costo TYPE numeric;

ALTER TABLE detalle_ventas ALTER COLUMN precio_unitario TYPE numeric;

ALTER TABLE ventas ALTER COLUMN subtotal TYPE numeric;
ALTER TABLE ventas ALTER COLUMN descuento TYPE numeric;
ALTER TABLE ventas ALTER COLUMN total TYPE numeric;

ALTER TABLE cobros_mayoristas ALTER COLUMN total_venta TYPE numeric;
ALTER TABLE cobros_mayoristas ALTER COLUMN total_pagado TYPE numeric;

ALTER TABLE pagos_mayoristas ALTER COLUMN monto TYPE numeric;

ALTER TABLE gastos ALTER COLUMN monto TYPE numeric;

-- 4. Recreate generated columns as unconstrained numeric
ALTER TABLE detalle_ventas ADD COLUMN subtotal numeric GENERATED ALWAYS AS (cantidad * precio_unitario) STORED;
ALTER TABLE cobros_mayoristas ADD COLUMN saldo numeric GENERATED ALWAYS AS (total_venta - total_pagado) STORED;

-- 5. Recreate views
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
