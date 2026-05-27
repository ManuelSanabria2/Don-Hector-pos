class Categoria {
  const Categoria({required this.id, required this.nombre, this.createdAt});

  final String id;
  final String nombre;
  final DateTime? createdAt;

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
