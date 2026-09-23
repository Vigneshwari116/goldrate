/// Compact field widths — just enough for label/value, not full stretch.
class FieldSizes {
  FieldSizes._();

  static const typeDropdown = 88.0;
  /// Payment type dropdown includes "CASH" — needs extra width for label + icon.
  static const paymentTypeDropdown = 96.0;
  static const weight = 72.0;
  static const touch = 64.0;
  static const pure = 72.0;
  static const cash = 88.0;
  /// Customer/supplier name on Sales/Purchase bill entry (medium, not full width).
  static const name = 200.0;
  static const shortLabel = 64.0;

  /// Billing / party profile fields (compact on wide layouts).
  static const billingName = 260.0;
  static const mobile = 132.0;
  static const billingAddress = 400.0;
  static const billingCity = 168.0;
  static const billingPincode = 108.0;
  static const billingGstin = 220.0;
  static const billingState = 180.0;
  static const billingEway = 240.0;
  static const billingPoNo = 140.0;
  static const billingPoDate = 132.0;
}
