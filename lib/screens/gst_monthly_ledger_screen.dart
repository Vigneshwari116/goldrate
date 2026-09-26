import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';
import '../logic/gst_monthly_ledger.dart';
import '../pdf/invoice_party_lines.dart';
import '../pdf/pdf_kit.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../util/platform_detect.dart';
import '../util/screen_activation.dart';

class GstMonthlyLedgerScreen extends StatefulWidget {
  const GstMonthlyLedgerScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<GstMonthlyLedgerScreen> createState() => _GstMonthlyLedgerScreenState();
}

class _GstMonthlyLedgerScreenState extends State<GstMonthlyLedgerScreen>
    with ScreenActivationMixin<GstMonthlyLedgerScreen> {
  DateTime _from = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _to = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _loading = true;
  List<Map<String, dynamic>> _txns = [];
  double _seedOpening = 0;
  final _seedController = TextEditingController();

  static final _pretty = DateFormat('dd/MM/yyyy');
  static final _inr = NumberFormat('#,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(GstMonthlyLedgerScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() => _load();

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txns = await DatabaseHelper.instance.getAllTransactions();
    final seed = await GstMonthlyLedgerReport.loadSeedOpening();
    if (!mounted) return;
    _seedController.text = seed == 0 ? '' : seed.toStringAsFixed(2);
    setState(() {
      _txns = txns;
      _seedOpening = seed;
      _loading = false;
    });
  }

  String get _filterLabel =>
      'FILTER: ${_pretty.format(_from)} - ${_pretty.format(_to)}';

  GstMonthlyLedgerRow get _row => GstMonthlyLedgerReport.forMonth(
        transactions: _txns,
        year: _from.year,
        month: _from.month,
        seedOpening: _seedOpening,
      );

  String get _gstinLabel {
    const fallback = '29ABDPV0313K1ZK';
    for (final line in InvoicePartyLines.shopLines) {
      if (line.contains('GSTIN')) {
        final parts = line.split(':');
        if (parts.length > 1) return parts.last.trim();
      }
    }
    return fallback;
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      _to = picked;
    });
  }

  Future<void> _pickRange() async {
    final from = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'From date',
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _to.isBefore(from) ? from : _to,
      firstDate: from,
      lastDate: DateTime(2100),
      helpText: 'To date',
    );
    if (to == null) return;
    setState(() {
      _from = from;
      _to = to;
    });
  }

  Future<void> _saveSeed() async {
    final value = double.tryParse(_seedController.text.trim()) ?? 0;
    await GstMonthlyLedgerReport.saveSeedOpening(value);
    setState(() => _seedOpening = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening balance seed saved')),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? AppColors.headerBand : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _filterRow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fromDay = DateTime(_from.year, _from.month, _from.day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chip('TODAY', () {
            setState(() {
              _from = today;
              _to = today;
            });
          }, active: _from == _to && fromDay == today),
          _chip('CUSTOM DATE', _pickSingleDate),
          _chip('DATE RANGE', _pickRange),
          DropdownButton<int>(
            value: _from.month,
            items: List.generate(
              12,
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text(DateFormat('MMMM').format(DateTime(2026, i + 1))),
              ),
            ),
            onChanged: (m) {
              if (m == null) return;
              final last = DateTime(_from.year, m + 1, 0);
              setState(() {
                _from = DateTime(_from.year, m, 1);
                _to = last;
              });
            },
          ),
          const SizedBox(width: 8),
          Text(
            _filterLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.mutedBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prominentClosing(GstMonthlyLedgerRow row) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        row.closingLabel,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: Responsive.isCompact(context) ? 14 : 18,
        ),
      ),
    );
  }

  Widget _summaryTable(GstMonthlyLedgerRow row) {
    final cells = row.toCells();
    return Table(
      border: TableBorder.all(color: AppColors.border),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2.2),
        3: FlexColumnWidth(2),
        4: FlexColumnWidth(2.2),
        5: FlexColumnWidth(2),
        6: FlexColumnWidth(2),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: AppColors.tableHeader),
          children: [
            for (final h in GstMonthlyLedgerReport.headers)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  h,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        TableRow(
          children: [
            for (final c in cells)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(c, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportPdf(GstMonthlyLedgerRow row) async {
    final headers = GstMonthlyLedgerReport.headers;
    final cells = row.toCells();
    final doc = await PdfKit.document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'JEWELLERY MANAGEMENT',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'TOTAL GST LEDGER',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('GSTIN: $_gstinLabel', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(_filterLabel, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.Text(
            row.closingLabel,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: [cells],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    final file = await PdfKit.sharePdf(
      bytes: bytes,
      fileName: 'total_gst_ledger',
      subject: 'Total GST Ledger',
      text: 'Monthly GST ledger for ${row.monthLabel}.',
    );
    if (!mounted) return;
    if (!isMobileNative) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: ${file.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    final needsSeed = GstMonthlyLedgerReport.needsSeedEntry(_txns);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filterRow(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'TOTAL GST LEDGER',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'GSTIN: $_gstinLabel',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.mutedBlue,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _prominentClosing(row),
                              if (needsSeed) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'First month — set starting GST opening balance (one-time):',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _seedController,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Opening balance (₹)',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: _saveSeed,
                                      child: const Text('SAVE'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _summaryTable(row),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                            ),
                            onPressed: () => _exportPdf(row),
                            child: Text(
                              isMobileNative
                                  ? 'SHARE PDF — THEN PRINT FROM WHATSAPP / FILES'
                                  : 'SAVE PDF AND OPEN — THEN PRINT FROM THE PDF WINDOW',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('TOTAL GST LEDGER')),
      body: body,
    );
  }
}
