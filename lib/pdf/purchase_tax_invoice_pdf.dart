import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';
import 'gst_tax_invoice_layout.dart';
import 'invoice_party_lines.dart';

/// GST purchase tax invoice (supplier = seller, shop = buyer).
class PurchaseTaxInvoicePdf {
  PurchaseTaxInvoicePdf._();

  static pw.Page buildPage({
    required Map<String, dynamic> row,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double tdsAmount,
    required double tcsAmount,
    required bool tdsApplicable,
    required bool tcsApplicable,
    String copyLabel = GstTaxInvoiceLayout.copyOriginalForRecipient,
  }) {
    final supplier = PartyBillingProfile.fromTransactionRow(row);
    final kind = 'PUR';
    final billNo = row['billNo']?.toString() ?? '';
    final poNo = (row['poNo'] ?? '').toString().trim();
    final poDate = (row['poDate'] ?? '').toString().trim();

    return GstTaxInvoiceLayout.buildPage(
      sellerLines: InvoicePartyLines.partyAsSellerLines(supplier),
      buyerLines: InvoicePartyLines.shopAsBuyerLines(),
      signatureName: InvoicePartyLines.shopSignatureName,
      billNo: '$kind-$billNo',
      billDate: (row['date'] ?? '').toString(),
      items: items,
      totals: totals,
      tdsAmount: tdsAmount,
      tcsAmount: tcsAmount,
      tdsApplicable: tdsApplicable,
      tcsApplicable: tcsApplicable,
      copyLabel: copyLabel,
      referenceNo: poNo,
      buyersOrderNo: poDate,
    );
  }
}
