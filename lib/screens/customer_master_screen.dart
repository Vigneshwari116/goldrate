import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../util/field_advance.dart';
import '../util/focus_chain.dart';
import '../util/screen_activation.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/material_tile_card.dart';
import '../widgets/party_autocomplete_field.dart';

class _PartySummary {
  final String name;
  final String mobile;
  final String city;
  final double rupees;
  final double grams;
  final List<Map<String, dynamic>> entries;

  _PartySummary({
    required this.name,
    required this.mobile,
    required this.city,
    required this.rupees,
    required this.grams,
    required this.entries,
  });
}

List<_PartySummary> _buildSummaries(
    List<Map<String, dynamic>> rows,
    ) {
  final grouped = <String, List<Map<String, dynamic>>>{};

  for (final row in rows) {
    final name = (row['name'] ?? '').toString().trim();

    if (name.isEmpty) continue;

    grouped.putIfAbsent(name, () => []).add(row);
  }

  final summaries = <_PartySummary>[];

  grouped.forEach((name, entries) {
    double rupees = 0;
    double grams = 0;
    String mobile = '';
    String city = '';

    for (final e in entries) {
      final cr =
          double.tryParse((e['cr'] ?? '0').toString()) ?? 0;
      final dr =
          double.tryParse((e['dr'] ?? '0').toString()) ?? 0;

      final unit =
      (e['balanceUnit'] ?? 'RUPEES').toString().toUpperCase();

      final net = dr - cr;

      if (unit == 'GRAMS') {
        grams += net;
      } else {
        rupees += net;
      }

      if (mobile.isEmpty) {
        final value = (e['mobile'] ?? '').toString().trim();
        if (value.isNotEmpty) {
          mobile = value;
        }
      }

      if (city.isEmpty) {
        final value = (e['city'] ?? '').toString().trim();
        if (value.isNotEmpty) {
          city = value;
        }
      }
    }

    summaries.add(
      _PartySummary(
        name: name,
        mobile: mobile,
        city: city,
        rupees: rupees,
        grams: grams,
        entries: entries,
      ),
    );
  });

  summaries.sort(
        (a, b) => a.name.toLowerCase().compareTo(
      b.name.toLowerCase(),
    ),
  );

  return summaries;
}

class CustomerMasterScreen extends StatefulWidget {
  const CustomerMasterScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<CustomerMasterScreen> createState() =>
      _CustomerMasterScreenState();
}

class _CustomerMasterScreenState extends State<CustomerMasterScreen>
    with FocusAdvanceMixin, ScreenActivationMixin<CustomerMasterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _cityController = TextEditingController();
  final _pureWeightController = TextEditingController();
  final _goldWeightController = TextEditingController();
  final _narrationController = TextEditingController();
  final _searchController = TextEditingController();

  FocusNode? _nameFocus;
  final _mobileFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _pureWeightFocus = FocusNode();
  final _goldWeightFocus = FocusNode();
  final _narrationFocus = FocusNode();
  final _saveFocus = FocusNode();

  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  List<_PartySummary> _summaries = [];

  bool _loading = true;
  bool _saving = false;

  static final RegExp _mobileRegex =
  RegExp(r'^[6-9]\d{9}$');

  static final RegExp _numberRegex =
  RegExp(r'^\d+(\.\d+)?$');

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_applySearch);

    loadCustomers();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(CustomerMasterScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    loadCustomers();
  }

  @override
  void dispose() {
    _mobileFocus.dispose();
    _cityFocus.dispose();
    _pureWeightFocus.dispose();
    _goldWeightFocus.dispose();
    _narrationFocus.dispose();
    _saveFocus.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _cityController.dispose();
    _pureWeightController.dispose();
    _goldWeightController.dispose();
    _narrationController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  Future<void> loadCustomers() async {
    try {
      final data =
      await DatabaseHelper.instance.getCustomers();

      if (!mounted) return;

      customers = data;
      _applySearch();

      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(
        'Could not load customers.\n\n$e',
      );
    }
  }

  void _applySearch() {
    final query =
    _searchController.text.trim().toLowerCase();

    final filtered = query.isEmpty
        ? List<Map<String, dynamic>>.from(customers)
        : customers.where((c) {
      final name =
      (c['name'] ?? '').toString().toLowerCase();

      final mobile =
      (c['mobile'] ?? '').toString().toLowerCase();

      return name.contains(query) ||
          mobile.contains(query);
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredCustomers = filtered;
      _summaries = _buildSummaries(filtered);
    });
  }

  List<String> get _allNames =>
      _buildSummaries(customers).map((s) => s.name).toList();

  Iterable<String> _nameOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return const Iterable.empty();
    return _allNames.where((n) => n.toLowerCase().contains(lower)).take(12);
  }

  Iterable<String> _searchOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _allNames.take(12);
    return _allNames.where((name) {
      if (name.toLowerCase().contains(lower)) return true;
      final match = _buildSummaries(customers)
          .where((s) => s.name == name)
          .toList();
      if (match.isEmpty) return false;
      return match.first.mobile.toLowerCase().contains(lower);
    }).take(12);
  }

  void _focusNext(FocusNode next) {
    final controller = switch (next) {
      _ when next == _mobileFocus => _mobileController,
      _ when next == _cityFocus => _cityController,
      _ when next == _pureWeightFocus => _pureWeightController,
      _ when next == _goldWeightFocus => _goldWeightController,
      _ when next == _narrationFocus => _narrationController,
      _ => null,
    };
    FocusChain.focus(next, controller: controller);
  }

  void _bindNameFocus(FocusNode node) {
    _nameFocus = node;
  }

  void _onNameChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _nameFocus == null) return;

    advanceWhenIdle(
      value: trimmed,
      from: _nameFocus!,
      when: (v) => v.trim().length >= 2,
      to: _mobileFocus,
      toController: _mobileController,
    );
  }

  void _onMobileChanged(String value) {
    advanceWhenComplete(
      value: value,
      from: _mobileFocus,
      isComplete: FieldComplete.mobile,
      to: _cityFocus,
      toController: _cityController,
    );
  }

  void _onCityChanged(String value) {
    advanceWhenIdle(
      value: value,
      from: _cityFocus,
      when: (v) => v.trim().length >= 2,
      to: _pureWeightFocus,
      toController: _pureWeightController,
    );
  }

  void _onPureWeightChanged(String value) {
    advanceWhenComplete(
      value: value,
      from: _pureWeightFocus,
      isComplete: FieldComplete.masterWeight,
      to: _goldWeightFocus,
      toController: _goldWeightController,
    );
    advanceWhenIdle(
      value: value,
      from: _pureWeightFocus,
      when: (v) => RegExp(r'^\d+$').hasMatch(v.trim()),
      to: _goldWeightFocus,
      toController: _goldWeightController,
    );
  }

  void _onGoldWeightChanged(String value) {
    advanceWhenComplete(
      value: value,
      from: _goldWeightFocus,
      isComplete: FieldComplete.masterWeight,
      to: _narrationFocus,
      toController: _narrationController,
    );
    advanceWhenIdle(
      value: value,
      from: _goldWeightFocus,
      when: (v) => RegExp(r'^\d+$').hasMatch(v.trim()),
      to: _narrationFocus,
      toController: _narrationController,
    );
  }

  void _onNarrationChanged(String value) {
    advanceWhenIdle(
      value: value,
      from: _narrationFocus,
      when: (v) => v.trim().isNotEmpty,
      action: () => FocusChain.focus(_saveFocus),
    );
  }

  void _prefillOpeningBalance(_PartySummary summary) {
    if (summary.grams.abs() > 0.0005) {
      _pureWeightController.text = summary.grams.toStringAsFixed(3);
    } else {
      _pureWeightController.clear();
    }

    double goldGross = 0;
    for (final e in summary.entries) {
      final gross =
          double.tryParse((e['drGross'] ?? '0').toString()) ?? 0;
      if (gross.abs() > goldGross.abs()) goldGross = gross;
    }
    if (goldGross.abs() > 0.0005) {
      _goldWeightController.text = goldGross.toStringAsFixed(3);
    } else {
      _goldWeightController.clear();
    }
  }

  void _prefillFromExistingName(String name) {
    for (final summary in _buildSummaries(customers)) {
      if (summary.name == name) {
        _mobileController.text = summary.mobile;
        _cityController.text = summary.city;
        _prefillOpeningBalance(summary);
        FocusChain.focusNextFrame(_mobileFocus, controller: _mobileController);
        return;
      }
    }
    _pureWeightController.clear();
    _goldWeightController.clear();
    FocusChain.focusNextFrame(_mobileFocus, controller: _mobileController);
  }

  void _clearForm() {
    _nameController.clear();
    _mobileController.clear();
    _cityController.clear();
    _pureWeightController.clear();
    _goldWeightController.clear();
    _narrationController.clear();
    _formKey.currentState?.reset();
  }

  // ============================================================
  // SAVE CUSTOMER
  // ============================================================

  Future<void> saveCustomer() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final now = DateTime.now();

      final date =
      DateFormat('dd-MM-yyyy').format(now);

      final time =
      DateFormat('hh:mm a').format(now);

      final name =
      _nameController.text.trim();

      final mobile =
      _mobileController.text.trim();

      final city =
      _cityController.text.trim();

      final pureText = _pureWeightController.text.trim();
      final goldText = _goldWeightController.text.trim();
      final pureVal =
          pureText.isEmpty ? 0.0 : double.tryParse(pureText) ?? 0.0;
      final goldVal =
          goldText.isEmpty ? 0.0 : double.tryParse(goldText) ?? 0.0;

      final cr = pureVal < 0 ? pureVal.abs().toStringAsFixed(3) : '0';
      final dr = pureVal > 0 ? pureVal.toStringAsFixed(3) : '0';
      final gross = goldVal > 0 ? goldVal.toStringAsFixed(3) : '0';
      final net = '0';

      final narration =
      _narrationController.text.trim();

      final record = <String, dynamic>{
        'name': name,
        'mobile': mobile,
        'city': city,
        'cr': cr,
        'dr': dr,
        'drGross': gross,
        'drNet': net,
        'narration': narration,
        'balanceUnit': 'GRAMS',
        'billRef': '',
        'date': date,
        'time': time,
      };

      debugPrint(
        'CUSTOMER INSERT: $record',
      );

      final id =
      await DatabaseHelper.instance.insertCustomer(
        record,
      );

      debugPrint(
        'CUSTOMER INSERTED ID: $id',
      );

      if (!mounted) return;

      _clearForm();

      await loadCustomers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer entry saved successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'CUSTOMER SAVE ERROR: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      _showError(
        'Customer could not be saved.\n\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _confirmDelete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Entry'),
          content: const Text(
            'Are you sure you want to delete this record?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await DatabaseHelper.instance.deleteCustomer(id);

      await loadCustomers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer entry deleted'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Could not delete customer.\n\n$e',
      );
    }
  }

  String _entryLine(Map<String, dynamic> e) {
    final cr =
        double.tryParse((e['cr'] ?? '0').toString()) ?? 0;

    final dr =
        double.tryParse((e['dr'] ?? '0').toString()) ?? 0;

    final unit =
    (e['balanceUnit'] ?? 'RUPEES')
        .toString()
        .toUpperCase();

    final unitLabel =
    unit == 'GRAMS' ? 'g' : '₹';

    if (dr > 0) {
      return 'DR $unitLabel${dr.toStringAsFixed(2)}';
    }

    if (cr > 0) {
      return 'CR $unitLabel${cr.toStringAsFixed(2)}';
    }

    return 'No balance';
  }

  void _showPartyDetails(_PartySummary summary) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            summary.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (summary.mobile.isNotEmpty)
                    _detailRow(
                      'Mobile',
                      summary.mobile,
                    ),
                  if (summary.city.isNotEmpty)
                    _detailRow(
                      'City',
                      summary.city,
                    ),
                  const Divider(),
                  Text(
                    _outstandingLine(summary),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  const Text(
                    'ENTRIES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedBlue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...summary.entries.map(
                        (e) => _buildEntryTile(e),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEntryTile(
      Map<String, dynamic> e,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  _entryLine(e),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((e['narration'] ?? '')
                    .toString()
                    .isNotEmpty)
                  Text(
                    e['narration'].toString(),
                    style: const TextStyle(
                      fontSize: 11.5,
                    ),
                  ),
                Text(
                  '${e['date'] ?? ''} ${e['time'] ?? ''}'
                      '${(e['billRef'] ?? '').toString().isNotEmpty ? '  •  ${e['billRef']}' : ''}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete,
              size: 16,
              color: Colors.redAccent,
            ),
            padding: EdgeInsets.zero,
            constraints:
            const BoxConstraints(),
            onPressed: () async {
              Navigator.pop(context);

              final id =
              int.tryParse(
                e['id'].toString(),
              );

              if (id != null) {
                await _confirmDelete(id);
              }
            },
          ),
        ],
      ),
    );
  }

  String _outstandingLine(
      _PartySummary summary,
      ) {
    final parts = <String>[];

    if (summary.rupees.abs() > 0.01) {
      parts.add(
        summary.rupees > 0
            ? 'Owes you ₹${summary.rupees.toStringAsFixed(2)}'
            : 'You owe ₹${summary.rupees.abs().toStringAsFixed(2)}',
      );
    }

    if (summary.grams.abs() > 0.01) {
      parts.add(
        summary.grams > 0
            ? 'Owes you ${summary.grams.toStringAsFixed(2)}g'
            : 'You owe ${summary.grams.abs().toStringAsFixed(2)}g',
      );
    }

    if (parts.isEmpty) {
      return 'No outstanding balance';
    }

    return parts.join('  •  ');
  }

  Widget _detailRow(
      String label,
      dynamic value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: (value ?? '-').toString(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callCustomer(
      String? mobile,
      ) async {
    if (mobile == null ||
        mobile.trim().isEmpty) {
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: mobile.trim(),
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;

        _showError(
          'Could not open dialer',
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Could not open dialer.\n\n$e',
      );
    }
  }

  Future<void> _shareCustomers() async {
    if (customers.isEmpty) {
      _showError(
        'No customers to share yet',
      );
      return;
    }

    try {
      final buffer = StringBuffer();

      buffer.writeln(
        'No.,Name,Mobile,City,CR,DR,GROSS,NET,Balance Unit,Bill Ref,Date,Time,Narration',
      );

      for (final c in customers) {
        final row = [
          c['id'],
          c['name'],
          c['mobile'],
          c['city'],
          c['cr'],
          c['dr'],
          c['drGross'],
          c['drNet'],
          c['balanceUnit'],
          c['billRef'],
          c['date'],
          c['time'],
          c['narration'],
        ].map(
              (v) => _csvEscape(
            v?.toString() ?? '',
          ),
        ).join(',');

        buffer.writeln(row);
      }

      final dir =
      await getTemporaryDirectory();

      final file = File(
        '${dir.path}/customer_master.csv',
      );

      await file.writeAsString(
        buffer.toString(),
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Customer Master',
        text: 'Customer list export',
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Could not share customers.\n\n$e',
      );
    }
  }

  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }

    return value;
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? _validateMobile(String? v) {
    final value = (v ?? '').trim();

    if (value.isEmpty) return null;

    if (!_mobileRegex.hasMatch(value)) {
      return 'Enter a valid 10-digit mobile number';
    }

    return null;
  }

  String? _validateNumber(
      String? v, {
        bool required = false,
      }) {
    final value = (v ?? '').trim();

    if (value.isEmpty) {
      return required ? 'Required' : null;
    }

    if (!_numberRegex.hasMatch(value)) {
      return 'Numbers only';
    }

    return null;
  }

  Widget _field(
      String label,
      TextEditingController controller, {
        FocusNode? focusNode,
        TextInputType? keyboardType,
        String? Function(String?)? validator,
        List<TextInputFormatter>? inputFormatters,
        ValueChanged<String>? onChanged,
        VoidCallback? onFieldSubmitted,
      }) {
    return Padding(
      padding:
      const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 14,
        ),
        textInputAction: TextInputAction.next,
        validator: validator,
        onFieldSubmitted: (_) => onFieldSubmitted?.call(),
        onChanged: onChanged,
        decoration: InputDecoration(
          label: Text(label),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius:
        BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PartyAutocompleteField(
                    label: 'Customer Name',
                    controller: _nameController,
                    options: _nameOptions,
                    validator: _validateName,
                    onFocusNodeReady: _bindNameFocus,
                    onSelected: _prefillFromExistingName,
                    onFieldSubmitted: () => _focusNext(_mobileFocus),
                    onChanged: _onNameChanged,
                    onFocus: loadCustomers,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    'Mobile',
                    _mobileController,
                    focusNode: _mobileFocus,
                    keyboardType:
                    TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter
                          .digitsOnly,
                      LengthLimitingTextInputFormatter(
                        10,
                      ),
                    ],
                    validator:
                    _validateMobile,
                    onChanged: _onMobileChanged,
                    onFieldSubmitted: () => _focusNext(_cityFocus),
                  ),
                ),
              ],
            ),

            _field(
              'City',
              _cityController,
              focusNode: _cityFocus,
              onChanged: _onCityChanged,
              onFieldSubmitted: () => _focusNext(_pureWeightFocus),
            ),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'Pure Weight (g)',
                    _pureWeightController,
                    focusNode: _pureWeightFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => _validateNumber(v),
                    onChanged: _onPureWeightChanged,
                    onFieldSubmitted: () => _focusNext(_goldWeightFocus),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    'Gold Weight (g)',
                    _goldWeightController,
                    focusNode: _goldWeightFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => _validateNumber(v),
                    onChanged: _onGoldWeightChanged,
                    onFieldSubmitted: () => _focusNext(_narrationFocus),
                  ),
                ),
              ],
            ),

            _field(
              'Narration',
              _narrationController,
              focusNode: _narrationFocus,
              onChanged: _onNarrationChanged,
              onFieldSubmitted: () => FocusChain.focus(_saveFocus),
            ),

            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                focusNode: _saveFocus,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.navy,
                  foregroundColor:
                  Colors.white,
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(6),
                  ),
                ),
                onPressed:
                _saving ? null : saveCustomer,
                child: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'SAVE CUSTOMER ENTRY',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection() {
    final search = PartyAutocompleteField(
      label: 'Search customer',
      controller: _searchController,
      options: _searchOptions,
      helperText: 'Filter by name or mobile',
      onChanged: (_) => _applySearch(),
    );

    final header = Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Text(
        'CUSTOMERS (${_summaries.length})',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.4,
          color: AppColors.mutedBlue,
        ),
      ),
    );

    Widget listBody;

    if (_summaries.isEmpty) {
      listBody = const Padding(
        padding:
        EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No customers found',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
        ),
      );
    } else {
      listBody = MaterialTileCard(
        child: Column(
          children:
          List.generate(
            _summaries.length,
                (index) {
              final summary =
              _summaries[index];

              final isLast =
                  index ==
                      _summaries.length - 1;

              final hasBalance =
                  summary.rupees.abs() >
                      0.01 ||
                      summary.grams.abs() >
                          0.01;

              return Container(
                decoration:
                BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                    bottom:
                    BorderSide(
                      color:
                      AppColors.border,
                    ),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  onTap: () =>
                      _showPartyDetails(
                        summary,
                      ),
                  leading:
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                    AppColors.headerBand,
                    child: Text(
                      '${summary.entries.length}',
                      style:
                      const TextStyle(
                        fontSize: 11,
                      ),
                    ),
                  ),
                  title: Text(
                    summary.name,
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${summary.mobile.isEmpty ? '-' : summary.mobile}'
                        ' · ${summary.city.isEmpty ? '-' : summary.city}\n'
                        '${_outstandingLine(summary)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasBalance
                          ? AppColors.navy
                          : Colors.black54,
                      fontWeight: hasBalance
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  isThreeLine: true,
                  trailing:
                  summary.mobile.isNotEmpty
                      ? IconButton(
                    icon:
                    const Icon(
                      Icons.call,
                      color:
                      Colors.green,
                      size: 18,
                    ),
                    onPressed: () =>
                        _callCustomer(
                          summary.mobile,
                        ),
                  )
                      : const Icon(
                    Icons.chevron_right,
                    color:
                    AppColors.mutedBlue,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        search,
        const SizedBox(height: 12),
        header,
        listBody,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(
      child:
      CircularProgressIndicator(),
    )
        : WorkbenchLayout(
      equalSplit: true,
      disableScroll: true,
      primary: _buildFormCard(),
      secondary:
      _buildListSection(),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor:
      AppColors.background,
      appBar: AppBar(
        title:
        const Text('CUSTOMER MASTER'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.share,
              size: 20,
            ),
            tooltip:
            'Share customer list',
            onPressed:
            _shareCustomers,
          ),
        ],
      ),
      body: content,
    );
  }
}