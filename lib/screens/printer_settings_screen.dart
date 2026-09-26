import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/printer_prefs.dart';
import '../util/sales_invoice_prefs.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _loading = true;
  List<String> _printers = [];
  String? _selected;
  String? _error;
  SalesInvoiceFormat _salesInvoiceFormat = SalesInvoiceFormat.detailed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final selected = await PrinterPrefs.getSelected();
      final printers = await PrinterPrefs.listPrinterNames();
      final invoiceFormat = await SalesInvoicePrefs.getFormat();
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _selected = selected;
        _salesInvoiceFormat = invoiceFormat;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _choose(String name) async {
    await PrinterPrefs.setSelected(name);
    if (!mounted) return;
    setState(() => _selected = name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Preferred printer: $name')),
    );
  }

  Future<void> _setSalesInvoiceFormat(SalesInvoiceFormat format) async {
    await SalesInvoicePrefs.setFormat(format);
    if (!mounted) return;
    setState(() => _salesInvoiceFormat = format);
    final label = format == SalesInvoiceFormat.simple
        ? 'Simple (compact)'
        : 'Detailed (GST form)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sales GST invoice layout: $label')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'This app uses the printers already installed on Windows or '
                'the phone. You do not write or install a jewellery printer '
                'driver. Add printers in Windows Settings or the phone print '
                'dialog, then pick one here.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sales GST invoice PDF',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose the layout used when you save or print a sales tax '
                'invoice. Purchase invoices are unchanged.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              RadioListTile<SalesInvoiceFormat>(
                value: SalesInvoiceFormat.detailed,
                groupValue: _salesInvoiceFormat,
                onChanged: (v) {
                  if (v != null) _setSalesInvoiceFormat(v);
                },
                title: const Text('Detailed (GST form)'),
                subtitle: const Text('Full tax invoice with QR and tax summary'),
                dense: true,
              ),
              RadioListTile<SalesInvoiceFormat>(
                value: SalesInvoiceFormat.simple,
                groupValue: _salesInvoiceFormat,
                onChanged: (v) {
                  if (v != null) _setSalesInvoiceFormat(v);
                },
                title: const Text('Simple (compact)'),
                subtitle: const Text(
                  'Compact layout with Shree Mahalasa seller block',
                ),
                dense: true,
              ),
              const SizedBox(height: 16),
              Text(
                Platform.isWindows
                    ? 'Windows printers from this computer'
                    : 'Printers available on this phone',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_printers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No printers were reported. Install a printer in Windows '
                    'Settings (or enable a printer on the phone). When you '
                    'open a PDF and print, the system print dialog still '
                    'lists every printer.',
                  ),
                )
              else
                for (final name in _printers)
                  ListTile(
                    selected: _selected == name,
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    trailing: _selected == name
                        ? const Icon(Icons.check, color: AppColors.navy)
                        : null,
                    onTap: () => _choose(name),
                  ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('REFRESH PRINTER LIST'),
              ),
            ],
          );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('PRINTER SETTINGS')),
      body: content,
    );
  }
}
