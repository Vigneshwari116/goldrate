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
  });

  final String label;
  final TextEditingController controller;
  final Iterable<String> Function(String query) options;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) => options(value.text),
      onSelected: (selection) {
        controller.text = selection;
        onSelected?.call(selection);
        onChanged?.call(selection);
      },
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
          validator: validator,
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
