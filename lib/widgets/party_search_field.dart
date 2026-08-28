import 'package:flutter/material.dart';

import '../models/party_suggestion.dart';
import '../theme/app_theme.dart';

/// Sales/Purchase party field with a rich autocomplete dropdown.
class PartySearchField extends StatefulWidget {
  /// Filters [parties] for the autocomplete dropdown while typing.
  static Iterable<PartySuggestion> filterParties(
    List<PartySuggestion> parties,
    String query,
  ) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const Iterable.empty();
    return parties.where((p) => p.matches(trimmed)).take(24);
  }

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
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final List<PartySuggestion> parties;
  final String? helperText;
  final ValueChanged<PartySuggestion>? onSelected;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldSubmitted;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;

  @override
  State<PartySearchField> createState() => _PartySearchFieldState();
}

class _PartySearchFieldState extends State<PartySearchField> {
  FocusNode? _attachedFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusListener(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant PartySearchField oldWidget) {
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

  Iterable<PartySuggestion> _options(String query) {
    return PartySearchField.filterParties(widget.parties, query);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<PartySuggestion>(
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
          focusNode: widget.focusNode ?? focusNode,
          style: const TextStyle(fontSize: 14),
          textInputAction: TextInputAction.next,
          onTap: widget.onFocus,
          onFieldSubmitted: (_) {
            final typed = fieldController.text.trim();
            final exact = widget.parties
                .where((p) => p.isExactNameMatch(typed))
                .toList();
            if (exact.length == 1) {
              final match = exact.first;
              widget.controller.text = match.name;
              widget.onSelected?.call(match);
              widget.onChanged?.call(match.name);
            }
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
