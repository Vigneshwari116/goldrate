import 'package:flutter/material.dart';
import 'package:grate_app/theme/responsive.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpen, this.embedded = false});

  final void Function(AppPage page)? onOpen;
  final bool embedded;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, String> _rates = {};
  Map<String, double> _stock = {};
  String _lastDate = '';
  String _lastTime = '';
  bool _openingWeightSet = true;
  bool _loading = true;

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
    final rows = await DatabaseHelper.instance.getRates();
    final stats = await DatabaseHelper.instance.getUpdateStats();
    final opening = await DatabaseHelper.instance.getOpeningWeight();
    final stock = await DatabaseHelper.instance.getCurrentStock();
    if (!mounted) return;
    setState(() {
      _rates = {
        for (final r in rows)
          (r['rateName'] ?? '').toString(): (r['rateValue'] ?? '').toString()
      };
      _lastDate = stats['lastDate'] as String;
      _lastTime = stats['lastTime'] as String;
      _openingWeightSet = opening != null;
      _stock = stock;
      _loading = false;
    });
  }

  void _open(AppPage page) {
    if (widget.onOpen != null) {
      widget.onOpen!(page);
      return;
    }
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
            onTap: () => _open(AppPage.rates),
          ),
        // Day-one only — vanishes forever once saved.
        if (!_openingWeightSet)
          _banner(
            icon: Icons.scale,
            text: "Opening weight not set yet — tap to enter your "
                "starting stock and cash",
            background: Colors.amber[100]!,
            foreground: Colors.brown,
            onTap: () => _open(AppPage.openingWeight),
          ),
        const SizedBox(height: 14),
        Text(
          _lastTime.isEmpty
              ? "Live stock  ·  GWT ${(_stock['GWT'] ?? 0).toStringAsFixed(2)}  "
                  "FWT ${(_stock['FWT'] ?? 0).toStringAsFixed(2)}  "
                  "KWT ${(_stock['KWT'] ?? 0).toStringAsFixed(2)}  "
                  "SWT ${(_stock['SWT'] ?? 0).toStringAsFixed(2)}"
              : "Live stock  ·  GWT ${(_stock['GWT'] ?? 0).toStringAsFixed(2)}  "
                  "FWT ${(_stock['FWT'] ?? 0).toStringAsFixed(2)}  "
                  "KWT ${(_stock['KWT'] ?? 0).toStringAsFixed(2)}  "
                  "SWT ${(_stock['SWT'] ?? 0).toStringAsFixed(2)}"
                  "${_rates['G.P RATE'] != null ? '  ·  G.P ${_rates['G.P RATE']}' : ''}"
                  "  ·  rates $_lastTime",
          style: const TextStyle(fontSize: 12, color: AppColors.mutedBlue),
        ),
        Row(
          children: [
            Expanded(
              child: _PrimaryTile(
                icon: Icons.add_box,
                label: "PURCHASE",
                subtitle: "Stock coming in",
                color: AppColors.navy,
                onTap: () => _open(AppPage.purchase),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryTile(
                icon: Icons.indeterminate_check_box,
                label: "SALES",
                subtitle: "Stock going out",
                color: AppColors.mutedBlue,
                onTap: () => _open(AppPage.sales),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManageColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "MANAGE",
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.mutedBlue),
        ),
        const SizedBox(height: 8),
        _SecondaryTile(
          icon: Icons.people,
          label: "Customer Master",
          onTap: () => _open(AppPage.customers),
        ),
        _SecondaryTile(
          icon: Icons.local_shipping,
          label: "Supplier Master",
          onTap: () => _open(AppPage.suppliers),
        ),
        _SecondaryTile(
          icon: Icons.scale,
          label: "Opening Weight",
          onTap: () => _open(AppPage.openingWeight),
        ),
        _SecondaryTile(
          icon: Icons.receipt_long,
          label: "Receipt Voucher",
          onTap: () => _open(AppPage.receipt),
        ),
        _SecondaryTile(
          icon: Icons.bar_chart,
          label: "Daily Reports",
          onTap: () => _open(AppPage.reports),
        ),
        _SecondaryTile(
          icon: Icons.inventory_2,
          label: "Stock",
          onTap: () => _open(AppPage.stock),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SplitLayout(
              primaryWidth: 420,
              primary: _buildPrimaryColumn(),
              secondary: _buildManageColumn(),
            ),
          );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("HOME")),
      body: content,
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

class _SecondaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: AppColors.navy, size: 20),
        title: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        trailing:
        const Icon(Icons.chevron_right, color: AppColors.mutedBlue, size: 20),
        onTap: onTap,
      ),
    );
  }
}
