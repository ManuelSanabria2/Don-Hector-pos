class CategoriaGasto {
  const CategoriaGasto({required this.id, required this.nombre});

  final String id;
  final String nombre;

  factory CategoriaGasto.fromJson(Map<String, dynamic> json) {
    return CategoriaGasto(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'nombre': nombre};
  }
}
