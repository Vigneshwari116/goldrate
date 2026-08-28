import 'package:flutter/material.dart';

/// Searchable name field used on sales, purchase, voucher, and master screens.
class PartyAutocompleteField extends StatefulWidget {
  const PartyAutocompleteField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.helperText,
    this.validator,
    this.onSelected,
    this.onChanged,
    this.focusNode,
    this.onFieldSubmitted,
    this.onFocus,
  });

  final String label;
  final TextEditingController controller;
  final Iterable<String> Function(String query) options;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onFieldSubmitted;
  final VoidCallback? onFocus;

  @override
  State<PartyAutocompleteField> createState() => _PartyAutocompleteFieldState();
}

class _PartyAutocompleteFieldState extends State<PartyAutocompleteField> {
  late final SearchController _searchController;
  FocusNode? _attachedFocusNode;
  bool _syncingControllers = false;

  @override
  void initState() {
    super.initState();
    _searchController = SearchController();
    _setSearchText(widget.controller.text);
    _searchController.addListener(_onSearchTextChanged);
    widget.controller.addListener(_onWidgetTextChanged);
    _attachFocusListener(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant PartyAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusListener(oldWidget.focusNode);
      _attachFocusListener(widget.focusNode);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onWidgetTextChanged);
      widget.controller.addListener(_onWidgetTextChanged);
      _setSearchText(widget.controller.text);
    }
  }

  @override
  void dispose() {
    _detachFocusListener(widget.focusNode);
    _searchController.removeListener(_onSearchTextChanged);
    widget.controller.removeListener(_onWidgetTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _setSearchText(String value) {
    if (_searchController.text == value) return;
    _syncingControllers = true;
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
    _syncingControllers = false;
  }

  void _onWidgetTextChanged() {
    if (_syncingControllers) return;
    _setSearchText(widget.controller.text);
  }

  void _onSearchTextChanged() {
    if (_syncingControllers) return;
    final value = _searchController.text;
    if (widget.controller.text != value) {
      widget.controller.text = value;
    }
    widget.onChanged?.call(value);
  }

  void _attachFocusListener(FocusNode? node) {
    if (node == null) return;
    _attachedFocusNode = node;
    node.addListener(_handleFocus);
  }

  void _detachFocusListener(FocusNode? node) {
    if (node == null) return;
    node.removeListener(_handleFocus);
    if (_attachedFocusNode == node) {
      _attachedFocusNode = null;
    }
  }

  void _handleFocus() {
    if (_attachedFocusNode?.hasFocus == true) {
      _openSuggestions();
    }
  }

  void _openSuggestions() {
    widget.onFocus?.call();
    if (!_searchController.isOpen) {
      _searchController.openView();
    }
  }

  void _selectOption(String value) {
    _setSearchText(value);
    widget.controller.text = value;
    widget.onSelected?.call(value);
    widget.onChanged?.call(value);
    _searchController.closeView(value);
    widget.onFieldSubmitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      searchController: _searchController,
      viewConstraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
      builder: (context, controller) {
        return TextFormField(
          controller: controller,
          focusNode: widget.focusNode,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
          validator: widget.validator,
          onTap: _openSuggestions,
          onFieldSubmitted: (_) {
            controller.closeView(controller.text);
            widget.onFieldSubmitted?.call();
          },
          decoration: InputDecoration(
            label: Text(widget.label),
            helperText: widget.helperText,
            helperStyle: const TextStyle(fontSize: 11),
          ),
        );
      },
      suggestionsBuilder: (context, controller) {
        final matches = widget.options(controller.text).toList();
        if (matches.isEmpty) {
          return [
            const ListTile(
              dense: true,
              enabled: false,
              title: Text(
                'No saved names found',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ];
        }

        return [
          for (final option in matches)
            ListTile(
              dense: true,
              title: Text(
                option,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              onTap: () => _selectOption(option),
            ),
        ];
      },
    );
  }
}
