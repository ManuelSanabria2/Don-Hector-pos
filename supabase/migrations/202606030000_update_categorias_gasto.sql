-- Actualizar los nombres de las categorías de gastos
UPDATE categorias_gasto 
SET nombre = 'Personales' 
WHERE nombre = 'Personal / Nómina';

UPDATE categorias_gasto 
SET nombre = 'Suministros' 
WHERE nombre = 'Suministros y empaques';
