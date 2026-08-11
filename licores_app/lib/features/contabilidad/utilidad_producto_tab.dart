import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/producto.dart';
import '../../data/models/utilidad_producto.dart';
import '../../data/repositories/inventario_repository.dart';
import 'contabilidad_providers.dart';

/// Pestaña de Contabilidad que muestra la utilidad de la última semana de los
/// productos que el usuario elija, para decidir qué conviene reponer.
///
/// No es un [Scaffold]: se monta dentro del TabBarView de ContabilidadScreen.
class UtilidadProductoTab extends ConsumerWidget {
  const UtilidadProductoTab({super.key});

  Future<void> _seleccionarProductos(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final seleccionados = ref.read(utilidadProductosSeleccionadosProvider);
    final resultado = await showModalBottomSheet<List<Producto>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.superficie,
      builder: (_) => _SelectorProductosSheet(iniciales: seleccionados),
    );
    if (resultado != null) {
      ref.read(utilidadProductosSeleccionadosProvider.notifier).state =
          resultado;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seleccionados = ref.watch(utilidadProductosSeleccionadosProvider);
    final utilidadAsync = ref.watch(utilidadPorProductoSemanaProvider);
    final rango = rangoSemanaUtilidad();
    final formato = DateFormat('dd/MM');

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(utilidadPorProductoSemanaProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_outlined,
                  size: 18, color: AppColors.blancoD),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Últimos $diasSemanaUtilidad días '
                  '(${formato.format(rango.start)} - ${formato.format(rango.end)})',
                  style: const TextStyle(color: AppColors.blancoD),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _seleccionarProductos(context, ref),
                icon: const Icon(Icons.checklist_outlined),
                label: Text(
                  seleccionados.isEmpty
                      ? 'Elegir productos'
                      : 'Elegir (${seleccionados.length})',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (seleccionados.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final producto in seleccionados)
                  Chip(
                    label: Text(producto.nombre),
                    onDeleted: () {
                      ref
                              .read(utilidadProductosSeleccionadosProvider.notifier)
                              .state =
                          seleccionados
                              .where((p) => p.id != producto.id)
                              .toList();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (seleccionados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'Elige uno o varios productos para ver\n'
                  'cuánta utilidad dejaron esta semana.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.blancoD),
                ),
              ),
            )
          else
            utilidadAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No se pudo calcular la utilidad:\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.rojo),
                  ),
                ),
              ),
              data: (filas) {
                if (filas.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    _TotalUtilidadCard(filas: filas),
                    const SizedBox(height: 16),
                    for (final fila in filas) _ProductoUtilidadCard(fila: fila),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TotalUtilidadCard extends StatelessWidget {
  const _TotalUtilidadCard({required this.filas});

  final List<UtilidadProducto> filas;

  @override
  Widget build(BuildContext context) {
    final unidades = filas.fold<int>(0, (sum, f) => sum + f.unidades);
    final ingresos = filas.fold<num>(0, (sum, f) => sum + f.ingresos);
    final costo = filas.fold<num>(0, (sum, f) => sum + f.costo);
    final utilidad = ingresos - costo;

    return Card(
      color: AppColors.superficie2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Utilidad total de la selección',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.blancoD),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.cop(utilidad),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: utilidad >= 0 ? AppColors.verde : AppColors.rojo,
                  ),
            ),
            const SizedBox(height: 12),
            _MetricasRow(unidades: unidades, ingresos: ingresos, costo: costo),
          ],
        ),
      ),
    );
  }
}

class _ProductoUtilidadCard extends StatelessWidget {
  const _ProductoUtilidadCard({required this.fila});

  final UtilidadProducto fila;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.superficie,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fila.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.blanco,
                    ),
                  ),
                ),
                Text(
                  CurrencyFormatter.cop(fila.utilidad),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: fila.utilidad >= 0 ? AppColors.verde : AppColors.rojo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (fila.sinVentas)
              const Text(
                'Sin ventas en el período',
                style: TextStyle(color: AppColors.gris, fontSize: 13),
              )
            else
              _MetricasRow(
                unidades: fila.unidades,
                ingresos: fila.ingresos,
                costo: fila.costo,
              ),
          ],
        ),
      ),
    );
  }
}

/// Trío de métricas (unidades / ingresos / costo) que acompaña a la utilidad.
class _MetricasRow extends StatelessWidget {
  const _MetricasRow({
    required this.unidades,
    required this.ingresos,
    required this.costo,
  });

  final int unidades;
  final num ingresos;
  final num costo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Metrica(titulo: 'Unidades', valor: '$unidades'),
        _Metrica(titulo: 'Ingresos', valor: CurrencyFormatter.cop(ingresos)),
        _Metrica(titulo: 'Costo', valor: CurrencyFormatter.cop(costo)),
      ],
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: AppColors.gris, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: const TextStyle(color: AppColors.blanco, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Hoja de selección múltiple de productos, con buscador por nombre o código
/// de barras. Devuelve la lista elegida al cerrarse con "Listo".
class _SelectorProductosSheet extends ConsumerStatefulWidget {
  const _SelectorProductosSheet({required this.iniciales});

  final List<Producto> iniciales;

  @override
  ConsumerState<_SelectorProductosSheet> createState() =>
      _SelectorProductosSheetState();
}

class _SelectorProductosSheetState
    extends ConsumerState<_SelectorProductosSheet> {
  final _searchCtrl = TextEditingController();
  final _seleccionados = <String, Producto>{};
  List<Producto> _todos = [];
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    for (final producto in widget.iniciales) {
      _seleccionados[producto.id] = producto;
    }
    _cargarProductos();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final lista = await ref.read(inventarioRepositoryProvider).getProductos();
      lista.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _todos = lista;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  List<Producto> get _visibles {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _todos;
    return _todos
        .where((p) =>
            p.nombre.toLowerCase().contains(query) ||
            (p.codigoBarras?.toLowerCase().contains(query) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Productos a comparar',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre o código de barras',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(child: Text('Error: $_error'))
                    : visibles.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No se encontraron productos'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visibles.length,
                            itemBuilder: (context, idx) {
                              final producto = visibles[idx];
                              final marcado =
                                  _seleccionados.containsKey(producto.id);
                              return CheckboxListTile(
                                value: marcado,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  producto.nombre,
                                  style: const TextStyle(
                                    color: AppColors.blanco,
                                  ),
                                ),
                                subtitle: Text(
                                  'Stock: ${producto.stockActual}',
                                  style: const TextStyle(
                                    color: AppColors.blancoD,
                                    fontSize: 13,
                                  ),
                                ),
                                onChanged: (valor) {
                                  setState(() {
                                    if (valor == true) {
                                      _seleccionados[producto.id] = producto;
                                    } else {
                                      _seleccionados.remove(producto.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _seleccionados.values.toList()),
              child: Text('Listo (${_seleccionados.length})'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
