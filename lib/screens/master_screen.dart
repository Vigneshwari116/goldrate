import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/number_format.dart';
import '../widgets/app_shell.dart';
import 'history_screen.dart';
import 'customer_master_screen.dart';
import 'supplier_master_screen.dart';
import 'opening_weight_screen.dart';

/// Rates ONLY. This screen does one job — enter/update today's four
/// rates — and nothing else. It's visited once a day, briefly, then
/// left. Purchase/Sales live on Home, not here, so this form is never
/// sitting on screen when staff is mid-billing.
class MasterScreen extends StatefulWidget {
  const MasterScreen({super.key});

  @override
  State<MasterScreen> createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  List<Map<String, dynamic>> rates = [];
  final Map<int, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;

  String _lastDate = '';
  String _lastTime = '';

  @override
  void initState() {
    super.initState();
    loadRates();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadRates() async {
    final data = await DatabaseHelper.instance.getRates();
    final stats = await DatabaseHelper.instance.getUpdateStats();

    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    for (final item in data) {
      _controllers[item['id']] = TextEditingController(
        text: orZero(item['rateValue']?.toString()),
      );
    }

    if (!mounted) return;
    setState(() {
      rates = data;
      _lastDate = stats['lastDate'] as String;
      _lastTime = stats['lastTime'] as String;
      _loading = false;
    });
  }

  /// Saves ALL rates in one tap. Any field left blank or invalid is
  /// simply skipped (not overwritten), so you can update just the
  /// ones that changed if you want, or all four at once.
  Future<void> saveAllRates() async {
    setState(() => _saving = true);

    String date = DateFormat("dd-MM-yyyy").format(DateTime.now());
    String time = DateFormat("hh:mm a").format(DateTime.now());

    int savedCount = 0;

    for (final item in rates) {
      final id = item['id'] as int;
      final rateName = item['rateName'] as String;
      final controller = _controllers[id]!;
      final parsed = double.tryParse(orZero(controller.text));

      if (parsed == null) continue;

      await DatabaseHelper.instance.updateRate(
        id,
        rateName,
        parsed.toString(),
        date,
        time,
      );
      savedCount++;
    }

    if (!mounted) return;

    setState(() => _saving = false);

    if (savedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least one valid rate")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$savedCount rate(s) updated successfully")),
    );
    loadRates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text("MASTER / RATES"),
        actions: [
          IconButton(
            icon: const Icon(Icons.people, size: 20),
            tooltip: 'Customer Master',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomerMasterScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.local_shipping, size: 20),
            tooltip: 'Supplier Master',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SupplierMasterScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.scale, size: 20),
            tooltip: 'Stock',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OpeningWeightScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: 'View update records',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
          children: [
            // Single global "Last Updated" header
            Container(
              width: double.infinity,
              color: AppColors.headerBand,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Text(
                _lastDate.isEmpty
                    ? "Last Updated : —"
                    : "Last Updated : $_lastDate  $_lastTime",
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSizes.sectionHeader,
                  color: AppColors.mutedBlue,
                ),
              ),
            ),
            Expanded(
              child: rates.isEmpty
                  ? const Center(
                child: Text(
                  "No rates found",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rates.length,
                itemBuilder: (context, index) {
                  final item = rates[index];
                  final controller = _controllers[item['id']]!;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item['rateName'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: controller,
                            style: const TextStyle(fontSize: 14),
                            textInputAction: index == rates.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onSubmitted: (_) {
                              if (index == rates.length - 1) saveAllRates();
                            },
                            keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '0',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Save, then leave — this screen's job is done.
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _saving ? null : saveAllRates,
                  child: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text("SAVE"),
                ),
              ),
            ),
          ],
        ),
    );
  }
}