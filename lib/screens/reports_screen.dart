import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';
import '../widgets/app_shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _kind = 'SALES';
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  String? _customer;
  List<String> _customers = [];
  DateTime _pickedDate = DateTime.now();
  DateTime _pickedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final names =
        await DatabaseHelper.instance.getDistinctPartyNames(isCustomer: true);
    List<Map<String, dynamic>> rows;
    switch (_tab.index) {
      case 1:
        rows = await DatabaseHelper.instance.getTransactionsByDate(
          DateFormat('dd-MM-yyyy').format(_pickedDate),
        );
        rows = rows.where((r) => r['transactionType'] == _kind).toList();
        break;
      case 2:
        rows = await DatabaseHelper.instance.getTransactionsForMonth(
          _pickedMonth.month,
          _pickedMonth.year,
        );
        rows = rows.where((r) => r['transactionType'] == _kind).toList();
        break;
      case 3:
        if (_customer == null && names.isNotEmpty) {
          _customer = names.first;
        }
        rows = _customer == null
            ? []
            : await DatabaseHelper.instance.getTransactionsForParty(
                _customer!,
                transactionType: _kind,
              );
        break;
      case 0:
      default:
        rows = await DatabaseHelper.instance.getTransactionsByDate(
          DateFormat('dd-MM-yyyy').format(DateTime.now()),
        );
        rows = rows.where((r) => r['transactionType'] == _kind).toList();
        break;
    }
    if (!mounted) return;
    setState(() {
      _customers = names;
      _rows = rows;
      _loading = false;
    });
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _shareExcel() async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rows to share')),
      );
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln(
      'Bill No,Date,Name,Rate,Particulars,GWT,Touch,NWT,Payment,Amount,Balance,Balance Unit',
    );
    for (final row in _rows) {
      List<dynamic> items;
      try {
        items = jsonDecode((row['items'] ?? '[]').toString()) as List<dynamic>;
      } catch (_) {
        items = [];
      }
      if (items.isEmpty) {
        items = [
          {
            'type': '',
            'weight': 0,
            'touch': 0,
            'pureWt': 0,
            'rate': 0,
          }
        ];
      }
      for (final raw in items) {
        final item = raw is Map ? raw : <String, dynamic>{};
        buffer.writeln([
          row['billNo'],
          row['date'],
          row['partyName'],
          item['rate'],
          item['type'],
          formatWeight(item['weight']),
          formatWeight(item['touch']),
          formatWeight(item['pureWt']),
          row['paymentMode'],
          row['paymentAmount'],
          row['balance'],
          row['balanceUnit'],
        ].map((v) => _csvEscape(v?.toString() ?? '')).join(','));
      }
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_kind.toLowerCase()}_report.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$_kind Report',
      text: '$_kind report (Excel)',
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('SALES'),
                selected: _kind == 'SALES',
                onSelected: (_) {
                  setState(() => _kind = 'SALES');
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('PURCHASE'),
                selected: _kind == 'PURCHASE',
                onSelected: (_) {
                  setState(() => _kind = 'PURCHASE');
                  _reload();
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share, color: AppColors.navy),
                tooltip: 'Share Excel',
                onPressed: _shareExcel,
              ),
            ],
          ),
          if (_tab.index == 1)
            ListTile(
              dense: true,
              title: Text(
                  'Date: ${DateFormat('dd-MM-yyyy').format(_pickedDate)}'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _pickedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _pickedDate = picked);
                  _reload();
                }
              },
            ),
          if (_tab.index == 2)
            ListTile(
              dense: true,
              title: Text(
                  'Month: ${DateFormat('MMMM yyyy').format(_pickedMonth)}'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _pickedMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _pickedMonth = picked);
                  _reload();
                }
              },
            ),
          if (_tab.index == 3 && _customers.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _customer,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: _customers
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) {
                setState(() => _customer = v);
                _reload();
              },
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Text('No bills in this report',
            style: TextStyle(color: Colors.black54)),
      );
    }

    double totalGold = 0;
    double totalPaid = 0;
    double totalBalance = 0;
    for (final row in _rows) {
      totalGold += double.tryParse((row['totalPureWt'] ?? '0').toString()) ?? 0;
      totalPaid +=
          double.tryParse((row['paymentAmount'] ?? '0').toString()) ?? 0;
      totalBalance += double.tryParse((row['balance'] ?? '0').toString()) ?? 0;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFDCE8F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Total gold ${formatWeight(totalGold)}   '
            'Paid ${formatAmount(totalPaid)}   '
            'Balance ${formatAmount(totalBalance)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              fontSize: 12.5,
            ),
          ),
        ),
        for (final row in _rows)
          Card(
            child: ListTile(
              dense: true,
              title: Text(
                'Bill #${row['billNo']}  ${row['partyName'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${row['date']}  GWT/Wt ${row['totalWt']}  '
                'Pure ${row['totalPureWt']}\n'
                '${row['paymentMode']} ${row['paymentAmount']}  '
                'Bal ${row['balance'] ?? '0'} ${row['balanceUnit'] ?? ''}',
              ),
              isThreeLine: true,
            ),
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
        title: const Text('REPORTS'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'DAILY'),
            Tab(text: 'DATE WISE'),
            Tab(text: 'MONTH WISE'),
            Tab(text: 'CUSTOMER WISE'),
          ],
        ),
      ),
      body: Column(
        children: [
          _filters(),
          const Divider(height: 1),
          Expanded(child: _list()),
        ],
      ),
    );
  }
}
