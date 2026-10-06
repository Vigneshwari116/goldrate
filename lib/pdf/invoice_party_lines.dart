import '../models/party_billing_profile.dart';

/// Address blocks for GST invoices (sales vs purchase roles).
class InvoicePartyLines {
  InvoicePartyLines._();

  static const String _placeholder = '—';

  static const List<String> shopLines = [
    'Shree Mahalasa Jewellery Works',
    'No.180, 1st Cross, 9th Main Road,',
    'Srinivasanagar, BSK 1st Stage,',
    'Bangalore',
    'Phone - 9448008065',
    'GSTIN/UIN: 29ABDPV0313K1ZK',
    'State Name : Karnataka, Code : 29',
  ];

  static const String shopSignatureName = 'Shree Mahalasa Jewellery Works';

  static List<String> shopAsBuyerLines() {
    return ['Buyer (Bill to)', ...shopLines];
  }

  static List<String> partyAsBuyerLines(PartyBillingProfile party) {
    final lines = <String>['Buyer (Bill to)'];
    lines.addAll(_partyBodyLines(party, includePlaceOfSupply: true));
    return lines;
  }

  /// Supplier as seller on purchase GST invoice (no "Buyer" header).
  static List<String> partyAsSellerLines(PartyBillingProfile party) {
    return _partyBodyLines(party, includePlaceOfSupply: false);
  }

  static List<String> _partyBodyLines(
    PartyBillingProfile party, {
    required bool includePlaceOfSupply,
  }) {
    final lines = <String>[];
    final name = party.name.trim().isEmpty ? _placeholder : party.name.trim();
    lines.add(name);
    final address = party.address.trim();
    if (address.isNotEmpty) {
      for (final part in address.split('\n')) {
        final t = part.trim();
        if (t.isNotEmpty) lines.add(t);
      }
    }
    final city = party.city.trim();
    final pin = party.pincode.trim();
    if (city.isNotEmpty || pin.isNotEmpty) {
      if (city.isNotEmpty && pin.isNotEmpty) {
        lines.add('$city -$pin');
      } else {
        lines.add(city.isNotEmpty ? city : pin);
      }
    }
    final gstin = party.gstin.trim();
    lines.add(
      gstin.isEmpty ? 'GSTIN/UIN : $_placeholder' : 'GSTIN/UIN : $gstin',
    );
    final state = party.state.trim();
    lines.add(
      state.isEmpty ? 'State Name : $_placeholder' : 'State Name : $state',
    );
    if (includePlaceOfSupply) {
      lines.add(
        state.isEmpty
            ? 'Place of Supply : $_placeholder'
            : 'Place of Supply : $state',
      );
    }
    return lines;
  }
}
