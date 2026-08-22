import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../logic/gold_ledger.dart';
import '../theme/app_theme.dart';

enum _ReportTab {
  dailySales,
  billWise,
  goldAudit,
  purchaseAudit,
  customerLedger,
  supplierLedger,
  customerNameWise,
  supplierNameWise,
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportTab _tab = _ReportTab.goldAudit;
  DateTime _from = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _to = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _allHistory = false;
  bool _loading = true;

  List<Map<String, dynamic>> _txns = [];
  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];

  static final _fmt = DateFormat('dd-MM-yyyy');
  static final _pretty = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await DatabaseHelper.instance.getAllTransactions();
    final vouchers = await DatabaseHelper.instance.getVouchers();
    final customers = await DatabaseHelper.instance.getCustomers();
    final suppliers = await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _txns = txns;
      _vouchers = vouchers;
      _customers = customers;
      _suppliers = suppliers;
      _loading = false;
    });
  }

  DateTime? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return _fmt.parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool _inRange(String? date) {
    if (_allHistory) return true;
    final d = _parse(date);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  List<Map<String, dynamic>> get _filteredTxns =>
      _txns.where((r) => _inRange(r['date']?.toString())).toList();

  List<Map<String, dynamic>> get _filteredVouchers =>
      _vouchers.where((r) => _inRange(r['date']?.toString())).toList();

  DailyTotals get _totals {
    var totals = const DailyTotals();
    for (final row in _filteredTxns) {
      final grams = double.tryParse((row['totalPureWt'] ?? '').toString()) ?? 0;
      final amount = double.tryParse((row['totalValue'] ?? '').toString()) ?? 0;
      final oldG = double.tryParse((row['oldGrams'] ?? '').toString()) ?? 0;
      final newG = double.tryParse((row['newGrams'] ?? '').toString()) ?? 0;
      final unpaidG = (newG - oldG).abs();
      final unpaidAmt =
          (double.tryParse((row['totalValue'] ?? '').toString()) ?? 0) -
              (double.tryParse((row['paymentAmount'] ?? '').toString()) ?? 0);
      if (row['transactionType'] == 'SALES') {
        totals = totals.addSale(
          grams: grams,
          amount: amount,
          unpaidGrams: unpaidG,
          unpaidAmount: unpaidAmt > 0 ? unpaidAmt : 0,
        );
      } else if (row['transactionType'] == 'PURCHASE') {
        totals = totals.addPurchase(
          grams: grams,
          amount: amount,
          unpaidGrams: unpaidG,
          unpaidAmount: unpaidAmt > 0 ? unpaidAmt : 0,
        );
      }
    }
    for (final v in _filteredVouchers) {
      final mode = (v['paymentMode'] ?? '').toString();
      final amt = double.tryParse((v['amount'] ?? '').toString()) ?? 0;
      final gold = double.tryParse((v['cashToGold'] ?? '').toString()) ??
          (mode == 'GOLD' ? amt : 0);
      totals = totals.addReceipt(
        cash: mode == 'GOLD' ? 0 : amt,
        gold: gold,
      );
    }
    return totals;
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
      _allHistory = false;
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
      _allHistory = false;
      _from = from;
      _to = to;
    });
  }

  String get _filterLabel {
    if (_allHistory) return 'FILTER: ALL HISTORY';
    return 'FILTER: ${_pretty.format(_from)} - ${_pretty.format(_to)}';
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tabBar(),
              _filterRow(),
              Expanded(child: _matrix()),
            ],
          );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('DAILY REPORTS')),
      body: content,
    );
  }

  Widget _tabBar() {
    Widget tab(_ReportTab id, String label) {
      final on = _tab == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: () => setState(() => _tab = id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? AppColors.tabActive : AppColors.navy,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(on ? 1 : 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tab(_ReportTab.dailySales, 'DAILY SALES REPORT'),
            tab(_ReportTab.billWise, 'BILL WISE ABSTRACT'),
            tab(_ReportTab.goldAudit, 'GOLD SALES AUDIT'),
            tab(_ReportTab.purchaseAudit, 'PURCHASE AUDIT'),
            tab(_ReportTab.customerLedger, 'CUSTOMER LEDGER'),
            tab(_ReportTab.supplierLedger, 'SUPPLIER LEDGER'),
            tab(_ReportTab.customerNameWise, 'CUSTOMER NAME WISE'),
            tab(_ReportTab.supplierNameWise, 'SUPPLIER NAME WISE'),
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chip('TODAY', () {
            setState(() {
              _allHistory = false;
              _from = DateTime(now.year, now.month, now.day);
              _to = _from;
            });
          }, active: !_allHistory && _from == _to && _from.day == now.day),
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
                _allHistory = false;
                _from = DateTime(_from.year, m, 1);
                _to = last;
              });
            },
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => setState(() => _allHistory = true),
            child: const Text('SHOW ALL HISTORY'),
          ),
          const SizedBox(width: 12),
          Text(_filterLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.mutedBlue)),
        ],
      ),
    );
  }

  Widget _matrix() {
    switch (_tab) {
      case _ReportTab.dailySales:
        return _dailyCard();
      case _ReportTab.billWise:
        return _billAbstract(salesOnly: false);
      case _ReportTab.goldAudit:
        return _billAbstract(salesOnly: true, title: 'GOLD SALES AUDIT LEDGER MATRIX');
      case _ReportTab.purchaseAudit:
        return _billAbstract(salesOnly: false, purchasesOnly: true, title: 'PURCHASE AUDIT LEDGER MATRIX');
      case _ReportTab.customerLedger:
        return _partyLedger(_customers, 'CUSTOMER LEDGER MATRIX');
      case _ReportTab.supplierLedger:
        return _partyLedger(_suppliers, 'SUPPLIER LEDGER MATRIX');
      case _ReportTab.customerNameWise:
        return _nameWise(customer: true);
      case _ReportTab.supplierNameWise:
        return _nameWise(customer: false);
    }
  }

  Widget _dailyCard() {
    final t = _totals;
    return _reportShell(
      title: 'DAILY SALES / PURCHASE AUTO TOTALS',
      records: t.salesBills + t.purchaseBills + t.receiptVouchers,
      units: t.salesGrams + t.purchaseGrams,
      total: t.salesAmount,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _stat('Sales bills (auto)', '${t.salesBills}'),
          _stat('Sales GWT / pure', '${t.salesGrams.toStringAsFixed(3)} g'),
          _stat('Sales amount', '₹${t.salesAmount.toStringAsFixed(2)}'),
          _stat('Sales credit (unpaid)',
              '${t.salesCreditGrams.toStringAsFixed(3)} g  ·  ₹${t.salesCreditAmount.toStringAsFixed(2)}'),
          const Divider(),
          _stat('Purchase bills (auto)', '${t.purchaseBills}'),
          _stat('Purchase GWT / pure', '${t.purchaseGrams.toStringAsFixed(3)} g'),
          _stat('Purchase amount', '₹${t.purchaseAmount.toStringAsFixed(2)}'),
          _stat('Purchase credit (unpaid)',
              '${t.purchaseCreditGrams.toStringAsFixed(3)} g  ·  ₹${t.purchaseCreditAmount.toStringAsFixed(2)}'),
          const Divider(),
          _stat('Receipts / payments', '${t.receiptVouchers}'),
          _stat('Receipt cash', '₹${t.receiptsCash.toStringAsFixed(2)}'),
          _stat('Receipt gold (incl. cash converted)',
              '${t.receiptsGold.toStringAsFixed(3)} g'),
          const SizedBox(height: 12),
          const Text(
            'These figures fill themselves from saved sales, purchase and receipt vouchers. Nothing is typed on this screen.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
      pdfRows: [
        ['Sales bills', '${t.salesBills}', '', '', '₹${t.salesAmount.toStringAsFixed(2)}'],
        ['Sales credit', '', '${t.salesCreditGrams.toStringAsFixed(3)} g', '', '₹${t.salesCreditAmount.toStringAsFixed(2)}'],
        ['Purchase bills', '${t.purchaseBills}', '', '', '₹${t.purchaseAmount.toStringAsFixed(2)}'],
        ['Purchase credit', '', '${t.purchaseCreditGrams.toStringAsFixed(3)} g', '', '₹${t.purchaseCreditAmount.toStringAsFixed(2)}'],
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _billAbstract({
    required bool salesOnly,
    bool purchasesOnly = false,
    String title = 'BILL WISE ABSTRACT',
  }) {
    var rows = _filteredTxns;
    if (salesOnly) {
      rows = rows.where((r) => r['transactionType'] == 'SALES').toList();
    }
    if (purchasesOnly) {
      rows = rows.where((r) => r['transactionType'] == 'PURCHASE').toList();
    }
    rows = [...rows]..sort((a, b) {
        final an = a['billNo'] as int? ?? 0;
        final bn = b['billNo'] as int? ?? 0;
        return an.compareTo(bn);
      });

    double total = 0;
    double units = 0;
    final table = <List<String>>[];
    for (final bill in rows) {
      total += double.tryParse((bill['totalValue'] ?? '').toString()) ?? 0;
      units += double.tryParse((bill['totalPureWt'] ?? '').toString()) ?? 0;
      List items;
      try {
        items = jsonDecode((bill['items'] ?? '[]').toString()) as List;
      } catch (_) {
        items = [];
      }
      final billNo =
          '${bill['transactionType'] == 'PURCHASE' ? 'PUR' : 'SAL'}-${bill['billNo']}';
      if (items.isEmpty) {
        table.add([
          billNo,
          '${bill['partyName']}',
          '-',
          '${bill['totalPureWt']} g',
          '₹${bill['totalValue']}',
        ]);
      }
      for (final item in items) {
        if (item is! Map) continue;
        table.add([
          billNo,
          '${item['type']}  ${bill['partyName']}  '
              'mode ${bill['paymentMode']}  '
              'old ${bill['oldGrams'] ?? '-'}g → new ${bill['newGrams'] ?? bill['balance']}g'
              '${(bill['cashToGold'] ?? '0') != '0.000' && (bill['cashToGold'] ?? '') != '' && (bill['cashToGold'] ?? '0') != '0' ? '  cash→gold ${bill['cashToGold']}g' : ''}',
          '₹${(item['rate'] ?? 0)}',
          'x${item['weight']} gwt',
          '₹${((item['value'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
        ]);
      }
    }

    return _reportShell(
      title: title,
      records: rows.length,
      units: units,
      total: total,
      child: _htmlTable(table),
      pdfRows: table,
    );
  }

  Widget _partyLedger(List<Map<String, dynamic>> all, String title) {
    final rows = all.where((r) => _inRange(r['date']?.toString())).toList();
    double total = 0;
    final table = <List<String>>[];
    for (final e in rows) {
      final dr = double.tryParse((e['dr'] ?? '').toString()) ?? 0;
      final cr = double.tryParse((e['cr'] ?? '').toString()) ?? 0;
      total += dr;
      table.add([
        (e['billRef'] ?? '-').toString(),
        '${e['name']}  ${(e['narration'] ?? '')}',
        (e['balanceUnit'] ?? '').toString(),
        dr > 0 ? 'DR ${dr.toStringAsFixed(3)}' : 'CR ${cr.toStringAsFixed(3)}',
        e['date']?.toString() ?? '',
      ]);
    }
    return _reportShell(
      title: title,
      records: rows.length,
      units: 0,
      total: total,
      child: _htmlTable(table, headers: const [
        'BILL NO',
        'PARTICULARS',
        'UNIT',
        'QTY',
        'DATE',
      ]),
      pdfRows: table,
      headers: const ['BILL NO', 'PARTICULARS', 'UNIT', 'QTY', 'DATE'],
    );
  }

  Widget _nameWise({required bool customer}) {
    final known = (customer ? _customers : _suppliers)
        .map((e) => (e['name'] ?? '').toString())
        .where((n) => n.trim().isNotEmpty);
    final rows = buildPartyNameWise(
      customer: customer,
      knownNames: known,
      transactions: _txns,
      vouchers: _vouchers,
      from: _from,
      to: _to,
      allHistory: _allHistory,
    );
    final headers = customer
        ? const [
            'Customer Name',
            'Opening Balance',
            'Debit (Sales)',
            'Credit (Payment)',
            'Closing Balance',
          ]
        : const [
            'Supplier Name',
            'Opening Balance',
            'Debit (Payment)',
            'Credit (Purchase)',
            'Closing Balance',
          ];
    final table = [for (final r in rows) r.toTableCells()];
    final closingTotal =
        rows.fold<double>(0, (sum, r) => sum + r.closing);
    return _reportShell(
      title: customer
          ? 'CUSTOMER NAME WISE GOLD STATEMENT'
          : 'SUPPLIER NAME WISE GOLD STATEMENT',
      records: rows.length,
      units: closingTotal,
      total: closingTotal,
      totalText: 'CLOSING: ${closingTotal.toStringAsFixed(3)} g',
      child: _htmlTable(table, headers: headers, evenFlex: true),
      pdfRows: table,
      headers: headers,
    );
  }

  Widget _htmlTable(List<List<String>> rows,
      {List<String> headers = const [
        'BILL NO',
        'PARTICULARS',
        'RATE',
        'QTY',
        'AMOUNT',
      ],
      bool evenFlex = false}) {
    if (rows.isEmpty) {
      return const Center(child: Text('No records in this filter'));
    }
    int flexFor(int i) {
      if (evenFlex) return 2;
      return i == 1 ? 4 : 2;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        Container(
          color: AppColors.tableHeader,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                Expanded(
                  flex: flexFor(i),
                  child: Text(headers[i],
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        for (final row in rows)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: Colors.white,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < row.length; i++)
                  Expanded(
                    flex: flexFor(i),
                    child: Text(row[i], style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _reportShell({
    required String title,
    required int records,
    required double units,
    required double total,
    required Widget child,
    required List<List<String>> pdfRows,
    List<String> headers = const [
      'BILL NO',
      'PARTICULARS',
      'RATE',
      'QTY',
      'AMOUNT',
    ],
    String? totalText,
  }) {
    return Padding(
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
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4)),
                        const SizedBox(height: 4),
                        Text(
                          'RECORDS: $records | UNITS: ${units.toStringAsFixed(3)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    color: AppColors.navy,
                    child: Text(
                      totalText ?? 'TOTAL: ₹${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
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
                onPressed: () => _printPdf(
                  title,
                  headers,
                  pdfRows,
                  total,
                  totalText: totalText,
                ),
                child: const Text('SHARE PDF — THEN PRINT FROM THE SHARE APP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printPdf(
    String title,
    List<String> headers,
    List<List<String>> rows,
    double total, {
    String? totalText,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text('JEWELLERY MANAGEMENT',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(title,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text(_filterLabel, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
          pw.Text(totalText ?? 'TOTAL: Rs. ${total.toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Text('No records')
          else
            pw.Table.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            ),
        ],
      ),
    );
    final bytes = await doc.save();
    await _shareBytes(bytes, title);
  }

  Future<void> _shareBytes(Uint8List bytes, String title) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${title.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: title,
      text:
          'Share this PDF first. Print it from WhatsApp, Files, or any printer app.',
    );
  }
}
