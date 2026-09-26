import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';
import 'gst_tax_invoice_layout.dart';
import 'invoice_party_lines.dart';

/// GST sales tax invoice (shop = seller, customer = buyer).
class SalesTaxInvoicePdf {
  SalesTaxInvoicePdf._();

  static const String copyOriginalForRecipient =
      GstTaxInvoiceLayout.copyOriginalForRecipient;
  static const String copyDuplicateForTransporter =
      GstTaxInvoiceLayout.copyDuplicateForTransporter;

  static const List<String> invoiceSellerLines = InvoicePartyLines.shopLines;
  static const String invoiceSellerSignatureName =
      InvoicePartyLines.shopSignatureName;

  static List<String> sellerDisplayLines() =>
      List<String>.unmodifiable(invoiceSellerLines);

  static List<String> buyerDisplayLines(PartyBillingProfile buyer) =>
      InvoicePartyLines.partyAsBuyerLines(buyer);

  static pw.Page buildPage({
    required PartyBillingProfile buyer,
    required Map<String, dynamic> row,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double tdsAmount,
    required double tcsAmount,
    required bool tdsApplicable,
    required bool tcsApplicable,
    String copyLabel = copyOriginalForRecipient,
  }) {
    return GstTaxInvoiceLayout.buildPage(
      sellerLines: sellerDisplayLines(),
      buyerLines: buyerDisplayLines(buyer),
      signatureName: invoiceSellerSignatureName,
      billNo: row['billNo']?.toString() ?? '',
      billDate: (row['date'] ?? '').toString(),
      items: items,
      totals: totals,
      tdsAmount: tdsAmount,
      tcsAmount: tcsAmount,
      tdsApplicable: tdsApplicable,
      tcsApplicable: tcsApplicable,
      copyLabel: copyLabel,
    );
  }
}
