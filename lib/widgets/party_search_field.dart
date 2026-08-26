import 'package:flutter/material.dart';

import '../models/party_suggestion.dart';
import '../theme/app_theme.dart';

/// Sales/Purchase party field with a rich autocomplete dropdown.
class PartySearchField extends StatefulWidget {
  const PartySearchField({
    super.key,
    required this.label,
    required this.controller,
    required this.parties,
    this.helperText,
    this.onSelected,
    this.onChanged,
    this.onFieldSubmitted,
    this.onFocus,
  });

  final String label;
  final TextEditingController controller;
  final List<PartySuggestion> parties;
  final String? helperText;
  final ValueChanged<PartySuggestion>? onSelected;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldSubmitted;
  final VoidCallback? onFocus;

  @override
  State<PartySearchField> createState() => _PartySearchFieldState();
}

class _PartySearchFieldState extends State<PartySearchField> {
  Iterable<PartySuggestion> _options(String query) {
    final matches = widget.parties.where((p) => p.matches(query));
    return query.trim().isEmpty ? matches.take(24) : matches.take(24);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<PartySuggestion>(
      key: ValueKey('${widget.label}-${widget.parties.length}'),
      displayStringForOption: (option) => option.name,
      optionsBuilder: (value) => _options(value.text),
      onSelected: (selection) {
        widget.controller.text = selection.name;
        widget.onSelected?.call(selection);
        widget.onChanged?.call(selection.name);
        widget.onFieldSubmitted?.call();
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        option.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        option.detailLine,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.mutedBlue,
                        ),
                      ),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, fieldController, focusNode, onAutocompleteSubmit) {
        if (fieldController.text != widget.controller.text) {
          fieldController.text = widget.controller.text;
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
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
