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
    this.compact = false,
    this.addressFocus,
    this.cityFocus,
    this.pincodeFocus,
    this.gstinFocus,
    this.stateFocus,
    this.onAddressSubmitted,
    this.onCitySubmitted,
    this.onPincodeSubmitted,
    this.onGstinSubmitted,
    this.onStateSubmitted,
  });

  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController pincodeController;
  final TextEditingController gstinController;
  final TextEditingController stateController;
  final bool compact;

  final FocusNode? addressFocus;
  final FocusNode? cityFocus;
  final FocusNode? pincodeFocus;
  final FocusNode? gstinFocus;
  final FocusNode? stateFocus;
  final VoidCallback? onAddressSubmitted;
  final VoidCallback? onCitySubmitted;
  final VoidCallback? onPincodeSubmitted;
  final VoidCallback? onGstinSubmitted;
  final VoidCallback? onStateSubmitted;

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
    final pairWidth = FieldSizes.billingPairField;

    Widget field(
      String label,
      TextEditingController c, {
      int maxLines = 1,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      String? Function(String?)? validator,
      int? maxLength,
      double? width,
      FocusNode? focusNode,
      VoidCallback? onSubmitted,
      TextInputAction inputAction = TextInputAction.next,
    }) {
      final input = TextFormField(
        controller: c,
        focusNode: focusNode,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters: formatters,
        validator: validator,
        maxLength: maxLength,
        style: TextStyle(fontSize: compact ? 13 : 14),
        textInputAction: inputAction,
        onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
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
      focusNode: addressFocus,
      onSubmitted: onAddressSubmitted,
    );

    final cityPinRow = narrow
        ? Column(
            children: [
              field(
                'City',
                cityController,
                focusNode: cityFocus,
                onSubmitted: onCitySubmitted,
              ),
              field(
                'Pincode',
                pincodeController,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                focusNode: pincodeFocus,
                onSubmitted: onPincodeSubmitted,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(
                'City',
                cityController,
                width: pairWidth,
                focusNode: cityFocus,
                onSubmitted: onCitySubmitted,
              ),
              const SizedBox(width: 8),
              field(
                'Pincode',
                pincodeController,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                width: pairWidth,
                focusNode: pincodeFocus,
                onSubmitted: onPincodeSubmitted,
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
                focusNode: gstinFocus,
                onSubmitted: onGstinSubmitted,
              ),
              field(
                'State',
                stateController,
                focusNode: stateFocus,
                onSubmitted: onStateSubmitted,
                inputAction: TextInputAction.done,
              ),
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
                width: pairWidth,
                focusNode: gstinFocus,
                onSubmitted: onGstinSubmitted,
              ),
              const SizedBox(width: 8),
              field(
                'State',
                stateController,
                width: pairWidth,
                focusNode: stateFocus,
                onSubmitted: onStateSubmitted,
                inputAction: TextInputAction.done,
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BILLING DETAILS', style: labelStyle),
        const SizedBox(height: 4),
        addressField,
        cityPinRow,
        gstStateRow,
      ],
    );
  }
}
