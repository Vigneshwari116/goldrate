import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';
import '../logic/gst_sales_ledger.dart';
import '../pdf/pdf_kit.dart';
import '../theme/app_theme.dart';
import '../util/app_date.dart';
import '../util/platform_detect.dart';
import '../util/screen_activation.dart';

class GstSalesLedgerScreen extends StatefulWidget {
  const GstSalesLedgerScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<GstSalesLedgerScreen> createState() => _GstSalesLedgerScreenState();
}

class _GstSalesLedgerScreenState extends State<GstSalesLedgerScreen>
    with ScreenActivationMixin<GstSalesLedgerScreen> {
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

  static final _pretty = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(GstSalesLedgerScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final txns = await DatabaseHelper.instance.getAllTransactions();
    if (!mounted) return;
    setState(() {
      _txns = txns;
      _loading = false;
    });
  }

  DateTime? _parse(String? raw) => parseAppDate(raw);

  bool _inRange(String? date) {
    final d = _parse(date);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  List<GstSalesLedgerRow> get _rows => GstSalesLedgerReport.rowsForTransactions(
        _txns,
        inDateRange: _inRange,
      );

  GstSalesLedgerTotals get _totals => GstSalesLedgerReport.totalsFor(_rows);

  String get _filterLabel =>
      'FILTER: ${_pretty.format(_from)} - ${_pretty.format(_to)}';

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

  static const _columnFlex = [
    2, 2, 4, 3, 2, 2, 2, 2, 3, 2, 2, 2, 3,
  ];

  Widget _table() {
    final headers = GstSalesLedgerReport.headers;
    final rows = _rows;
    final footer = _totals.toFooterCells();
    final grandCol = GstSalesLedgerReport.grandTotalColumnIndex;

    Widget headerCell(String text, int index) {
      final boldGrand = index == grandCol;
      return Expanded(
        flex: _columnFlex[index],
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: boldGrand ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      );
    }

    Widget dataRow(List<String> cells, {bool footer = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: footer ? AppColors.navy : AppColors.border,
              width: footer ? 1.5 : 1,
            ),
          ),
          color: footer ? AppColors.headerBand.withOpacity(0.35) : Colors.white,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < headers.length; i++)
              Expanded(
                flex: _columnFlex[i],
                child: Text(
                  i < cells.length ? cells[i] : '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (footer || i == grandCol)
                        ? FontWeight.w800
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth < 1100 ? 1100.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.tableHeader,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < headers.length; i++)
                        headerCell(headers[i], i),
                    ],
                  ),
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No sales bills in this date range')),
                  )
                else ...[
                  for (final row in rows) dataRow(row.toCells()),
                  dataRow(footer, footer: true),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportPdf() async {
    final headers = GstSalesLedgerReport.headers;
    final rows = _rows.map((r) => r.toCells()).toList();
    final footer = _totals.toFooterCells();
    final grandCol = GstSalesLedgerReport.grandTotalColumnIndex;

    final doc = await PdfKit.document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Text(
            'JEWELLERY MANAGEMENT',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'GST SALES LEDGER',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(_filterLabel, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('No records in this date range')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    for (var i = 0; i < headers.length; i++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(
                          headers[i],
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: i == grandCol
                                ? pw.FontWeight.bold
                                : pw.FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final row in rows)
                  pw.TableRow(
                    children: [
                      for (var i = 0; i < row.length; i++)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(
                            row[i],
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: i == grandCol
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                        ),
                    ],
                  ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    for (var i = 0; i < footer.length; i++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(
                          footer[i],
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    final bytes = await doc.save();
    final file = await PdfKit.sharePdf(
      bytes: bytes,
      fileName: 'gst_sales_ledger',
      subject: 'GST Sales Ledger',
      text: 'GST Sales Ledger for selected date range.',
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
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'GST SALES LEDGER',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'RECORDS: ${_rows.length}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                color: AppColors.navy,
                                child: Text(
                                  'GRAND TOTAL: ₹${_totals.grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(child: _table()),
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
                            onPressed: _exportPdf,
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
      appBar: AppBar(title: const Text('GST SALES LEDGER')),
      body: body,
    );
  }
}
