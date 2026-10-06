import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../navigation/app_page.dart';
import '../theme/app_theme.dart';
import '../util/screen_activation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpen,
    this.embedded = false,
    this.isActive = true,
  });

  final void Function(AppPage page)? onOpen;
  final bool embedded;
  final bool isActive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with ScreenActivationMixin<HomeScreen> {
  Map<String, String> _rates = {};
  Map<String, double> _stock = {};
  String _lastDate = '';
  bool _openingWeightSet = true;
  bool _loading = true;
  double _todaySalesAmount = 0;
  double _todaySalesGrams = 0;
  int _todaySalesBills = 0;
  double _todayPurchaseAmount = 0;
  double _todayPurchaseGrams = 0;
  int _todayPurchaseBills = 0;
  double _todayCreditGrams = 0;
  int _customerCount = 0;
  int _supplierCount = 0;

  bool get _ratesSetToday {
    final today = DateFormat("dd-MM-yyyy").format(DateTime.now());
    return _lastDate == today;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(HomeScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    _load();
  }

  Future<void> _load() async {
    final today = DateFormat("dd-MM-yyyy").format(DateTime.now());
    final rows = await DatabaseHelper.instance.getRates();
    final stats = await DatabaseHelper.instance.getUpdateStats();
    final opening = await DatabaseHelper.instance.getOpeningWeight();
    final stock = await DatabaseHelper.instance.getCurrentStock();
    final bills = await DatabaseHelper.instance.getTransactionsByDate(today);
    final customers = await DatabaseHelper.instance.getCustomers();
    final suppliers = await DatabaseHelper.instance.getSuppliers();

    double salesAmt = 0, salesG = 0, purchaseAmt = 0, purchaseG = 0, creditG = 0;
    var salesBills = 0;
    var purchaseBills = 0;
    for (final bill in bills) {
      final amt = double.tryParse((bill['totalValue'] ?? '').toString()) ?? 0;
      final g = double.tryParse((bill['totalPureWt'] ?? '').toString()) ?? 0;
      final paid = double.tryParse((bill['paymentAmount'] ?? '').toString()) ?? 0;
      if (bill['transactionType'] == 'SALES') {
        salesBills++;
        salesAmt += amt;
        salesG += g;
        if (amt - paid > 0.01) {
          final oldG = double.tryParse((bill['oldGrams'] ?? '').toString()) ?? 0;
          final newG = double.tryParse((bill['newGrams'] ?? '').toString()) ?? 0;
          creditG += (newG - oldG).abs();
        }
      } else if (bill['transactionType'] == 'PURCHASE') {
        purchaseBills++;
        purchaseAmt += amt;
        purchaseG += g;
      }
    }

    if (!mounted) return;
    setState(() {
      _rates = {
        for (final r in rows)
          (r['rateName'] ?? '').toString(): (r['rateValue'] ?? '').toString()
      };
      _lastDate = stats['lastDate'] as String;
      _openingWeightSet = opening != null;
      _stock = stock;
      _todaySalesAmount = salesAmt;
      _todaySalesGrams = salesG;
      _todaySalesBills = salesBills;
      _todayPurchaseAmount = purchaseAmt;
      _todayPurchaseGrams = purchaseG;
      _todayPurchaseBills = purchaseBills;
      _todayCreditGrams = creditG;
      _customerCount = customers.map((c) => c['name']).toSet().length;
      _supplierCount = suppliers.map((s) => s['name']).toSet().length;
      _loading = false;
    });
  }

  void _open(AppPage page) {
    widget.onOpen?.call(page);
  }

  Widget _banner({
    required IconData icon,
    required String text,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: foreground),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }

  Widget _kpi({
    required String label,
    required String value,
    required String detail,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = _rates['G.P RATE'] ?? '—';
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final cross = wide ? 3 : 2;
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                children: [
                  const Text(
                    'Use the menu on the left. Opening Weight is under Inventory, just below Home.',
                    style: TextStyle(fontSize: 12, color: AppColors.mutedBlue),
                  ),
                  const SizedBox(height: 8),
                  if (!_ratesSetToday)
                    _banner(
                      icon: Icons.currency_exchange,
                      text: _lastDate.isEmpty
                          ? "Rates not set yet — tap to enter today's rates"
                          : "Today's rates not set yet (last set $_lastDate) — tap to update",
                      background: const Color(0xFFDCE8F5),
                      foreground: AppColors.navy,
                      onTap: () => _open(AppPage.rates),
                    ),
                  if (!_openingWeightSet)
                    _banner(
                      icon: Icons.scale,
                      text:
                          "Opening weight not set yet — tap to enter starting stock and cash",
                      background: const Color(0xFFDCE8F5),
                      foreground: AppColors.navy,
                      onTap: () => _open(AppPage.openingWeight),
                    ),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: cross,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: wide ? 2.8 : 2.2,
                    children: [
                      _kpi(
                        label: "TODAY'S SALES",
                        value: "₹${_todaySalesAmount.toStringAsFixed(2)}",
                        detail:
                            "$_todaySalesBills bills  ·  ${_todaySalesGrams.toStringAsFixed(3)} g",
                      ),
                      _kpi(
                        label: "TODAY'S PURCHASE",
                        value: "₹${_todayPurchaseAmount.toStringAsFixed(2)}",
                        detail:
                            "$_todayPurchaseBills bills  ·  ${_todayPurchaseGrams.toStringAsFixed(3)} g",
                      ),
                      _kpi(
                        label: 'CURRENT STOCK',
                        value:
                            "${(_stock['GWT'] ?? 0).toStringAsFixed(3)} g GWT",
                        detail:
                            "FWT ${(_stock['FWT'] ?? 0).toStringAsFixed(3)}  ·  "
                            "KWT ${(_stock['KWT'] ?? 0).toStringAsFixed(3)}  ·  "
                            "SWT ${(_stock['SWT'] ?? 0).toStringAsFixed(3)}",
                      ),
                      _kpi(
                        label: "TODAY'S CREDIT (UNPAID SALES)",
                        value: "${_todayCreditGrams.toStringAsFixed(3)} g",
                        detail: 'Gold still due on sales saved today',
                      ),
                      _kpi(
                        label: "TODAY'S G.P RATE",
                        value: gp.toString(),
                        detail: _ratesSetToday
                            ? 'Used to convert cash into gold'
                            : 'Set rates from Daily Rate',
                      ),
                      _kpi(
                        label: 'PARTIES ON FILE',
                        value: '$_customerCount / $_supplierCount',
                        detail: 'Customers  ·  Suppliers',
                      ),
                    ],
                  ),
                ],
              );
            },
          );

    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("HOME")),
      body: content,
    );
  }
}
