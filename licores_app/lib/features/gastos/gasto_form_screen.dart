import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/gasto.dart';
import '../../data/repositories/gastos_repository.dart';
import 'gastos_providers.dart';

class GastoFormScreen extends ConsumerStatefulWidget {
  const GastoFormScreen({super.key, this.gasto});
  final Gasto? gasto;

  @override
  ConsumerState<GastoFormScreen> createState() => _GastoFormScreenState();
}

class _GastoFormScreenState extends ConsumerState<GastoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descripcionCtrl;
  late TextEditingController _montoCtrl;
  late TextEditingController _notasCtrl;
  String? _categoriaId;
  late DateTime _fecha;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descripcionCtrl = TextEditingController(text: widget.gasto?.descripcion);
    _montoCtrl = TextEditingController(text: widget.gasto?.monto.toString());
    _notasCtrl = TextEditingController(text: widget.gasto?.notas);
    _categoriaId = widget.gasto?.categoriaId;
    _fecha = widget.gasto?.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_categoriaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione una categoría')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(gastosRepositoryProvider);
      
      final gasto = Gasto(
        id: widget.gasto?.id ?? '',
        descripcion: _descripcionCtrl.text.trim(),
        monto: num.parse(_montoCtrl.text.trim()),
        categoriaId: _categoriaId,
        fecha: _fecha,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
      );

      await repo.upsertGasto(gasto);
      
      ref.invalidate(gastosDelMesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasGastoProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.gasto == null ? 'Nuevo Gasto' : 'Editar Gasto'),
      ),
      body: categoriasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error al cargar categorías: $err')),
        data: (categorias) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _descripcionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _montoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monto (COP)',
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Requerido';
                    if (num.tryParse(v) == null) return 'Número inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  value: _categoriaId,
                  items: categorias.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text(c.nombre),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _categoriaId = val),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha'),
                  subtitle: Text(DateFormat('yyyy-MM-dd').format(_fecha)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _fecha = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notasCtrl,
                  decoration: const InputDecoration(labelText: 'Notas (Opcional)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _guardar,
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Guardar'),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}
