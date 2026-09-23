import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/field_sizes.dart';
import '../theme/responsive.dart';

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
    final narrow = !Responsive.isWide(context);

    Widget field(
      String label,
      TextEditingController c, {
      int maxLines = 1,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      String? Function(String?)? validator,
      int? maxLength,
      double? width,
    }) {
      final input = TextFormField(
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
      );
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 6 : 8),
        child: width != null && !narrow
            ? SizedBox(width: width, child: input)
            : input,
      );
    }

    final addressField = field(
      'Address',
      addressController,
      maxLines: 2,
      width: FieldSizes.billingAddress,
    );

    final cityPinRow = narrow
        ? Column(
            children: [
              field('City', cityController),
              field(
                'Pincode',
                pincodeController,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field('City', cityController, width: FieldSizes.billingCity),
              const SizedBox(width: 8),
              field(
                'Pincode',
                pincodeController,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                width: FieldSizes.billingPincode,
              ),
            ],
          );

    final gstStateRow = narrow
        ? Column(
            children: [
              field(
                'GSTIN (optional)',
                gstinController,
                maxLength: 15,
                validator: _gstinValidator,
              ),
              field('State', stateController),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(
                'GSTIN (optional)',
                gstinController,
                maxLength: 15,
                validator: _gstinValidator,
                width: FieldSizes.billingGstin,
              ),
              const SizedBox(width: 8),
              field('State', stateController, width: FieldSizes.billingState),
            ],
          );

    final ewayField = showEwayBill && ewayBillController != null
        ? field(
            'E-Way Bill No (optional)',
            ewayBillController!,
            width: FieldSizes.billingEway,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BILLING DETAILS', style: labelStyle),
        const SizedBox(height: 4),
        addressField,
        cityPinRow,
        gstStateRow,
        if (ewayField != null) ewayField,
      ],
    );
  }
}
