import 'package:shared_preferences/shared_preferences.dart';

/// Sales GST invoice PDF layout: detailed (GST form) vs simple (compact).
enum SalesInvoiceFormat {
  detailed,
  simple,
}

class SalesInvoicePrefs {
  SalesInvoicePrefs._();

  static const _key = 'sales_invoice_pdf_format';

  static Future<SalesInvoiceFormat> getFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == 'simple') return SalesInvoiceFormat.simple;
    return SalesInvoiceFormat.detailed;
  }

  static Future<void> setFormat(SalesInvoiceFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      format == SalesInvoiceFormat.simple ? 'simple' : 'detailed',
    );
  }
}
