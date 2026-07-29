-- ============================================================
-- MIGRATION: 202607110000_storage_bucket_productos_permitir_anon
-- El signInAnonymously() del cliente falla porque el proyecto tiene
-- deshabilitados los inicios de sesion anonimos (422 en /auth/v1/signup),
-- por lo que la app siempre opera con el rol 'anon', nunca 'authenticated'.
-- Igual que el resto de las tablas (RLS deshabilitado), se amplian las
-- policies de storage.objects para aceptar tambien el rol anon.
-- ============================================================
drop policy if exists "productos_img_insert" on storage.objects;
drop policy if exists "productos_img_update" on storage.objects;
drop policy if exists "productos_img_delete" on storage.objects;

create policy "productos_img_insert" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'productos');

create policy "productos_img_update" on storage.objects
  for update to anon, authenticated
  using (bucket_id = 'productos');

create policy "productos_img_delete" on storage.objects
  for delete to anon, authenticated
  using (bucket_id = 'productos');
