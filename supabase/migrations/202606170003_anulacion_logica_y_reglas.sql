-- ============================================================
-- 1. Anulación Lógica de Ventas
-- ============================================================

create or replace function anular_venta(p_venta_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
as $$
declare
  v_item record;
  v_stock_antes integer;
  v_stock_despues integer;
  v_estado_actual estado_venta;
begin
  -- Obtener el estado actual de la venta con bloqueo para evitar condiciones de carrera
  select estado into v_estado_actual from ventas where id = p_venta_id for update;
  
  if v_estado_actual is null then
    raise exception 'La venta especificada no existe.';
  end if;
  if v_estado_actual = 'anulada' then
    raise exception 'La venta ya está anulada.';
  end if;

  -- Revertir el stock de cada producto de la venta
  for v_item in
    select producto_id, cantidad from detalle_ventas where venta_id = p_venta_id
  loop
    -- Bloquear producto para actualizar el stock
    select stock_actual into v_stock_antes from productos where id = v_item.producto_id for update;
    
    update productos 
    set stock_actual = stock_actual + v_item.cantidad
    where id = v_item.producto_id 
    returning stock_actual into v_stock_despues;
    
    -- Registrar movimiento de stock
    insert into movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, referencia_id)
    values (v_item.producto_id, 'entrada'::tipo_movimiento, v_item.cantidad, v_stock_antes, v_stock_despues, 'anulacion_venta', p_venta_id);
  end loop;

  -- Actualizar el estado de la venta
  update ventas
  set estado = 'anulada', 
      notas = coalesce(notas || ' | ', '') || 'ANULADA: ' || coalesce(p_motivo, 'sin motivo')
  where id = p_venta_id;
end;
$$;

-- ============================================================
-- 2. Anulación Lógica de Gastos
-- ============================================================

alter table gastos add column if not exists anulado boolean not null default false;

-- ============================================================
-- 3. Impedir Sobrepago a Nivel de Base de Datos
-- ============================================================

create or replace function validar_pago_no_excede_saldo()
returns trigger as $$
declare
  v_saldo_actual numeric;
begin
  select saldo into v_saldo_actual from cobros_mayoristas where id = new.cobro_id;
  if new.monto > v_saldo_actual then
    raise exception 'El pago (%) excede el saldo pendiente (%)', new.monto, v_saldo_actual;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists pago_no_excede_saldo on pagos_mayoristas;
create trigger pago_no_excede_saldo
  before insert on pagos_mayoristas
  for each row execute function validar_pago_no_excede_saldo();

-- ============================================================
-- 4. Asegurar ajustar_stock con bloqueo y validación de stock
-- ============================================================

create or replace function ajustar_stock(
  p_producto_id uuid, p_cantidad integer, p_tipo text, p_motivo text
) returns void as $$
declare
  v_stock_antes integer;
  v_stock_despues integer;
begin
  -- Obtener stock con bloqueo para evitar race conditions
  select stock_actual into v_stock_antes from productos where id = p_producto_id for update;
  if not found then
    raise exception 'Producto con ID % no encontrado', p_producto_id;
  end if;

  if p_tipo <> 'entrada' and p_tipo <> 'salida' then
    raise exception 'Tipo de movimiento invalido: %. Debe ser "entrada" o "salida"', p_tipo;
  end if;

  if p_tipo = 'salida' and v_stock_antes < p_cantidad then
    raise exception 'Stock insuficiente: hay % unidades, se intentan retirar %', v_stock_antes, p_cantidad;
  end if;

  if p_tipo = 'entrada' then
    update productos set stock_actual = stock_actual + p_cantidad where id = p_producto_id returning stock_actual into v_stock_despues;
  else
    update productos set stock_actual = stock_actual - p_cantidad where id = p_producto_id returning stock_actual into v_stock_despues;
  end if;

  insert into movimientos_stock (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo)
  values (p_producto_id, p_tipo::tipo_movimiento, p_cantidad, v_stock_antes, v_stock_despues, p_motivo);
end;
$$ language plpgsql security definer;
