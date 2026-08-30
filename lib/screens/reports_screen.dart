import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_helper.dart';
import '../logic/gold_ledger.dart';
import '../pdf/pdf_kit.dart';
import '../theme/app_theme.dart';
import '../util/platform_detect.dart';
import '../util/screen_activation.dart';
import '../widgets/party_options_overlay.dart';

enum _ReportTab {
  dailySales,
  billWise,
  salesReport,
  purchaseReport,
  receiptVoucherReport,
  paymentVoucherReport,
  customerLedger,
  supplierLedger,
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with ScreenActivationMixin<ReportsScreen> {
  _ReportTab _tab = _ReportTab.salesReport;
  DateTime _from = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _to = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _allHistory = false;
  bool _loading = true;

  List<Map<String, dynamic>> _txns = [];
  List<Map<String, dynamic>> _vouchers = [];
  Map<String, double> _rates = {};
  List<String> _customerNames = [];
  List<String> _supplierNames = [];

  bool _customerLedgerByName = false;
  bool _supplierLedgerByName = false;
  final _customerNameQuery = TextEditingController();
  final _supplierNameQuery = TextEditingController();

  static final _fmt = DateFormat('dd-MM-yyyy');
  static final _pretty = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _customerNameQuery.addListener(_onLedgerQueryChanged);
    _supplierNameQuery.addListener(_onLedgerQueryChanged);
    _load();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(ReportsScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    _load();
  }

  @override
  void dispose() {
    _customerNameQuery.removeListener(_onLedgerQueryChanged);
    _supplierNameQuery.removeListener(_onLedgerQueryChanged);
    _customerNameQuery.dispose();
    _supplierNameQuery.dispose();
    super.dispose();
  }

  void _onLedgerQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final txns = await DatabaseHelper.instance.getAllTransactions();
    final vouchers = await DatabaseHelper.instance.getVouchers();
    final rates = await DatabaseHelper.instance.getRatesMap();
    final customers = await DatabaseHelper.instance.getCustomers();
    final suppliers = await DatabaseHelper.instance.getSuppliers();
    if (!mounted) return;
    setState(() {
      _txns = txns;
      _vouchers = vouchers;
      _rates = rates;
      _customerNames = customers
          .map((r) => (r['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _supplierNames = suppliers
          .map((r) => (r['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
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
            tab(_ReportTab.salesReport, 'SALES'),
            tab(_ReportTab.purchaseReport, 'PURCHASE'),
            tab(_ReportTab.receiptVoucherReport, 'RECEIPT VOUCHER'),
            tab(_ReportTab.paymentVoucherReport, 'PAYMENT VOUCHER'),
            tab(_ReportTab.customerLedger, 'CUSTOMER LEDGER'),
            tab(_ReportTab.supplierLedger, 'SUPPLIER LEDGER'),
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
      case _ReportTab.salesReport:
        return _billAbstract(salesOnly: true, title: 'SALES REPORT');
      case _ReportTab.purchaseReport:
        return _billAbstract(
          salesOnly: false,
          purchasesOnly: true,
          title: 'PURCHASE REPORT',
        );
      case _ReportTab.receiptVoucherReport:
        return _voucherAbstract(
          voucherType: 'RECEIPT',
          title: 'RECEIPT VOUCHER REPORT',
        );
      case _ReportTab.paymentVoucherReport:
        return _voucherAbstract(
          voucherType: 'PAYMENT',
          title: 'PAYMENT VOUCHER REPORT',
        );
      case _ReportTab.customerLedger:
        return _partyLedgerRecords(customer: true);
      case _ReportTab.supplierLedger:
        return _partyLedgerRecords(customer: false);
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

  Widget _voucherAbstract({
    required String voucherType,
    required String title,
  }) {
    final goldRate = GoldLedger.goldRate(_rates);
    var rows = _filteredVouchers
        .where((r) => (r['voucherType'] ?? '').toString() == voucherType)
        .toList();
    rows = [...rows]..sort((a, b) {
        final an = a['voucherNo'] as int? ?? 0;
        final bn = b['voucherNo'] as int? ?? 0;
        return an.compareTo(bn);
      });

    double total = 0;
    double units = 0;
    final table = <List<String>>[];
    for (final voucher in rows) {
      final amount =
          double.tryParse((voucher['amount'] ?? '').toString()) ?? 0;
      final gold = goldPaidOnRow(voucher);
      total += voucherAmountRupees(voucher, goldRate);
      units += gold;
      final voucherNo = '$voucherType-${voucher['voucherNo']}';
      final name = '${voucher['partyName'] ?? ''}';
      final mode = paymentModeLabel(voucher['paymentMode']?.toString());
      table.add([
        voucherNo,
        name,
        voucher['date']?.toString() ?? '',
        mode,
        '${gold.toStringAsFixed(3)} g',
        mode == 'GOLD'
            ? '${amount.toStringAsFixed(3)} g'
            : 'Rs.${amount.toStringAsFixed(2)}',
      ]);
    }

    const headers = [
      'VOUCHER NO',
      'NAME',
      'DATE',
      'MODE',
      'GOLD',
      'AMOUNT',
    ];
    return _reportShell(
      title: title,
      records: rows.length,
      units: units,
      total: total,
      child: _htmlTable(
        table,
        headers: headers,
        columnFlex: const [2, 3, 2, 2, 2, 2],
      ),
      pdfRows: table,
      headers: headers,
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
      final billNo =
          '${bill['transactionType'] == 'PURCHASE' ? 'PUR' : 'SAL'}-${bill['billNo']}';
      final name = '${bill['partyName'] ?? ''}';
      final mode = paymentModeLabel(bill['paymentMode']?.toString());
      table.add([
        billNo,
        name,
        bill['date']?.toString() ?? '',
        mode,
        '${bill['totalPureWt']} g',
        'Rs.${bill['totalValue']}',
      ]);
    }

    const headers = [
      'BILL NO',
      'NAME',
      'DATE',
      'MODE',
      'WEIGHT',
      'AMOUNT',
    ];
    return _reportShell(
      title: title,
      records: rows.length,
      units: units,
      total: total,
      child: _htmlTable(table, headers: headers, columnFlex: const [2, 3, 2, 2, 2, 2]),
      pdfRows: table,
      headers: headers,
    );
  }

  Widget _ledgerModeBar({
    required bool byName,
    required TextEditingController query,
    required ValueChanged<bool> onModeChanged,
    required String nameHint,
    required List<String> partyNames,
    double goldRate = 0,
  }) {
    Iterable<String> nameOptions(String text) {
      final lower = text.trim().toLowerCase();
      if (lower.isEmpty) return const Iterable.empty();
      return partyNames
          .where((name) => name.toLowerCase().contains(lower))
          .take(12);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('ALL', () => onModeChanged(false), active: !byName),
          _chip('NAME', () => onModeChanged(true), active: byName),
          if (goldRate > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.headerBand,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'G.P RATE: ₹${goldRate.toStringAsFixed(2)}/g',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
          if (byName)
            SizedBox(
              width: 260,
              child: Autocomplete<String>(
                optionsViewOpenDirection: OptionsViewOpenDirection.down,
                initialValue: TextEditingValue(text: query.text),
                optionsBuilder: (value) => nameOptions(value.text),
                onSelected: (selection) {
                  query.text = selection;
                  setState(() {});
                },
                optionsViewBuilder: (context, onSelected, options) {
                  if (options.isEmpty) return const SizedBox.shrink();
                  return partyAutocompleteOptionsView(
                    context: context,
                    child: partyAutocompleteOptionsShell(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return partyAutocompleteOptionTile(
                            onSelected: () => onSelected(option),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                option,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                fieldViewBuilder:
                    (context, fieldController, focusNode, onAutocompleteSubmit) {
                  if (fieldController.text != query.text) {
                    fieldController.text = query.text;
                  }
                  return TextField(
                    controller: fieldController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: nameHint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (value) {
                      query.text = value;
                      setState(() {});
                    },
                    onSubmitted: (_) => onAutocompleteSubmit(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _partyLedgerRecords({required bool customer}) {
    final byName = customer ? _customerLedgerByName : _supplierLedgerByName;
    final query =
        customer ? _customerNameQuery.text : _supplierNameQuery.text;
    final goldRate = GoldLedger.goldRate(_rates);
    final sections = buildPartyLedgerSections(
      customer: customer,
      transactions: _txns,
      vouchers: _vouchers,
      from: _from,
      to: _to,
      allHistory: _allHistory,
      nameQuery: byName ? query : '',
      goldRate: goldRate,
    );
    final recordCount =
        sections.fold<int>(0, (sum, section) => sum + section.rows.length);
    final totalReceipt = sections.fold<double>(
      0,
      (sum, section) =>
          sum + section.rows.fold(0, (s, row) => s + row.receiptWeight),
    );
    final totalIssue = sections.fold<double>(
      0,
      (sum, section) =>
          sum + section.rows.fold(0, (s, row) => s + row.issueWeight),
    );
    final totalPure = sections.fold<double>(
      0,
      (sum, section) =>
          sum + section.rows.fold(0, (s, row) => s + row.pureGold),
    );
    const headers = [
      'DATE',
      'BILL NO',
      'NAME',
      'TYPE',
      'R.WEIGHT',
      'ISSUE WT',
      'PURE GOLD',
      'NARRATION',
    ];
    final pdfRows = [
      for (final section in sections) ...[
        [
          '',
          '',
          section.partyName,
          'OPENING',
          '',
          '',
          '',
          _signedLedgerBalance(section.openingBalance),
        ],
        ...section.toTableRows(),
        [
          '',
          '',
          section.partyName,
          'CLOSING',
          '',
          '',
          '',
          _signedLedgerBalance(section.closingBalance),
        ],
      ],
    ];
    final title =
        customer ? 'CUSTOMER LEDGER' : 'SUPPLIER LEDGER';
    final rateLabel = goldRate > 0
        ? 'G.P RATE: ₹${goldRate.toStringAsFixed(2)}/g  |  '
        : '';
    final totalText =
        '${rateLabel}'
        'R.WT: ${totalReceipt.toStringAsFixed(3)} g  |  '
        'ISSUE: ${totalIssue.toStringAsFixed(3)} g  |  '
        'PURE: ${totalPure.toStringAsFixed(3)} g';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ledgerModeBar(
          byName: byName,
          query: customer ? _customerNameQuery : _supplierNameQuery,
          nameHint: customer ? 'Customer name' : 'Supplier name',
          partyNames: customer ? _customerNames : _supplierNames,
          goldRate: goldRate,
          onModeChanged: (nameMode) => setState(() {
            if (customer) {
              _customerLedgerByName = nameMode;
              if (!nameMode) _customerNameQuery.clear();
            } else {
              _supplierLedgerByName = nameMode;
              if (!nameMode) _supplierNameQuery.clear();
            }
          }),
        ),
        Expanded(
          child: _reportShell(
            title: title,
            records: recordCount,
            units: totalPure,
            total: 0,
            totalText: totalText,
            child: _partyLedgerSectionsView(
              sections,
              headers: headers,
            ),
            pdfRows: pdfRows,
            headers: headers,
          ),
        ),
      ],
    );
  }

  String _signedLedgerBalance(double grams) {
    final sign = grams > 0 ? '+' : grams < 0 ? '' : '';
    return '$sign${grams.toStringAsFixed(3)} g';
  }

  Widget _partyLedgerSectionsView(
    List<PartyLedgerSection> sections, {
    required List<String> headers,
  }) {
    if (sections.isEmpty) {
      return const Center(child: Text('No records in this filter'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final section in sections) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.headerBand,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              section.partyName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.navy,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: Colors.white,
            ),
            child: Text(
              'Opening Balance: ${_signedLedgerBalance(section.openingBalance)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ledgerSectionTable(section, headers: headers),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: Colors.white,
            ),
            child: Text(
              'Closing Balance: ${_signedLedgerBalance(section.closingBalance)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ledgerSectionTable(
    PartyLedgerSection section, {
    required List<String> headers,
  }) {
    final rows = section.toTableRows();
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No transactions in this period',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
      );
    }
    return _htmlTable(
      rows,
      headers: headers,
      columnFlex: const [2, 1, 3, 2, 2, 2, 2, 3],
      includeOuterPadding: false,
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
      bool evenFlex = false,
      List<int>? columnFlex,
      bool includeOuterPadding = true}) {
    if (rows.isEmpty) {
      return const Center(child: Text('No records in this filter'));
    }
    int flexFor(int i) {
      if (columnFlex != null && i < columnFlex.length) return columnFlex[i];
      if (evenFlex) return 2;
      return i == 1 ? 4 : 2;
    }
    return ListView(
      padding: includeOuterPadding
          ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
          : EdgeInsets.zero,
      shrinkWrap: !includeOuterPadding,
      physics: includeOuterPadding ? null : const NeverScrollableScrollPhysics(),
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
    );
  }

  Future<void> _printPdf(
    String title,
    List<String> headers,
    List<List<String>> rows,
    double total, {
    String? totalText,
  }) async {
    final doc = await PdfKit.document();
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
            pw.TableHelper.fromTextArray(
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
    final file = await PdfKit.sharePdf(
      bytes: bytes,
      fileName: title,
      subject: title,
      text:
          'Share this PDF first. Print it from WhatsApp, Files, or any printer app.',
    );
    if (!mounted) return;
    if (!isMobileNative) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: ${file.path}')),
      );
    }
  }
}
