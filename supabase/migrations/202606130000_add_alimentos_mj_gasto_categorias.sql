-- Agregar nuevas categorías de gastos
INSERT INTO categorias_gasto (nombre)
VALUES 
  ('Alimentos'),
  ('MJ')
ON CONFLICT (nombre) DO NOTHING;
