import 'package:flutter/material.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../domain/models/nutrition_models.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';

typedef FoodSearchCallback = Future<FoodSearchResult> Function(String query,
    {int limit});

class FoodSearchPanel extends StatefulWidget {
  const FoodSearchPanel({
    super.key,
    required this.keyPrefix,
    required this.searchFoods,
    required this.onSelected,
    required this.onClose,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.initialQuery,
    this.autofocus = true,
    this.resultLimit = 10,
    this.closeKeySuffix = 'close',
  });

  final String keyPrefix;
  final FoodSearchCallback searchFoods;
  final ValueChanged<MealItem> onSelected;
  final VoidCallback onClose;
  final String? actionLabel;
  final IconData actionIcon;
  final String? initialQuery;
  final bool autofocus;
  final int resultLimit;
  final String closeKeySuffix;

  @override
  State<FoodSearchPanel> createState() => _FoodSearchPanelState();
}

class _FoodSearchPanelState extends State<FoodSearchPanel> {
  late final TextEditingController _queryController;
  List<MealItem> _results = const [];
  bool _isSearching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void didUpdateWidget(covariant FoodSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != null &&
        widget.initialQuery != _queryController.text) {
      _queryController.text = widget.initialQuery!;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FreshUnderlineTextField(
          fieldKey: ValueKey('${widget.keyPrefix}_field'),
          label: l10n.foodSearchHint,
          controller: _queryController,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          suffix: IconButton(
            key: ValueKey('${widget.keyPrefix}_submit'),
            onPressed: _isSearching ? null : _search,
            icon: _isSearching
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: FreshSpacing.sm),
          Text(
            _error!,
            key: ValueKey('${widget.keyPrefix}_message'),
            style: textTheme.bodySmall?.copyWith(color: palette.coral),
          ),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: FreshSpacing.md),
          for (var index = 0; index < _results.length; index++)
            InkWell(
              key: ValueKey('${widget.keyPrefix}_result_$index'),
              onTap: () => _select(_results[index]),
              borderRadius: BorderRadius.circular(FreshRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _results[index].name,
                            style: textTheme.bodyLarge?.copyWith(
                              color: palette.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: FreshSpacing.xs),
                          Text(
                            _foodSubtitle(_results[index]),
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey('${widget.keyPrefix}_result_button_$index'),
                      onPressed: () => _select(_results[index]),
                      icon: Icon(widget.actionIcon, size: 18),
                      label: Text(
                        widget.actionLabel ?? l10n.foodSearchAddAction,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('${widget.keyPrefix}_${widget.closeKeySuffix}'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
            label: Text(l10n.foodSearchHideSearch),
          ),
        ),
      ],
    );
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final result = await widget.searchFoods(query, limit: widget.resultLimit);
      if (!mounted) return;
      setState(() {
        _results = result.items.take(widget.resultLimit).toList();
        _error = _results.isEmpty ? context.l10n.foodSearchEmpty : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = context.l10n.foodSearchError;
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _select(MealItem item) {
    FocusScope.of(context).unfocus();
    widget.onSelected(item);
  }
}

String _foodSubtitle(MealItem item) {
  final quantity = _formatQuantity(item.quantity);
  final macros = '${_formatMacro(item.proteinGrams)}g P · '
      '${_formatMacro(item.carbsGrams)}g C · '
      '${_formatMacro(item.fatGrams)}g F';
  return '$quantity ${item.unit} · ${item.calories} Kcal · $macros';
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatMacro(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
