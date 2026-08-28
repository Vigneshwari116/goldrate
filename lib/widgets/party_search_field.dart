import 'package:flutter/material.dart';

import '../models/party_suggestion.dart';
import '../theme/app_theme.dart';

/// Sales/Purchase party field with a rich autocomplete dropdown.
class PartySearchField extends StatefulWidget {
  /// Filters [parties] for the autocomplete dropdown.
  static Iterable<PartySuggestion> filterParties(
    List<PartySuggestion> parties,
    String query, {
    bool includeAllWhenEmpty = true,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return includeAllWhenEmpty ? parties.take(24) : const Iterable.empty();
    }
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
  void didUpdateWidget(covariant PartySearchField oldWidget) {
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

  void _selectParty(PartySuggestion party) {
    _setSearchText(party.name);
    widget.controller.text = party.name;
    widget.onSelected?.call(party);
    widget.onChanged?.call(party.name);
    _searchController.closeView(party.name);
    widget.onFieldSubmitted?.call();
  }

  Iterable<PartySuggestion> _matches(String query) {
    return PartySearchField.filterParties(widget.parties, query);
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
          onTap: _openSuggestions,
          onFieldSubmitted: (_) {
            final typed = controller.text.trim();
            final exact = widget.parties
                .where((p) => p.isExactNameMatch(typed))
                .toList();
            if (exact.length == 1) {
              _selectParty(exact.first);
              return;
            }
            controller.closeView(typed);
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
        final matches = _matches(controller.text).toList();
        if (matches.isEmpty) {
          return [
            const ListTile(
              dense: true,
              enabled: false,
              title: Text(
                'No saved parties found',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ];
        }

        return [
          for (final party in matches)
            ListTile(
              dense: true,
              title: Text(
                party.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                party.detailLine,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.mutedBlue,
                ),
              ),
              onTap: () => _selectParty(party),
            ),
        ];
      },
    );
  }
}
