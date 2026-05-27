-- Añadir la categoría Cigarrillos si no existe
INSERT INTO categorias (nombre) 
VALUES ('Cigarrillos')
ON CONFLICT (nombre) DO NOTHING;
