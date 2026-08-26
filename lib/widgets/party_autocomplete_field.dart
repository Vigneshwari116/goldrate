import 'package:flutter/material.dart';

/// Searchable name field used on sales, purchase, voucher, and master screens.
class PartyAutocompleteField extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) => options(value.text),
      onSelected: (selection) {
        controller.text = selection;
        onSelected?.call(selection);
        onChanged?.call(selection);
        onFieldSubmitted?.call();
      },
      fieldViewBuilder: (context, fieldController, focusNode, onAutocompleteSubmit) {
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        final node = this.focusNode ?? focusNode;
        return TextFormField(
          controller: fieldController,
          focusNode: node,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
          validator: validator,
          onFieldSubmitted: (_) {
            onAutocompleteSubmit();
            this.onFieldSubmitted?.call();
          },
          onChanged: (value) {
            controller.text = value;
            onChanged?.call(value);
          },
          decoration: InputDecoration(
            label: Text(label),
            helperText: helperText,
            helperStyle: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }
}
