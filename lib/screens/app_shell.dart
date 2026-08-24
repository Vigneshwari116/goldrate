import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'backup_screen.dart';
import 'customer_master_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'master_screen.dart';
import 'opening_weight_screen.dart';
import 'printer_settings_screen.dart';
import 'reports_screen.dart';
import 'stock_screen.dart';
import 'supplier_master_screen.dart';
import 'transaction_screen.dart';
import 'voucher_screen.dart';

enum AppPage {
  home,
  openingWeight,
  stock,
  sales,
  purchase,
  receipt,
  customers,
  suppliers,
  rates,
  reports,
  rateRecords,
  backup,
  printerSettings,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialPage = AppPage.home});

  final AppPage initialPage;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppPage _page;
  bool _navOpen = true;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  String get _title {
    switch (_page) {
      case AppPage.home:
        return 'HOME';
      case AppPage.openingWeight:
        return 'OPENING WEIGHT';
      case AppPage.stock:
        return 'STOCK';
      case AppPage.sales:
        return 'SALES';
      case AppPage.purchase:
        return 'PURCHASE';
      case AppPage.receipt:
        return 'RECEIPT VOUCHER';
      case AppPage.customers:
        return 'CUSTOMER MASTER';
      case AppPage.suppliers:
        return 'SUPPLIER MASTER';
      case AppPage.rates:
        return 'DAILY RATE';
      case AppPage.reports:
        return 'DAILY REPORTS';
      case AppPage.rateRecords:
        return 'RATE RECORDS';
      case AppPage.backup:
        return 'BACKUP';
      case AppPage.printerSettings:
        return 'PRINTER SETTINGS';
    }
  }

  void _go(AppPage page) {
    setState(() => _page = page);
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Sign out of jewellery management?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _body() {
    switch (_page) {
      case AppPage.home:
        return HomeScreen(onOpen: _go);
      case AppPage.openingWeight:
        return const OpeningWeightScreen(embedded: true);
      case AppPage.stock:
        return const StockScreen(embedded: true);
      case AppPage.sales:
        return const TransactionScreen(
          kind: TransactionKind.sales,
          embedded: true,
        );
      case AppPage.purchase:
        return const TransactionScreen(
          kind: TransactionKind.purchase,
          embedded: true,
        );
      case AppPage.receipt:
        return const VoucherScreen(embedded: true);
      case AppPage.customers:
        return const CustomerMasterScreen(embedded: true);
      case AppPage.suppliers:
        return const SupplierMasterScreen(embedded: true);
      case AppPage.rates:
        return const MasterScreen(embedded: true);
      case AppPage.reports:
        return const ReportsScreen(embedded: true);
      case AppPage.rateRecords:
        return const HistoryScreen(embedded: true);
      case AppPage.backup:
        return const BackupScreen(embedded: true);
      case AppPage.printerSettings:
        return const PrinterSettingsScreen(embedded: true);
    }
  }

  Widget _leaf({
    required IconData icon,
    required String label,
    required AppPage page,
    bool nested = true,
  }) {
    final selected = _page == page;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.drawerActive,
      contentPadding:
          EdgeInsets.only(left: nested ? 28 : 12, right: 12),
      leading: Icon(icon, color: Colors.white, size: 18),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      onTap: () => _go(page),
    );
  }

  Widget _group({
    required IconData icon,
    required String label,
    required List<AppPage> pages,
    required List<Widget> children,
  }) {
    final open = pages.contains(_page);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>(label),
        initiallyExpanded: true,
        maintainState: true,
        leading: Icon(icon, color: Colors.white70, size: 20),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white70,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          label,
          style: TextStyle(
            color: open ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        children: children,
      ),
    );
  }

  Widget _sidebar() {
    return ColoredBox(
      color: AppColors.drawerNavy,
      child: SafeArea(
        child: SizedBox(
          width: 252,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'NAVIGATION',
                    style: TextStyle(
                      color: Color(0xFF9EC4DC),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _leaf(
                        icon: Icons.home,
                        label: 'Home',
                        page: AppPage.home,
                        nested: false),
                    _group(
                      icon: Icons.inventory_2,
                      label: 'INVENTORY',
                      pages: const [AppPage.openingWeight, AppPage.stock],
                      children: [
                        _leaf(
                            icon: Icons.scale,
                            label: 'Opening Weight',
                            page: AppPage.openingWeight),
                        _leaf(
                            icon: Icons.inventory_2,
                            label: 'Stock',
                            page: AppPage.stock),
                      ],
                    ),
                    _group(
                      icon: Icons.swap_horiz,
                      label: 'TRANSACTIONS',
                      pages: const [
                        AppPage.sales,
                        AppPage.purchase,
                        AppPage.receipt
                      ],
                      children: [
                        _leaf(
                            icon: Icons.indeterminate_check_box,
                            label: 'Sales',
                            page: AppPage.sales),
                        _leaf(
                            icon: Icons.add_box,
                            label: 'Purchase',
                            page: AppPage.purchase),
                        _leaf(
                            icon: Icons.receipt_long,
                            label: 'Receipt Voucher',
                            page: AppPage.receipt),
                      ],
                    ),
                    _group(
                      icon: Icons.menu_book,
                      label: 'MASTERS',
                      pages: const [
                        AppPage.customers,
                        AppPage.suppliers,
                        AppPage.rates
                      ],
                      children: [
                        _leaf(
                            icon: Icons.people,
                            label: 'Customer Master',
                            page: AppPage.customers),
                        _leaf(
                            icon: Icons.local_shipping,
                            label: 'Supplier Master',
                            page: AppPage.suppliers),
                        _leaf(
                            icon: Icons.currency_exchange,
                            label: 'Daily Rate',
                            page: AppPage.rates),
                      ],
                    ),
                    _group(
                      icon: Icons.bar_chart,
                      label: 'REPORTS & AUDIT',
                      pages: const [AppPage.reports, AppPage.rateRecords],
                      children: [
                        _leaf(
                            icon: Icons.assessment,
                            label: 'Reports',
                            page: AppPage.reports),
                        _leaf(
                            icon: Icons.history,
                            label: 'Rate Records',
                            page: AppPage.rateRecords),
                      ],
                    ),
                    _group(
                      icon: Icons.settings,
                      label: 'SETTINGS',
                      pages: const [AppPage.backup, AppPage.printerSettings],
                      children: [
                        _leaf(
                            icon: Icons.backup,
                            label: 'Backup',
                            page: AppPage.backup),
                        _leaf(
                            icon: Icons.print,
                            label: 'Printer Settings',
                            page: AppPage.printerSettings),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              ListTile(
                leading:
                    const Icon(Icons.logout, color: Color(0xFFFF8A80), size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_navOpen ? Icons.menu_open : Icons.menu),
          tooltip: _navOpen ? 'Hide menu' : 'Show menu',
          onPressed: () => setState(() => _navOpen = !_navOpen),
        ),
        title: Column(
          children: [
            Text(_title),
            Text(
              today.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          if (_navOpen) _sidebar(),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_page),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }
}
