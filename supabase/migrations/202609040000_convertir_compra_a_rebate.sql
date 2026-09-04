-- ============================================================
-- MIGRATION: 202609040000_convertir_compra_a_rebate
--
-- Corrige una compra que se registró como pagada con plata cuando
-- en realidad se canjeó con el saldo de rebate del proveedor.
--
-- Existe para el caso en que anular y volver a registrar NO es
-- posible: anular_compra devuelve el stock, y si la mercancía ya se
-- vendió el stock actual queda por debajo y la anulación falla. Esta
-- función arregla solo el ORIGEN DE FONDOS y no toca stock, costos
-- ni detalle: la mercancía entró igual, lo que estaba mal era de
-- dónde salió la plata.
--
-- Deja la compra exactamente como si se hubiera registrado bien
-- desde el principio: metodo_pago = 'rebate' y su fila de canje en
-- rebates_proveedor, validada por el mismo trigger. Por eso anular
-- después sigue devolviendo el saldo sin nada especial.
-- ============================================================
create or replace function convertir_compra_a_rebate(
  p_compra_id uuid,
  p_notas     text default null
)
returns numeric
language plpgsql
security definer
as $$
declare
  v_proveedor_id uuid;
  v_metodo       text;
  v_total        numeric(12,3);
  v_fecha        date;
  v_anulado      boolean;
  v_pagos        numeric;
  v_saldo        numeric;
begin
  select proveedor_id, metodo_pago::text, total, fecha, anulado
    into v_proveedor_id, v_metodo, v_total, v_fecha, v_anulado
  from compras_inventario
  where id = p_compra_id
  for update;

  if not found then
    raise exception 'La compra especificada no existe.';
  end if;

  if v_anulado then
    raise exception 'La compra está anulada: no tiene sentido cambiarle el origen de fondos.';
  end if;

  if v_metodo = 'rebate' then
    raise exception 'Esta compra ya está registrada como canje de rebate.';
  end if;

  if v_proveedor_id is null then
    raise exception 'La compra no tiene proveedor, y un rebate siempre lo otorga uno. Asígnale el proveedor primero.';
  end if;

  if v_total <= 0 then
    raise exception 'Un canje de rebate debe tener un total mayor a cero.';
  end if;

  -- Un pago vivo es plata que SÍ salió de la caja. Convertir la
  -- compra la dejaría fuera de los reportes de efectivo y ese
  -- desembolso quedaría huérfano, así que se para aquí en vez de
  -- adivinar qué hacer con él.
  select coalesce(sum(monto), 0) into v_pagos
  from pagos_compras
  where compra_id = p_compra_id
    and anulado = false;

  if v_pagos > 0 then
    raise exception
      'La compra tiene % en pagos registrados. Anula esos pagos primero: si de verdad salió esa plata, la compra no se pagó solo con rebate.',
      v_pagos;
  end if;

  -- El canje conserva la fecha de la compra, no la de hoy: el saldo
  -- se consumió cuando llegó la mercancía.
  insert into rebates_proveedor (proveedor_id, fecha, tipo, monto, compra_id, notas)
  values (
    v_proveedor_id,
    v_fecha,
    'canje',
    v_total,
    p_compra_id,
    coalesce(p_notas, 'Canje corregido: la compra se había registrado como ' || v_metodo)
  );

  update compras_inventario
  set metodo_pago = 'rebate',
      -- Si venía como crédito, la deuda con el proveedor desaparece:
      -- se pagó con el saldo a favor, no queda nada por pagar.
      valor_deuda = 0,
      notas = coalesce(notas || ' | ', '') ||
              'CORREGIDA: pagada con rebate (antes ' || v_metodo || ')'
  where id = p_compra_id;

  select saldo_rebate_proveedor(v_proveedor_id) into v_saldo;
  return v_saldo;
end;
$$;
