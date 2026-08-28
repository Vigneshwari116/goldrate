import 'package:flutter/material.dart';

/// Asks whether to save a new customer/supplier when the typed name is not
/// already in the master list.
Future<bool> confirmSaveNewParty(
  BuildContext context, {
  required bool isCustomer,
  required String name,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;

  final kind = isCustomer ? 'customer' : 'supplier';
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Save this $kind?'),
      content: Text(
        '"$trimmed" is not in the saved ${isCustomer ? 'customer' : 'supplier'} list.\n\n'
        'Save as a new ${kind.toUpperCase()} master entry?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return result == true;
}
