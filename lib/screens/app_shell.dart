import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../navigation/app_page.dart';
import '../theme/app_theme.dart';
import '../util/session_prefs.dart';
import 'backup_screen.dart';
import 'customer_master_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'master_screen.dart';
import 'opening_weight_screen.dart';
import 'printer_settings_screen.dart';
import 'reports_screen.dart';
import 'reset_screen.dart';
import 'supplier_master_screen.dart';
import 'transaction_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialPage = AppPage.home});

  final AppPage initialPage;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppPage _page;
  bool _navOpen = false;
  int _sessionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    SessionPrefs.setLastPage(widget.initialPage);
  }

  String get _title {
    switch (_page) {
      case AppPage.home:
        return 'HOME';
      case AppPage.openingWeight:
        return 'OPENING WEIGHT';
      case AppPage.sales:
        return 'SALES';
      case AppPage.purchase:
        return 'PURCHASE';
      case AppPage.receipt:
        return 'RECEIPT VOUCHER';
      case AppPage.payment:
        return 'PAYMENT VOUCHER';
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
      case AppPage.reset:
        return 'RESET';
    }
  }

  void resetSession() {
    setState(() {
      _sessionGeneration++;
      _page = AppPage.home;
      _navOpen = false;
    });
    SessionPrefs.setLastPage(AppPage.home);
  }

  Future<void> _resetSessionAndForms() async {
    resetSession();
  }

  void _go(AppPage page) {
    setState(() => _page = page);
    SessionPrefs.setLastPage(page);
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
    await SessionPrefs.setLoggedIn(false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  static const _pageOrder = [
    AppPage.home,
    AppPage.openingWeight,
    AppPage.sales,
    AppPage.purchase,
    AppPage.receipt,
    AppPage.payment,
    AppPage.customers,
    AppPage.suppliers,
    AppPage.rates,
    AppPage.reports,
    AppPage.rateRecords,
    AppPage.backup,
    AppPage.printerSettings,
    AppPage.reset,
  ];

  int get _pageIndex {
    final i = _pageOrder.indexOf(_page);
    return i < 0 ? 0 : i;
  }

  Widget _body() {
    return IndexedStack(
      key: ValueKey(_sessionGeneration),
      index: _pageIndex,
      children: [
        _KeepAlivePage(child: _HomePage()),
        _KeepAlivePage(child: OpeningWeightScreen(embedded: true)),
        _KeepAlivePage(
          child: TransactionScreen(
            kind: TransactionKind.sales,
            embedded: true,
            isActive: _page == AppPage.sales,
          ),
        ),
        _KeepAlivePage(
          child: TransactionScreen(
            kind: TransactionKind.purchase,
            embedded: true,
            isActive: _page == AppPage.purchase,
          ),
        ),
        _KeepAlivePage(
          child: TransactionScreen(
            kind: TransactionKind.receiptVoucher,
            embedded: true,
            isActive: _page == AppPage.receipt,
          ),
        ),
        _KeepAlivePage(
          child: TransactionScreen(
            kind: TransactionKind.paymentVoucher,
            embedded: true,
            isActive: _page == AppPage.payment,
          ),
        ),
        _KeepAlivePage(
          child: CustomerMasterScreen(
            embedded: true,
            isActive: _page == AppPage.customers,
          ),
        ),
        _KeepAlivePage(
          child: SupplierMasterScreen(
            embedded: true,
            isActive: _page == AppPage.suppliers,
          ),
        ),
        _KeepAlivePage(child: MasterScreen(embedded: true)),
        _KeepAlivePage(
          child: ReportsScreen(
            embedded: true,
            isActive: _page == AppPage.reports,
          ),
        ),
        _KeepAlivePage(child: HistoryScreen(embedded: true)),
        _KeepAlivePage(child: BackupScreen(embedded: true)),
        _KeepAlivePage(child: PrinterSettingsScreen(embedded: true)),
        _KeepAlivePage(child: _ResetPage()),
      ],
    );
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
        initiallyExpanded: false,
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

  Widget _railButton({
    required IconData icon,
    required String tooltip,
    required AppPage page,
  }) {
    final selected = _page == page;
    return IconButton(
      tooltip: tooltip,
      onPressed: () => _go(page),
      icon: Icon(
        icon,
        color: selected ? Colors.white : Colors.white70,
        size: 22,
      ),
      style: IconButton.styleFrom(
        backgroundColor:
            selected ? AppColors.drawerActive : Colors.transparent,
        fixedSize: const Size(56, 44),
        shape: const RoundedRectangleBorder(),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _sidebarRail() {
    const mainPages = <(IconData, String, AppPage)>[
      (Icons.home, 'Home', AppPage.home),
      (Icons.indeterminate_check_box, 'Sales', AppPage.sales),
      (Icons.add_box, 'Purchase', AppPage.purchase),
      (Icons.receipt_long, 'Receipt Voucher', AppPage.receipt),
      (Icons.payments, 'Payment Voucher', AppPage.payment),
      (Icons.people, 'Customer Master', AppPage.customers),
      (Icons.assessment, 'Reports', AppPage.reports),
    ];

    return Material(
      color: AppColors.drawerNavy,
      child: SafeArea(
        child: SizedBox(
          width: 56,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 8),
                  children: [
                    for (final page in mainPages)
                      _railButton(
                        icon: page.$1,
                        tooltip: page.$2,
                        page: page.$3,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Logout',
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Color(0xFFFF8A80), size: 22),
                style: IconButton.styleFrom(
                  fixedSize: const Size(56, 44),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar() {
    return Material(
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
                    _leaf(
                        icon: Icons.scale,
                        label: 'Opening Weight',
                        page: AppPage.openingWeight),
                    _group(
                      icon: Icons.swap_horiz,
                      label: 'TRANSACTIONS',
                      pages: const [
                        AppPage.sales,
                        AppPage.purchase,
                        AppPage.receipt,
                        AppPage.payment,
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
                        _leaf(
                            icon: Icons.payments,
                            label: 'Payment Voucher',
                            page: AppPage.payment),
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
                      pages: const [
                        AppPage.backup,
                        AppPage.printerSettings,
                        AppPage.reset,
                      ],
                      children: [
                        _leaf(
                            icon: Icons.backup,
                            label: 'Backup',
                            page: AppPage.backup),
                        _leaf(
                            icon: Icons.print,
                            label: 'Printer Settings',
                            page: AppPage.printerSettings),
                        _leaf(
                            icon: Icons.restart_alt,
                            label: 'Reset',
                            page: AppPage.reset),
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
          if (_navOpen) _sidebar() else _sidebarRail(),
          Expanded(
            child: _body(),
          ),
        ],
      ),
    );
  }
}

/// Home needs navigation callback from AppShell — wired via InheritedWidget
/// so the page can stay alive inside IndexedStack.
class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_AppShellState>();
    return HomeScreen(
      onOpen: shell?._go ?? (_) {},
      embedded: true,
      isActive: shell?._page == AppPage.home,
    );
  }
}

class _ResetPage extends StatelessWidget {
  const _ResetPage();

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_AppShellState>();
    return ResetScreen(
      embedded: true,
      onSessionReset: shell?._resetSessionAndForms,
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
