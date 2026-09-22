import '../util/party_name_key.dart';

/// Billing address / GST details for a customer or supplier (master data).
class PartyBillingProfile {
  final String name;
  final bool isCustomer;
  final String mobile;
  final String address;
  final String city;
  final String pincode;
  final String gstin;
  final String state;

  const PartyBillingProfile({
    required this.name,
    required this.isCustomer,
    this.mobile = '',
    this.address = '',
    this.city = '',
    this.pincode = '',
    this.gstin = '',
    this.state = '',
  });

  static const empty = PartyBillingProfile(name: '', isCustomer: true);

  bool get isEmpty =>
      name.trim().isEmpty &&
      address.trim().isEmpty &&
      city.trim().isEmpty &&
      pincode.trim().isEmpty &&
      gstin.trim().isEmpty &&
      state.trim().isEmpty;

  Map<String, dynamic> toDbRow() => {
        'nameKey': partyNameKey(name),
        'displayName': name.trim(),
        'isCustomer': isCustomer ? 1 : 0,
        'mobile': mobile.trim(),
        'address': address.trim(),
        'city': city.trim(),
        'pincode': pincode.trim(),
        'gstin': gstin.trim().toUpperCase(),
        'state': state.trim(),
      };

  factory PartyBillingProfile.fromDbRow(Map<String, dynamic> row) {
    return PartyBillingProfile(
      name: (row['displayName'] ?? row['name'] ?? '').toString(),
      isCustomer: (row['isCustomer'] as int? ?? 1) == 1,
      mobile: (row['mobile'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      city: (row['city'] ?? '').toString(),
      pincode: (row['pincode'] ?? '').toString(),
      gstin: (row['gstin'] ?? '').toString(),
      state: (row['state'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toTransactionSnapshot() => {
        'address': address,
        'city': city,
        'pincode': pincode,
        'gstin': gstin,
        'state': state,
      };

  factory PartyBillingProfile.fromTransactionRow(Map<String, dynamic> row) {
    return PartyBillingProfile(
      name: (row['partyName'] ?? '').toString(),
      isCustomer: true,
      address: (row['partyAddress'] ?? '').toString(),
      city: (row['partyCity'] ?? '').toString(),
      pincode: (row['partyPincode'] ?? '').toString(),
      gstin: (row['partyGstin'] ?? '').toString(),
      state: (row['partyState'] ?? '').toString(),
    );
  }
}

class ShopSettings {
  final String shopName;
  final String address;
  final String phone;
  final String gstin;
  final String state;
  final String stateCode;

  const ShopSettings({
    this.shopName = '',
    this.address = '',
    this.phone = '',
    this.gstin = '',
    this.state = '',
    this.stateCode = '',
  });

  Map<String, dynamic> toDbRow() => {
        'id': 1,
        'shopName': shopName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'gstin': gstin.trim().toUpperCase(),
        'state': state.trim(),
        'stateCode': stateCode.trim(),
      };

  factory ShopSettings.fromDbRow(Map<String, dynamic>? row) {
    if (row == null) return const ShopSettings();
    return ShopSettings(
      shopName: (row['shopName'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      gstin: (row['gstin'] ?? '').toString(),
      state: (row['state'] ?? '').toString(),
      stateCode: (row['stateCode'] ?? '').toString(),
    );
  }
}
