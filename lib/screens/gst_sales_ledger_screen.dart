import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';
import '../logic/gst_sales_ledger.dart';
import '../pdf/pdf_kit.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
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

  /// Tighter flex so all 13 columns fit on a typical desktop width.
  static const _columnFlex = [
    1.1, 1.3, 2.0, 1.8, 1.0, 1.0, 1.0, 1.2, 1.6, 1.1, 1.1, 0.9, 1.4,
  ];

  static const _borderSide = BorderSide(color: AppColors.border, width: 1);

  Widget _gridCell(
    String text, {
    bool header = false,
    bool footer = false,
    bool boldGrand = false,
    int columnIndex = 0,
  }) {
    final numericCol = columnIndex >= 4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: header
            ? AppColors.tableHeader
            : footer
                ? AppColors.headerBand.withValues(alpha: 0.4)
                : Colors.white,
        border: const Border(
          right: _borderSide,
          bottom: _borderSide,
        ),
      ),
      child: Text(
        text,
        maxLines: header ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        softWrap: header,
        textAlign: numericCol ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: header ? 9.5 : 10.5,
          fontWeight: header || footer || boldGrand
              ? FontWeight.w800
              : FontWeight.normal,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _grandTotalBar() {
    if (_rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'GRAND TOTAL: ₹${_totals.grandTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _table() {
    final headers = GstSalesLedgerReport.headers;
    final rows = _rows;
    final footer = _totals.toFooterCells();
    final grandCol = GstSalesLedgerReport.grandTotalColumnIndex;

    TableRow buildRow(
      List<String> cells, {
      bool header = false,
      bool footer = false,
    }) {
      return TableRow(
        children: [
          for (var i = 0; i < headers.length; i++)
            _gridCell(
              i < cells.length ? cells[i] : '',
              header: header,
              footer: footer,
              boldGrand: !header && i == grandCol,
              columnIndex: i,
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (Responsive.isCompact(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GstSalesLedgerCompactList(rows: rows),
              ),
              _grandTotalBar(),
            ],
          );
        }

        final tableWidth = constraints.maxWidth;
        Widget tableContent = SizedBox(
          width: tableWidth,
          child: Table(
            border: const TableBorder(
              left: _borderSide,
              top: _borderSide,
              right: _borderSide,
              verticalInside: _borderSide,
              horizontalInside: _borderSide,
            ),
            columnWidths: {
              for (var i = 0; i < headers.length; i++)
                i: FlexColumnWidth(_columnFlex[i]),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              buildRow(headers, header: true),
              if (rows.isEmpty)
                buildRow(
                  const [
                    'No sales bills in this date range',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                  ],
                )
              else ...[
                for (final row in rows) buildRow(row.toCells()),
                buildRow(footer, footer: true),
              ],
            ],
          ),
        );

        if (tableWidth < 920) {
          tableContent = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: 920, child: tableContent),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tableContent,
            _grandTotalBar(),
          ],
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
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: _table(),
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

/// Phone-width GST ledger — one expandable card per bill (no 920px table scroll).
class GstSalesLedgerCompactList extends StatelessWidget {
  const GstSalesLedgerCompactList({super.key, required this.rows});

  final List<GstSalesLedgerRow> rows;

  static final _inr = NumberFormat('#,##0.00', 'en_IN');

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No sales bills in this date range',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return Material(
          color: AppColors.cardWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Bill #${row.billNo} · ${row.billDate}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.navy,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    row.customerName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Grand Total: ₹${_inr.format(row.grandTotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              children: [
                _line('GSTIN', row.gstin.isEmpty ? '—' : row.gstin),
                _line('Gross Wt', '${row.grossWeight.toStringAsFixed(2)} GM'),
                _line('Net Wt', '${row.netWeight.toStringAsFixed(3)} GM'),
                _line('Total Wt', '${row.totalWeight.toStringAsFixed(2)} GM'),
                _line('Rate', _inr.format(row.rate)),
                _line('Taxable', '₹${_inr.format(row.taxableValue)}'),
                _line('CGST', '₹${_inr.format(row.cgst)}'),
                _line('SGST', '₹${_inr.format(row.sgst)}'),
                _line('IGST', '₹${_inr.format(row.igst)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedBlue,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
