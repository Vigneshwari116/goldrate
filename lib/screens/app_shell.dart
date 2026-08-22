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
import 'reports_screen.dart';
import 'stock_screen.dart';
import 'supplier_master_screen.dart';
import 'transaction_screen.dart';
import 'voucher_screen.dart';

enum AppPage {
  home,
  sales,
  purchase,
  receipt,
  stock,
  rates,
  customers,
  suppliers,
  reports,
  rateRecords,
  openingWeight,
  backup,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialPage = AppPage.home});

  final AppPage initialPage;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppPage _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  String get _title {
    switch (_page) {
      case AppPage.home:
        return 'HOME';
      case AppPage.sales:
        return 'SALES';
      case AppPage.purchase:
        return 'PURCHASE';
      case AppPage.receipt:
        return 'RECEIPT VOUCHER';
      case AppPage.stock:
        return 'STOCK';
      case AppPage.rates:
        return 'MASTER / RATES';
      case AppPage.customers:
        return 'CUSTOMER MASTER';
      case AppPage.suppliers:
        return 'SUPPLIER MASTER';
      case AppPage.reports:
        return 'DAILY REPORTS';
      case AppPage.rateRecords:
        return 'RATE RECORDS';
      case AppPage.openingWeight:
        return 'OPENING WEIGHT';
      case AppPage.backup:
        return 'BACKUP';
    }
  }

  void _go(AppPage page) {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
    setState(() => _page = page);
  }

  void _logout() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _body() {
    switch (_page) {
      case AppPage.home:
        return HomeScreen(onOpen: _go);
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
      case AppPage.stock:
        return const StockScreen(embedded: true);
      case AppPage.rates:
        return const MasterScreen(embedded: true);
      case AppPage.customers:
        return const CustomerMasterScreen(embedded: true);
      case AppPage.suppliers:
        return const SupplierMasterScreen(embedded: true);
      case AppPage.reports:
        return const ReportsScreen(embedded: true);
      case AppPage.rateRecords:
        return const HistoryScreen(embedded: true);
      case AppPage.openingWeight:
        return const OpeningWeightScreen(embedded: true);
      case AppPage.backup:
        return const BackupScreen(embedded: true);
    }
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required AppPage page,
  }) {
    final selected = _page == page;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.drawerActive,
      leading: Icon(icon, color: Colors.white, size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
      ),
      onTap: () => _go(page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
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
      drawer: Drawer(
        backgroundColor: AppColors.drawerNavy,
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'JEWELLERY MANAGEMENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: ListView(
                  children: [
                    _drawerItem(
                        icon: Icons.home, label: 'Home', page: AppPage.home),
                    _drawerItem(
                        icon: Icons.indeterminate_check_box,
                        label: 'Sales',
                        page: AppPage.sales),
                    _drawerItem(
                        icon: Icons.add_box,
                        label: 'Purchase',
                        page: AppPage.purchase),
                    _drawerItem(
                        icon: Icons.receipt_long,
                        label: 'Receipt Voucher',
                        page: AppPage.receipt),
                    _drawerItem(
                        icon: Icons.inventory_2,
                        label: 'Stock',
                        page: AppPage.stock),
                    _drawerItem(
                        icon: Icons.currency_exchange,
                        label: 'Master / Rates',
                        page: AppPage.rates),
                    _drawerItem(
                        icon: Icons.people,
                        label: 'Customer Master',
                        page: AppPage.customers),
                    _drawerItem(
                        icon: Icons.local_shipping,
                        label: 'Supplier Master',
                        page: AppPage.suppliers),
                    _drawerItem(
                        icon: Icons.bar_chart,
                        label: 'Reports',
                        page: AppPage.reports),
                    _drawerItem(
                        icon: Icons.history,
                        label: 'Rate Records',
                        page: AppPage.rateRecords),
                    _drawerItem(
                        icon: Icons.scale,
                        label: 'Opening Weight',
                        page: AppPage.openingWeight),
                    _drawerItem(
                        icon: Icons.backup,
                        label: 'Backup',
                        page: AppPage.backup),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white70, size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: KeyedSubtree(
        key: ValueKey(_page),
        child: _body(),
      ),
    );
  }
}
