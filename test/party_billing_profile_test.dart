import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/models/party_billing_profile.dart';

void main() {
  test('fromDbRow parses isCustomer from bool or int', () {
    final fromBool = PartyBillingProfile.fromDbRow({
      'displayName': 'Acme',
      'isCustomer': false,
    });
    expect(fromBool.isCustomer, false);

    final fromInt = PartyBillingProfile.fromDbRow({
      'displayName': 'Acme',
      'isCustomer': 1,
    });
    expect(fromInt.isCustomer, true);
  });
}
