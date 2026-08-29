import 'package:flutter/material.dart';

import 'party_options_overlay.dart';

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
    this.onFieldSubmitted,
    this.onFocus,
    this.onFocusNodeReady,
  });

  final String label;
  final TextEditingController controller;
  final Iterable<String> Function(String query) options;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldSubmitted;
  final VoidCallback? onFocus;
  final ValueChanged<FocusNode>? onFocusNodeReady;

  @override
  State<PartyAutocompleteField> createState() => _PartyAutocompleteFieldState();
}

class _PartyAutocompleteFieldState extends State<PartyAutocompleteField> {
  FocusNode? _fieldFocusNode;

  @override
  void dispose() {
    _fieldFocusNode?.removeListener(_handleFocus);
    super.dispose();
  }

  void _bindFieldFocusNode(FocusNode node) {
    if (_fieldFocusNode == node) return;
    _fieldFocusNode?.removeListener(_handleFocus);
    _fieldFocusNode = node;
    node.addListener(_handleFocus);
    widget.onFocusNodeReady?.call(node);
  }

  void _handleFocus() {
    if (_fieldFocusNode?.hasFocus == true) {
      widget.onFocus?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      optionsBuilder: (value) => widget.options(value.text),
      onSelected: (selection) {
        widget.controller.text = selection;
        widget.onSelected?.call(selection);
        widget.onChanged?.call(selection);
        widget.onFieldSubmitted?.call();
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) return const SizedBox.shrink();
        return partyAutocompleteOptionsView(
          context: context,
          child: partyAutocompleteOptionsShell(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options.elementAt(index);
                return partyAutocompleteOptionTile(
                  onSelected: () => onSelected(option),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      fieldViewBuilder: (context, fieldController, focusNode, onAutocompleteSubmit) {
        _bindFieldFocusNode(focusNode);
        if (fieldController.text != widget.controller.text) {
          fieldController.text = widget.controller.text;
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
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
