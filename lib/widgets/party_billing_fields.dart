import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Address / GST fields for party master and purchase/sales bills.
class PartyBillingFields extends StatelessWidget {
  const PartyBillingFields({
    super.key,
    required this.addressController,
    required this.cityController,
    required this.pincodeController,
    required this.gstinController,
    required this.stateController,
    this.showEwayBill = false,
    this.ewayBillController,
    this.compact = false,
  });

  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController pincodeController;
  final TextEditingController gstinController;
  final TextEditingController stateController;
  final bool showEwayBill;
  final TextEditingController? ewayBillController;
  final bool compact;

  String? _gstinValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    if (value.length != 15) return 'GSTIN must be 15 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: compact ? 11 : 12,
      fontWeight: FontWeight.w600,
      color: AppColors.mutedBlue,
    );

    Widget field(String label, TextEditingController c,
        {int maxLines = 1,
        TextInputType? keyboard,
        List<TextInputFormatter>? formatters,
        String? Function(String?)? validator,
        int? maxLength}) {
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 6 : 8),
        child: TextFormField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          inputFormatters: formatters,
          validator: validator,
          maxLength: maxLength,
          style: TextStyle(fontSize: compact ? 13 : 14),
          decoration: InputDecoration(
            labelText: label,
            isDense: compact,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BILLING DETAILS', style: labelStyle),
        const SizedBox(height: 4),
        field('Address', addressController, maxLines: 2),
        Row(
          children: [
            Expanded(
              child: field('City', cityController),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: field(
                'Pincode',
                pincodeController,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ),
          ],
        ),
        field(
          'GSTIN (optional)',
          gstinController,
          maxLength: 15,
          validator: _gstinValidator,
        ),
        field('State', stateController),
        if (showEwayBill && ewayBillController != null)
          field('E-Way Bill No (optional)', ewayBillController!),
      ],
    );
  }
}
