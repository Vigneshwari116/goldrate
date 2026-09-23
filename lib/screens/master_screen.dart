import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../util/focus_chain.dart';
import '../util/screen_activation.dart';
import '../database/database_helper.dart';
import '../logic/bill_tax.dart';
import '../models/party_billing_profile.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Rates ONLY. This screen does one job — enter/update today's four
/// rates — and nothing else. It's visited once a day, briefly, then
/// left. Purchase/Sales live on Home, not here, so this form is never
/// sitting on screen when staff is mid-billing.
class MasterScreen extends StatefulWidget {
  const MasterScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;
  final bool isActive;

  @override
  State<MasterScreen> createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen>
    with ScreenActivationMixin<MasterScreen> {
  List<Map<String, dynamic>> rates = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _loading = true;
  bool _saving = false;

  String _lastDate = '';
  String _lastTime = '';

  final Map<String, TextEditingController> _hsnControllers = {};
  final _shopNameController = TextEditingController();
  final _shopAddressController = TextEditingController();
  final _shopPhoneController = TextEditingController();
  final _shopGstinController = TextEditingController();
  final _shopStateController = TextEditingController();
  final _shopStateCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadRates();
  }

  @override
  bool get screenIsActive => widget.isActive;

  @override
  bool wasScreenActive(MasterScreen oldWidget) => oldWidget.isActive;

  @override
  void onScreenActivated() {
    loadRates();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    for (final c in _hsnControllers.values) {
      c.dispose();
    }
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _shopPhoneController.dispose();
    _shopGstinController.dispose();
    _shopStateController.dispose();
    _shopStateCodeController.dispose();
    super.dispose();
  }

  String _rateName(Map<String, dynamic> item) =>
      (item['rateName'] ?? '').toString();

  int _rateId(Map<String, dynamic> item) =>
      (item['id'] as num?)?.toInt() ?? 0;

  Future<void> loadRates() async {
    setState(() => _loading = true);
    try {
      final data = DatabaseHelper.canonicalRateRows(
        await DatabaseHelper.instance.getRatesForMaster(),
      );
      final stats = await DatabaseHelper.instance.getUpdateStats();
      final hsnMap = await DatabaseHelper.instance.getItemTypeHsnMap();
      final shop = await DatabaseHelper.instance.getShopSettings();

      for (final c in _hsnControllers.values) {
        c.dispose();
      }
      _hsnControllers.clear();
      for (final type in kDefaultHsnByItemType.keys) {
        _hsnControllers[type] =
            TextEditingController(text: hsnMap[type] ?? '');
      }
      _shopNameController.text = shop.shopName;
      _shopAddressController.text = shop.address;
      _shopPhoneController.text = shop.phone;
      _shopGstinController.text = shop.gstin;
      _shopStateController.text = shop.state;
      _shopStateCodeController.text = shop.stateCode;

      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      for (final n in _focusNodes.values) {
        n.dispose();
      }
      _focusNodes.clear();

      for (final item in data) {
        final name = _rateName(item);
        _controllers[name] =
            TextEditingController(text: (item['rateValue'] ?? '').toString());
        _focusNodes[name] = FocusNode();
      }

      if (!mounted) return;
      setState(() {
        rates = data;
        _lastDate = stats['lastDate'] as String? ?? '';
        _lastTime = stats['lastTime'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load rates: $e')),
      );
    }
  }

  Future<Map<String, int>> _rateIdsByName() async {
    await DatabaseHelper.instance.ensureDefaultRates();
    final rows = await DatabaseHelper.instance.getRates();
    return {
      for (final row in rows)
        _rateName(row): _rateId(row),
    };
  }

  /// Saves ALL rates in one tap. Any field left blank or invalid is
  /// simply skipped (not overwritten), so you can update just the
  /// ones that changed if you want, or all four at once.
  Future<void> saveAllRates() async {
    if (_saving) return;
    _saving = true;
    if (mounted) setState(() {});

    final date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final time = DateFormat('hh:mm a').format(DateTime.now());

    var savedCount = 0;

    try {
      final idsByName = await _rateIdsByName();

      for (final item in rates) {
        final rateName = _rateName(item);
        final id = idsByName[rateName] ?? _rateId(item);
        if (id == 0) continue;
        final controller = _controllers[rateName];
        if (controller == null) continue;
        final parsed = double.tryParse(controller.text.trim());
        if (parsed == null) continue;

        final rowsAffected = await DatabaseHelper.instance.updateRate(
          id,
          rateName,
          parsed.toString(),
          date,
          time,
        );
        if (rowsAffected > 0) savedCount++;
      }

      for (final entry in _hsnControllers.entries) {
        final code = entry.value.text.trim();
        if (code.isNotEmpty) {
          await DatabaseHelper.instance.saveItemTypeHsn(entry.key, code);
          savedCount++;
        }
      }

      await DatabaseHelper.instance.saveShopSettings(
        ShopSettings(
          shopName: _shopNameController.text.trim(),
          address: _shopAddressController.text.trim(),
          phone: _shopPhoneController.text.trim(),
          gstin: _shopGstinController.text.trim(),
          state: _shopStateController.text.trim(),
          stateCode: _shopStateCodeController.text.trim(),
        ),
      );
      savedCount++;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      } else {
        _saving = false;
      }
    }

    if (!mounted) return;

    if (savedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter at least one valid rate. If fields just appeared, '
            'tap SAVE again after the server seeds the rate rows.',
          ),
        ),
      );
      await loadRates();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$savedCount rate(s) updated successfully')),
    );
    await loadRates();
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : CenteredMaxWidth(
            maxWidth: 560,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.headerBand,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    _lastDate.isEmpty
                        ? 'Last Updated : —'
                        : 'Last Updated : $_lastDate  $_lastTime',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppTextSizes.sectionHeader,
                      color: AppColors.mutedBlue,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var index = 0; index < rates.length; index++)
                        Builder(builder: (context) {
                          final item = rates[index];
                          final rateName = _rateName(item);
                          final controller = _controllers[rateName]!;
                          final focusNode = _focusNodes[rateName]!;

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
                                    rateName,
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
                                    focusNode: focusNode,
                                    style: const TextStyle(fontSize: 14),
                                    keyboardType: const TextInputType
                                        .numberWithOptions(decimal: true),
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) {
                                      if (index + 1 < rates.length) {
                                        final nextName =
                                            _rateName(rates[index + 1]);
                                        FocusChain.focus(
                                          _focusNodes[nextName]!,
                                          controller:
                                              _controllers[nextName],
                                        );
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      const Text(
                        'HSN CODE (per item type)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSizes.sectionHeader,
                          color: AppColors.mutedBlue,
                        ),
                      ),
                      for (final type in kDefaultHsnByItemType.keys)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.cardWhite,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  type,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _hsnControllers[type],
                                  decoration: const InputDecoration(
                                    labelText: 'HSN',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'SHOP SETTINGS',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSizes.sectionHeader,
                          color: AppColors.mutedBlue,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardWhite,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _shopNameController,
                              decoration: const InputDecoration(
                                labelText: 'Shop name',
                              ),
                            ),
                            TextField(
                              controller: _shopAddressController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                              ),
                            ),
                            TextField(
                              controller: _shopPhoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                              ),
                            ),
                            TextField(
                              controller: _shopGstinController,
                              decoration: const InputDecoration(
                                labelText: 'GSTIN',
                              ),
                            ),
                            TextField(
                              controller: _shopStateController,
                              decoration: const InputDecoration(
                                labelText: 'State',
                              ),
                            ),
                            TextField(
                              controller: _shopStateCodeController,
                              decoration: const InputDecoration(
                                labelText: 'State code',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                          : const Text('SAVE'),
                    ),
                  ),
                ),
              ],
            ),
          );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('DAILY RATE')),
      body: content,
    );
  }
}
