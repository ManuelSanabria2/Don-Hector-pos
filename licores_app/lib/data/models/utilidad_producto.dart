import 'model_helpers.dart';
import 'producto.dart';

/// Utilidad acumulada de un producto en un rango de fechas.
///
/// [ingresos] es la suma de `cantidad * precio_unitario` de las líneas de
/// venta; no descuenta `ventas.descuento`, que es un descuento de cabecera y
/// no está atribuido a ninguna línea. Por eso la suma de [ingresos] de todos
/// los productos puede quedar por encima del total de ventas del mismo rango.
class UtilidadProducto {
  const UtilidadProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.ingresos,
    required this.costo,
  });

  final String productoId;
  final String nombre;
  final int unidades;
  final num ingresos;
  final num costo;

  num get utilidad => ingresos - costo;

  /// Margen sobre la venta, en porcentaje. Null si no hubo ingresos.
  double? get margen =>
      ingresos == 0 ? null : (utilidad / ingresos * 100).toDouble();

  bool get sinVentas => unidades == 0;
}

/// Agrupa las líneas de `detalle_ventas` por producto.
///
/// Todos los [productos] pedidos aparecen en el resultado, incluso los que no
/// se vendieron en el rango: se devuelven en ceros para que el usuario vea
/// explícitamente que no hubo movimiento, en vez de que la fila desaparezca.
///
/// El costo replica el `coalesce` de la función SQL `cogs_rango`: se usa el
/// costo histórico guardado en la línea y, si es null (ventas anteriores a la
/// migración que lo agregó), el costo actual del producto.
List<UtilidadProducto> agruparUtilidadPorProducto(
  List<Producto> productos,
  List<Map<String, dynamic>> lineas,
) {
  final unidades = <String, int>{};
  final ingresos = <String, num>{};
  final costos = <String, num>{};

  for (final producto in productos) {
    unidades[producto.id] = 0;
    ingresos[producto.id] = 0;
    costos[producto.id] = 0;
  }

  final costoActual = {
    for (final producto in productos) producto.id: producto.costo,
  };

  for (final linea in lineas) {
    final productoId = linea['producto_id'] as String?;
    if (productoId == null || !unidades.containsKey(productoId)) continue;

    final cantidad = parseInt(linea['cantidad']);
    final precio = parseNum(linea['precio_unitario']);
    final costoUnitario = linea['costo_unitario_historico'] == null
        ? (costoActual[productoId] ?? 0)
        : parseNum(linea['costo_unitario_historico']);

    unidades[productoId] = unidades[productoId]! + cantidad;
    ingresos[productoId] = ingresos[productoId]! + cantidad * precio;
    costos[productoId] = costos[productoId]! + cantidad * costoUnitario;
  }

  final resultado = [
    for (final producto in productos)
      UtilidadProducto(
        productoId: producto.id,
        nombre: producto.nombre,
        unidades: unidades[producto.id]!,
        ingresos: ingresos[producto.id]!,
        costo: costos[producto.id]!,
      ),
  ];

  resultado.sort((a, b) => b.utilidad.compareTo(a.utilidad));
  return resultado;
}
