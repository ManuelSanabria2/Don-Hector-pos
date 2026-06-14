import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/cliente_mayorista.dart';
import '../../data/repositories/mayoristas_repository.dart';
import 'mayoristas_providers.dart';

class ClienteFormScreen extends ConsumerStatefulWidget {
  const ClienteFormScreen({this.cliente, super.key});

  final ClienteMayorista? cliente;

  @override
  ConsumerState<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends ConsumerState<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _nitController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _direccionController;
  late final TextEditingController _emailController;
  late final TextEditingController _notasController;
  bool _saving = false;

  ClienteMayorista? get _cliente => widget.cliente;

  @override
  void initState() {
    super.initState();
    final cliente = _cliente;
    _nombreController = TextEditingController(text: cliente?.nombre ?? '');
    _nitController = TextEditingController(text: cliente?.nit ?? '');
    _telefonoController = TextEditingController(text: cliente?.telefono ?? '');
    _direccionController = TextEditingController(
      text: cliente?.direccion ?? '',
    );
    _emailController = TextEditingController(text: cliente?.email ?? '');
    _notasController = TextEditingController(text: cliente?.notas ?? '');
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _nitController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _emailController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final cliente = ClienteMayorista(
      id: _cliente?.id ?? '',
      nombre: _nombreController.text.trim(),
      nit: _optional(_nitController.text),
      telefono: _optional(_telefonoController.text),
      direccion: _optional(_direccionController.text),
      email: _optional(_emailController.text),
      notas: _optional(_notasController.text),
      activo: _cliente?.activo ?? true,
    );

    try {
      await ref.read(mayoristasRepositoryProvider).upsertCliente(cliente);
      ref.invalidate(mayoristasClientesProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
      ),
      body: Form(
        key: _formKey,
        child: SafeArea(
          bottom: true,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el nombre';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nitController,
                decoration: const InputDecoration(labelText: 'NIT'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefonoController,
                decoration: const InputDecoration(labelText: 'Telefono'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _direccionController,
                decoration: const InputDecoration(labelText: 'Direccion'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notasController,
                decoration: const InputDecoration(labelText: 'Notas'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _optional(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
