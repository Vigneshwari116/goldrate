import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/printer_prefs.dart';

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
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _selected = selected;
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
