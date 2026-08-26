import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/material_tile_card.dart';
import '../widgets/party_autocomplete_field.dart';

/// Every raw row in `suppliers` is one visit/entry.
/// This groups all entries of a person together and calculates
/// the running outstanding balance separately for rupees and grams.
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
    List<Map<String, dynamic>> rows) {
  final grouped = <String, List<Map<String, dynamic>>>{};

  for (final row in rows) {
    final name = (row['name'] ?? '').toString().trim();

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
          double.tryParse((e['cr'] ?? '').toString()) ?? 0;

      final dr =
          double.tryParse((e['dr'] ?? '').toString()) ?? 0;

      final unit =
      (e['balanceUnit'] ?? 'RUPEES').toString();

      final net = dr - cr;

      if (unit == 'GRAMS') {
        grams += net;
      } else {
        rupees += net;
      }

      if (mobile.isEmpty &&
          (e['mobile'] ?? '').toString().isNotEmpty) {
        mobile = e['mobile'].toString();
      }

      if (city.isEmpty &&
          (e['city'] ?? '').toString().isNotEmpty) {
        city = e['city'].toString();
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
        (a, b) => a.name
        .toLowerCase()
        .compareTo(b.name.toLowerCase()),
  );

  return summaries;
}

class SupplierMasterScreen extends StatefulWidget {
  const SupplierMasterScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<SupplierMasterScreen> createState() =>
      _SupplierMasterScreenState();
}

class _SupplierMasterScreenState
    extends State<SupplierMasterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _cityController = TextEditingController();
  final _crController =
  TextEditingController(text: '0');
  final _drController =
  TextEditingController(text: '0');
  final _grossController =
  TextEditingController(text: '0');
  final _netController =
  TextEditingController(text: '0');
  final _narrationController =
  TextEditingController();
  final _searchController =
  TextEditingController();

  List<Map<String, dynamic>> suppliers = [];

  List<Map<String, dynamic>> _filteredSuppliers = [];

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

    loadSuppliers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _cityController.dispose();
    _crController.dispose();
    _drController.dispose();
    _grossController.dispose();
    _netController.dispose();
    _narrationController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD SUPPLIERS
  // ============================================================

  Future<void> loadSuppliers() async {
    try {
      final data =
      await DatabaseHelper.instance.getSuppliers();

      if (!mounted) return;

      setState(() {
        suppliers = data;
        _loading = false;
      });

      _applySearch();
    } catch (e, stackTrace) {
      debugPrint(
        'LOAD SUPPLIERS ERROR: $e',
      );

      debugPrint(
        '$stackTrace',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load suppliers: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void _applySearch() {
    if (!mounted) return;

    final query =
    _searchController.text.trim().toLowerCase();

    final filtered = query.isEmpty
        ? List<Map<String, dynamic>>.from(suppliers)
        : suppliers.where((s) {
      final name =
      (s['name'] ?? '')
          .toString()
          .toLowerCase();

      final mobile =
      (s['mobile'] ?? '')
          .toString()
          .toLowerCase();

      return name.contains(query) ||
          mobile.contains(query);
    }).toList();

    final summaries =
    _buildSummaries(filtered);

    setState(() {
      _filteredSuppliers = filtered;
      _summaries = summaries;
    });
  }

  List<String> get _allNames =>
      _buildSummaries(suppliers).map((s) => s.name).toList();

  Iterable<String> _nameOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _allNames.take(12);
    return _allNames.where((n) => n.toLowerCase().contains(lower)).take(12);
  }

  Iterable<String> _searchOptions(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _allNames.take(12);
    return _allNames.where((name) {
      if (name.toLowerCase().contains(lower)) return true;
      final match = _buildSummaries(suppliers)
          .where((s) => s.name == name)
          .toList();
      if (match.isEmpty) return false;
      return match.first.mobile.toLowerCase().contains(lower);
    }).take(12);
  }

  void _prefillFromExistingName(String name) {
    for (final summary in _buildSummaries(suppliers)) {
      if (summary.name == name) {
        _mobileController.text = summary.mobile;
        _cityController.text = summary.city;
        return;
      }
    }
  }

  // ============================================================
  // CLEAR FORM
  // ============================================================

  void _clearForm() {
    _nameController.clear();
    _mobileController.clear();
    _cityController.clear();

    _crController.text = '0';
    _drController.text = '0';
    _grossController.text = '0';
    _netController.text = '0';

    _narrationController.clear();

    _formKey.currentState?.reset();
  }

  // ============================================================
  // SAVE SUPPLIER
  // ============================================================

  Future<void> saveSupplier() async {
    debugPrint(
      '==============================',
    );

    debugPrint(
      'SUPPLIER SAVE STARTED',
    );

    debugPrint(
      '==============================',
    );

    // ----------------------------------------------------------
    // VALIDATION
    // ----------------------------------------------------------

    final isValid =
        _formKey.currentState?.validate() ?? false;

    if (!isValid) {
      debugPrint(
        'SUPPLIER SAVE: FORM VALIDATION FAILED',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please correct the highlighted fields',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }

      return;
    }

    if (_saving) {
      debugPrint(
        'SUPPLIER SAVE: ALREADY SAVING',
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final now = DateTime.now();

      final date =
      DateFormat('dd-MM-yyyy').format(now);

      final time =
      DateFormat('hh:mm a').format(now);

      // --------------------------------------------------------
      // CREATE DATABASE RECORD
      // --------------------------------------------------------

      final record = <String, dynamic>{
        'name': _nameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'city': _cityController.text.trim(),
        'cr': _crController.text.trim(),
        'dr': _drController.text.trim(),
        'gross': _grossController.text.trim(),
        'net': _netController.text.trim(),
        'narration':
        _narrationController.text.trim(),
        'balanceUnit': 'GRAMS',
        'billRef': '',
        'date': date,
        'time': time,
      };

      debugPrint(
        'SUPPLIER RECORD:',
      );

      debugPrint(
        record.toString(),
      );

      // --------------------------------------------------------
      // INSERT
      // --------------------------------------------------------

      final insertedId =
      await DatabaseHelper.instance
          .insertSupplier(record);

      debugPrint(
        'SUPPLIER INSERT SUCCESS',
      );

      debugPrint(
        'INSERTED ID: $insertedId',
      );

      // --------------------------------------------------------
      // RELOAD DATABASE
      // --------------------------------------------------------

      await loadSuppliers();

      if (!mounted) return;

      // --------------------------------------------------------
      // CLEAR FORM
      // --------------------------------------------------------

      _clearForm();

      setState(() {
        _saving = false;
      });

      // --------------------------------------------------------
      // SUCCESS MESSAGE
      // --------------------------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Supplier saved successfully. ID: $insertedId',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      debugPrint(
        'SUPPLIER SAVE COMPLETED SUCCESSFULLY',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '==============================',
      );

      debugPrint(
        'SUPPLIER SAVE ERROR',
      );

      debugPrint(
        e.toString(),
      );

      debugPrint(
        stackTrace.toString(),
      );

      debugPrint(
        '==============================',
      );

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Supplier save failed:\n$e',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> _confirmDelete(int id) async {
    final confirmed =
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Entry',
        ),
        content: const Text(
          'Are you sure you want to delete this record?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text(
              'Cancel',
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance
            .deleteSupplier(id);

        await loadSuppliers();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Supplier entry deleted',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Delete failed: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // ENTRY LINE
  // ============================================================

  String _entryLine(
      Map<String, dynamic> e) {
    final cr =
        double.tryParse(
          (e['cr'] ?? '').toString(),
        ) ??
            0;

    final dr =
        double.tryParse(
          (e['dr'] ?? '').toString(),
        ) ??
            0;

    final unit =
    (e['balanceUnit'] ?? 'RUPEES')
        .toString();

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

  // ============================================================
  // PARTY DETAILS
  // ============================================================

  void _showPartyDetails(
      _PartySummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                for (final e in summary.entries)
                  Container(
                    margin:
                    const EdgeInsets.only(
                      bottom: 8,
                    ),
                    padding:
                    const EdgeInsets.all(8),
                    decoration:
                    BoxDecoration(
                      color:
                      AppColors.headerBand,
                      borderRadius:
                      BorderRadius.circular(
                        6,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                _entryLine(e),
                                style:
                                const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight:
                                  FontWeight
                                      .w600,
                                ),
                              ),
                              if ((e['narration'] ??
                                  '')
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  e['narration']
                                      .toString(),
                                  style:
                                  const TextStyle(
                                    fontSize: 11.5,
                                  ),
                                ),
                              Text(
                                '${e['date'] ?? ''} '
                                    '${e['time'] ?? ''}'
                                    '${(e['billRef'] ?? '').toString().isNotEmpty ? '  •  ${e['billRef']}' : ''}',
                                style:
                                const TextStyle(
                                  fontSize: 10.5,
                                  color:
                                  Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            size: 16,
                            color:
                            Colors.redAccent,
                          ),
                          padding:
                          EdgeInsets.zero,
                          constraints:
                          const BoxConstraints(),
                          onPressed: () async {
                            Navigator.pop(context);

                            final id =
                            e['id'];

                            if (id is int) {
                              await _confirmDelete(
                                id,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context),
            child: const Text(
              'CLOSE',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // OUTSTANDING
  // ============================================================

  String _outstandingLine(
      _PartySummary summary) {
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

  // ============================================================
  // DETAIL ROW
  // ============================================================

  Widget _detailRow(
      String label,
      dynamic value) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 3,
      ),
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
              text:
              (value ?? '-').toString(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CALL SUPPLIER
  // ============================================================

  Future<void> _callSupplier(
      String? mobile) async {
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

        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open dialer',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Could not open dialer: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // SHARE SUPPLIERS
  // ============================================================

  Future<void> _shareSuppliers() async {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'No suppliers to share yet',
          ),
        ),
      );

      return;
    }

    try {
      final buffer = StringBuffer();

      buffer.writeln(
        'No.,Name,Mobile,City,CR,DR,GROSS,NET,'
            'Balance Unit,Bill Ref,Date,Time,Narration',
      );

      for (final s in suppliers) {
        final row = [
          s['id'],
          s['name'],
          s['mobile'],
          s['city'],
          s['cr'],
          s['dr'],
          s['gross'],
          s['net'],
          s['balanceUnit'],
          s['billRef'],
          s['date'],
          s['time'],
          s['narration'],
        ]
            .map(
              (v) => _csvEscape(
            v?.toString() ?? '',
          ),
        )
            .join(',');

        buffer.writeln(row);
      }

      final dir =
      await getTemporaryDirectory();

      final file = File(
        '${dir.path}/supplier_master.csv',
      );

      await file.writeAsString(
        buffer.toString(),
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Supplier Master',
        text: 'Supplier list export',
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Share failed: $e',
          ),
          backgroundColor: Colors.red,
        ),
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

  // ============================================================
  // VALIDATORS
  // ============================================================

  String? _validateName(String? v) {
    if (v == null ||
        v.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? _validateMobile(String? v) {
    final value =
    (v ?? '').trim();

    if (value.isEmpty) {
      return null;
    }

    if (!_mobileRegex.hasMatch(value)) {
      return 'Enter a valid 10-digit mobile number';
    }

    return null;
  }

  String? _validateNumber(
      String? v, {
        bool required = false,
      }) {
    final value =
    (v ?? '').trim();

    if (value.isEmpty) {
      return required
          ? 'Required'
          : null;
    }

    if (!_numberRegex.hasMatch(value)) {
      return 'Numbers only';
    }

    return null;
  }

  // ============================================================
  // FORM FIELD
  // ============================================================

  Widget _field(
      String label,
      TextEditingController controller, {
        TextInputType? keyboardType,
        String? Function(String?)? validator,
        List<TextInputFormatter>?
        inputFormatters,
      }) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters:
        inputFormatters,
        style: const TextStyle(
          fontSize: 14,
        ),
        validator: validator,
        decoration:
        InputDecoration(
          label: Text(label),
        ),
      ),
    );
  }

  // ============================================================
  // FORM CARD
  // ============================================================

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
      padding:
      const EdgeInsets.all(12),
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
                    label: 'Supplier Name',
                    controller: _nameController,
                    options: _nameOptions,
                    validator: _validateName,
                    onSelected: _prefillFromExistingName,
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: _field(
                    'Mobile',
                    _mobileController,
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
                  ),
                ),
              ],
            ),

            _field(
              'City',
              _cityController,
            ),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'CR (Credit)',
                    _crController,
                    keyboardType:
                    const TextInputType
                        .numberWithOptions(
                      decimal: true,
                    ),
                    validator:
                        (v) =>
                        _validateNumber(v),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: _field(
                    'DR (Debit)',
                    _drController,
                    keyboardType:
                    const TextInputType
                        .numberWithOptions(
                      decimal: true,
                    ),
                    validator:
                        (v) =>
                        _validateNumber(v),
                  ),
                ),
              ],
            ),

            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'GROSS',
                    _grossController,
                    keyboardType:
                    const TextInputType
                        .numberWithOptions(
                      decimal: true,
                    ),
                    validator:
                        (v) =>
                        _validateNumber(v),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: _field(
                    'NET',
                    _netController,
                    keyboardType:
                    const TextInputType
                        .numberWithOptions(
                      decimal: true,
                    ),
                    validator:
                        (v) =>
                        _validateNumber(v),
                  ),
                ),
              ],
            ),

            _field(
              'Narration',
              _narrationController,
            ),

            const SizedBox(
              height: 2,
            ),

            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed:
                _saving
                    ? null
                    : saveSupplier,
                child: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    color:
                    Colors.white,
                    strokeWidth:
                    2,
                  ),
                )
                    : const Text(
                  'SAVE SUPPLIER ENTRY',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LIST SECTION
  // ============================================================

  Widget _buildListSection() {
    final search = PartyAutocompleteField(
      label: 'Search supplier',
      controller: _searchController,
      options: _searchOptions,
      helperText: 'Filter by name or mobile',
      onChanged: (_) => _applySearch(),
    );

    final header =
    Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Text(
        'SUPPLIERS (${_summaries.length})',
        textAlign:
        TextAlign.center,
        style:
        const TextStyle(
          fontWeight:
          FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.4,
          color:
          AppColors.mutedBlue,
        ),
      ),
    );

    Widget listBody;

    if (_summaries.isEmpty) {
      listBody =
      const Padding(
        padding:
        EdgeInsets.symmetric(
          vertical: 24,
        ),
        child: Center(
          child: Text(
            'No suppliers found',
            style: TextStyle(
              fontSize: 13,
              color:
              Colors.black54,
            ),
          ),
        ),
      );
    } else {
      listBody =
          MaterialTileCard(
            child: Column(
              children:
              List.generate(
                _summaries.length,
                    (index) {
                  final summary =
                  _summaries[index];

                  final isLast =
                      index ==
                          _summaries.length -
                              1;

                  final hasBalance =
                      summary.rupees
                          .abs() >
                          0.01 ||
                          summary.grams
                              .abs() >
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
                          AppColors
                              .border,
                        ),
                      ),
                    ),
                    child:
                    ListTile(
                      dense: true,
                      onTap: () =>
                          _showPartyDetails(
                            summary,
                          ),
                      leading:
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                        AppColors
                            .headerBand,
                        child: Text(
                          '${summary.entries.length}',
                          style:
                          const TextStyle(
                            fontSize: 11,
                            color:
                            AppColors
                                .navy,
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
                      subtitle:
                      Text(
                        '${summary.mobile.isEmpty ? '-' : summary.mobile}'
                            ' · ${summary.city.isEmpty ? '-' : summary.city}\n'
                            '${_outstandingLine(summary)}',
                        style:
                        TextStyle(
                          fontSize:
                          11.5,
                          color: hasBalance
                              ? AppColors
                              .navy
                              : Colors
                              .black54,
                          fontWeight:
                          hasBalance
                              ? FontWeight
                              .w600
                              : FontWeight
                              .normal,
                        ),
                      ),
                      isThreeLine:
                      true,
                      trailing:
                      summary.mobile
                          .isNotEmpty
                          ? IconButton(
                        icon:
                        const Icon(
                          Icons
                              .call,
                          color:
                          Colors
                              .green,
                          size:
                          18,
                        ),
                        onPressed:
                            () =>
                            _callSupplier(
                              summary
                                  .mobile,
                            ),
                      )
                          : const Icon(
                        Icons
                            .chevron_right,
                        color:
                        AppColors
                            .mutedBlue,
                        size:
                        20,
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
        const SizedBox(
          height: 12,
        ),
        header,
        listBody,
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context) {
    final content = _loading
        ? const Center(
      child:
      CircularProgressIndicator(),
    )
        : WorkbenchLayout(
      equalSplit: true,
      disableScroll: true,
      primary:
      _buildFormCard(),
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
        title: const Text(
          'SUPPLIER MASTER',
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.share,
              size: 20,
            ),
            tooltip:
            'Share supplier list',
            onPressed:
            _shareSuppliers,
          ),
        ],
      ),
      body: content,
    );
  }
}