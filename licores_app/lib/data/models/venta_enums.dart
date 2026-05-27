enum TipoVenta {
  publico('publico'),
  mayorista('mayorista');

  const TipoVenta(this.value);

  final String value;

  static TipoVenta fromJson(Object? value) {
    return TipoVenta.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TipoVenta.publico,
    );
  }
}

enum MetodoPago {
  efectivo('efectivo'),
  nequi('nequi'),
  daviplata('daviplata'),
  transferencia('transferencia'),
  otro('otro');

  const MetodoPago(this.value);

  final String value;

  static MetodoPago fromJson(Object? value) {
    return MetodoPago.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MetodoPago.efectivo,
    );
  }
}

enum EstadoVenta {
  completada('completada'),
  anulada('anulada');

  const EstadoVenta(this.value);

  final String value;

  static EstadoVenta fromJson(Object? value) {
    return EstadoVenta.values.firstWhere(
      (item) => item.value == value,
      orElse: () => EstadoVenta.completada,
    );
  }
}

enum EstadoCobro {
  pendiente('pendiente'),
  parcial('parcial'),
  pagado('pagado');

  const EstadoCobro(this.value);

  final String value;

  static EstadoCobro fromJson(Object? value) {
    return EstadoCobro.values.firstWhere(
      (item) => item.value == value,
      orElse: () => EstadoCobro.pendiente,
    );
  }
}
