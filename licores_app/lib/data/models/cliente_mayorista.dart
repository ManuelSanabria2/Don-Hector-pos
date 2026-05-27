import 'model_helpers.dart';

class ClienteMayorista {
  const ClienteMayorista({
    required this.id,
    required this.nombre,
    this.nit,
    this.telefono,
    this.direccion,
    this.email,
    this.notas,
    this.activo,
    this.createdAt,
  });

  final String id;
  final String nombre;
  final String? nit;
  final String? telefono;
  final String? direccion;
  final String? email;
  final String? notas;
  final bool? activo;
  final DateTime? createdAt;

  factory ClienteMayorista.fromJson(Map<String, dynamic> json) {
    return ClienteMayorista(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      nit: json['nit'] as String?,
      telefono: json['telefono'] as String?,
      direccion: json['direccion'] as String?,
      email: json['email'] as String?,
      notas: json['notas'] as String?,
      activo: json['activo'] as bool?,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'nit': nit,
      'telefono': telefono,
      'direccion': direccion,
      'email': email,
      'notas': notas,
      'activo': activo,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
