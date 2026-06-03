-- Actualizar los nombres de las categorías de gastos
UPDATE categorias_gasto 
SET nombre = 'Personales' 
WHERE nombre = 'Personal / Nómina';

UPDATE categorias_gasto 
SET nombre = 'Suministros' 
WHERE nombre = 'Suministros y empaques';

-- Eliminar categorías no requeridas (se establece NULL en los gastos históricos por restricción ON DELETE SET NULL)
DELETE FROM categorias_gasto 
WHERE nombre = 'Arriendo';

DELETE FROM categorias_gasto 
WHERE nombre = 'Mantenimiento';
