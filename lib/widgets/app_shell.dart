import 'package:flutter/material.dart';

import '../screens/backup_screen.dart';
import '../screens/customer_master_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/master_screen.dart';
import '../screens/opening_weight_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/supplier_master_screen.dart';
import '../screens/transaction_screen.dart';
import '../theme/app_theme.dart';

class NavItem {
  final IconData icon;
  final String label;
  final Widget page;

  NavItem({
    required this.icon,
    required this.label,
    required this.page,
  });
}

class ShellDrawerScope extends InheritedWidget {
  final VoidCallback openDrawer;

  const ShellDrawerScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  static ShellDrawerScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellDrawerScope>();
  }

  @override
  bool updateShouldNotify(ShellDrawerScope oldWidget) =>
      openDrawer != oldWidget.openDrawer;
}

class ShellNavigateScope extends InheritedWidget {
  final void Function(int index) goTo;

  const ShellNavigateScope({
    super.key,
    required this.goTo,
    required super.child,
  });

  static ShellNavigateScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavigateScope>();
  }

  @override
  bool updateShouldNotify(ShellNavigateScope oldWidget) =>
      goTo != oldWidget.goTo;
}

Widget? shellMenuButton(BuildContext context) {
  final shell = ShellDrawerScope.maybeOf(context);
  if (shell == null) return null;
  return IconButton(
    icon: const Icon(Icons.menu),
    tooltip: 'Menu',
    onPressed: shell.openDrawer,
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;
  late final List<NavItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      NavItem(
          icon: Icons.home_outlined,
          label: 'Home',
          page: const HomeScreen()),
      NavItem(
          icon: Icons.indeterminate_check_box_outlined,
          label: 'Sales',
          page: const TransactionScreen(kind: TransactionKind.sales)),
      NavItem(
          icon: Icons.add_box_outlined,
          label: 'Purchase',
          page: const TransactionScreen(kind: TransactionKind.purchase)),
      NavItem(
          icon: Icons.scale_outlined,
          label: 'Opening Weight',
          page: const OpeningWeightScreen()),
      NavItem(
          icon: Icons.currency_exchange,
          label: 'Master / Rates',
          page: const MasterScreen()),
      NavItem(
          icon: Icons.people_outlined,
          label: 'Customer Master',
          page: const CustomerMasterScreen()),
      NavItem(
          icon: Icons.local_shipping_outlined,
          label: 'Supplier Master',
          page: const SupplierMasterScreen()),
      NavItem(
          icon: Icons.bar_chart_outlined,
          label: 'Reports',
          page: const ReportsScreen()),
      NavItem(
          icon: Icons.history,
          label: 'Rate Records',
          page: const HistoryScreen()),
      NavItem(
          icon: Icons.backup_outlined,
          label: 'Backup',
          page: const BackupScreen()),
    ];
  }

  void _logout() {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    final pages = IndexedStack(
      index: _index,
      children: _items.map((item) => item.page).toList(),
    );

    final sidebar = Material(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.navy,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
            child: const Text(
              'JEWELLERY\nMANAGEMENT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.3,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final selected = index == _index;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: const Color(0xFFDCE8F5),
                  leading: Icon(
                    item.icon,
                    color: selected ? AppColors.navy : AppColors.mutedBlue,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                  ),
                  onTap: () {
                    setState(() => _index = index);
                    if (!wide) {
                      Navigator.of(context).maybePop();
                    }
                  },
                );
              },
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout, color: AppColors.mutedBlue),
            title: const Text('Logout', style: TextStyle(fontSize: 13)),
            onTap: _logout,
          ),
        ],
      ),
    );

    Widget shell = wide
        ? Scaffold(
            body: Row(
              children: [
                SizedBox(width: 240, child: sidebar),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: pages),
              ],
            ),
          )
        : ShellDrawerScope(
            openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            child: Scaffold(
              key: _scaffoldKey,
              drawer: Drawer(child: sidebar),
              body: pages,
            ),
          );

    return ShellNavigateScope(
      goTo: (index) => setState(() => _index = index),
      child: shell,
    );
  }
}
