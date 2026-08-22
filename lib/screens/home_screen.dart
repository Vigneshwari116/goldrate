import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';
import '../utils/stock_ledger.dart';
import 'master_screen.dart';
import 'opening_weight_screen.dart';
import '../widgets/app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastDate = '';
  bool _openingWeightSet = true;
  bool _loading = true;
  List<StockSummaryRow> _stock = [];

  bool get _ratesSetToday {
    final today = DateFormat("dd-MM-yyyy").format(DateTime.now());
    return _lastDate == today;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await DatabaseHelper.instance.getUpdateStats();
    final opening = await DatabaseHelper.instance.getOpeningWeight();
    final stock = await DatabaseHelper.instance.getStockSummary();
    if (!mounted) return;
    setState(() {
      _lastDate = stats['lastDate'] as String;
      _openingWeightSet = opening != null;
      _stock = stock;
      _loading = false;
    });
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }

  void _goShell(int index) {
    ShellNavigateScope.maybeOf(context)?.goTo(index);
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

  Widget _buildPrimaryColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Every single day until today's rates are saved — checked
        // first, since nothing can be priced correctly until this
        // is done.
        if (!_ratesSetToday)
          _banner(
            icon: Icons.currency_exchange,
            text: _lastDate.isEmpty
                ? "Rates not set yet — tap to enter today's rates"
                : "Today's rates not set yet (last set $_lastDate) — "
                "tap to update",
            background: const Color(0xFFDCE8F5),
            foreground: AppColors.navy,
            onTap: () => _open(const MasterScreen()),
          ),
        // Day-one only — vanishes forever once saved.
        if (!_openingWeightSet)
          _banner(
            icon: Icons.scale,
            text: "Opening weight not set yet — tap to enter your "
                "starting stock and cash",
            background: Colors.amber[100]!,
            foreground: Colors.brown,
            onTap: () => _open(const OpeningWeightScreen()),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _PrimaryTile(
                icon: Icons.add_box,
                label: "PURCHASE",
                subtitle: "Stock coming in",
                color: AppColors.navy,
                onTap: () => _goShell(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryTile(
                icon: Icons.indeterminate_check_box,
                label: "SALES",
                subtitle: "Stock going out",
                color: AppColors.mutedBlue,
                onTap: () => _goShell(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: () => _goShell(3),
          child: const Text(
            'CURRENT STOCK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.mutedBlue,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in _stock)
              SizedBox(
                width: 160,
                child: Material(
                  color: AppColors.cardWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: InkWell(
                    onTap: () => _goShell(3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatWeight(row.current),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            'Open ${formatWeight(row.opening)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text("HOME"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: _buildPrimaryColumn(),
            ),
          );
        },
      ),
    );
  }
}

class _PrimaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PrimaryTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
