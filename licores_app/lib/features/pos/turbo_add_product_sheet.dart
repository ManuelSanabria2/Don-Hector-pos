import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/inventario_repository.dart';

/// Sheet del modo edición del Turbo POS para agregar productos del
/// inventario al menú. Permite agregar varios sin cerrarse; el caller
/// re-sincroniza el menú al cerrar.
class TurboAddProductSheet extends ConsumerStatefulWidget {
  const TurboAddProductSheet({super.key});

  @override
  ConsumerState<TurboAddProductSheet> createState() =>
      _TurboAddProductSheetState();
}

class _TurboAddProductSheetState extends ConsumerState<TurboAddProductSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Producto> _resultados = [];
  bool _loading = true;
  final Set<String> _agregados = {};
  final Set<String> _agregando = {};

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(value));
  }

  Future<void> _buscar(String query) async {
    setState(() => _loading = true);
    try {
      final productos = await ref
          .read(inventarioRepositoryProvider)
          .getProductos(busqueda: query);
      if (!mounted) return;
      setState(() {
        _resultados = productos
            .where((p) => p.enTurbo != true || _agregados.contains(p.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los productos')),
      );
    }
  }

  Future<void> _agregar(Producto producto) async {
    if (_agregados.contains(producto.id) || _agregando.contains(producto.id)) {
      return;
    }
    setState(() => _agregando.add(producto.id));
    try {
      await ref
          .read(inventarioRepositoryProvider)
          .setProductoTurbo(producto.id, true);
      if (!mounted) return;
      setState(() => _agregados.add(producto.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo agregar ${producto.nombre}')),
      );
    } finally {
      if (mounted) setState(() => _agregando.remove(producto.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.add_circle_outline,
                      color: AppColors.ambar, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Agregar al menú turbo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _resultados.isEmpty
                        ? const Center(
                            child: Text(
                              'Sin productos para agregar.',
                              style: TextStyle(color: AppColors.blancoD),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _resultados.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFF262626),
                            ),
                            itemBuilder: (context, index) {
                              final producto = _resultados[index];
                              final agregado =
                                  _agregados.contains(producto.id);
                              final agregando =
                                  _agregando.contains(producto.id);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                title: Text(
                                  producto.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${formatCOP(producto.precioPublico.toDouble())}'
                                  '  ·  ${producto.stockActual} uds',
                                  style: const TextStyle(
                                    color: AppColors.blancoD,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: agregado
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.greenAccent)
                                    : agregando
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : FilledButton.tonal(
                                            onPressed: () =>
                                                _agregar(producto),
                                            child: const Text('Agregar'),
                                          ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
