-- ============================================================
-- MIGRATION: 202607090002_storage_bucket_productos
-- Bucket público de Storage para las fotos de producto del menú
-- Turbo POS. Lectura pública por URL; escritura solo para el rol
-- authenticated (la app usa sesión anónima, que es authenticated).
-- Si los create policy fallan por ownership de storage.objects,
-- recrear las mismas policies desde Dashboard → Storage → Policies.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('productos', 'productos', true)
on conflict (id) do nothing;

create policy "productos_img_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'productos');

create policy "productos_img_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'productos');

create policy "productos_img_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'productos');

create policy "productos_img_select" on storage.objects
  for select to public
  using (bucket_id = 'productos');
