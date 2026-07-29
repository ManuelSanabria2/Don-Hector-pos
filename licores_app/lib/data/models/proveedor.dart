import 'model_helpers.dart';

class Proveedor {
  const Proveedor({
    required this.id,
    required this.nombre,
    this.telefono,
    this.notas,
    this.activo = true,
    this.createdAt,
  });

  final String id;
  final String nombre;
  final String? telefono;
  final String? notas;
  final bool activo;
  final DateTime? createdAt;

  factory Proveedor.fromJson(Map<String, dynamic> json) {
    return Proveedor(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      telefono: json['telefono'] as String?,
      notas: json['notas'] as String?,
      activo: json['activo'] as bool? ?? true,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'notas': notas,
      'activo': activo,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
