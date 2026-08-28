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
  FocusNode? _attachedFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusListener(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant PartyAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusListener(oldWidget.focusNode);
      _attachFocusListener(widget.focusNode);
    }
  }

  @override
  void dispose() {
    _detachFocusListener(widget.focusNode);
    super.dispose();
  }

  void _attachFocusListener(FocusNode? node) {
    if (node == null || widget.onFocus == null) return;
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
      widget.onFocus?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) => widget.options(value.text),
      onSelected: (selection) {
        widget.controller.text = selection;
        widget.onSelected?.call(selection);
        widget.onChanged?.call(selection);
        widget.onFieldSubmitted?.call();
      },
      fieldViewBuilder: (context, fieldController, focusNode, onAutocompleteSubmit) {
        if (fieldController.text != widget.controller.text) {
          fieldController.text = widget.controller.text;
        }
        final node = widget.focusNode ?? focusNode;
        return TextFormField(
          controller: fieldController,
          focusNode: node,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
          validator: widget.validator,
          onTap: widget.onFocus,
          onFieldSubmitted: (_) {
            onAutocompleteSubmit();
            widget.onFieldSubmitted?.call();
          },
          onChanged: (value) {
            widget.controller.text = value;
            widget.onChanged?.call(value);
          },
          decoration: InputDecoration(
            label: Text(widget.label),
            helperText: widget.helperText,
            helperStyle: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }
}
