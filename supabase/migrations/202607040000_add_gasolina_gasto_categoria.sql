-- Migration: Agregar categoría de gasto "Gasolina"
INSERT INTO categorias_gasto (nombre)
VALUES ('Gasolina')
ON CONFLICT (nombre) DO NOTHING;
