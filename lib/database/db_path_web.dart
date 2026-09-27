import 'package:path/path.dart';

Future<String> resolveJewelleryDatabasePathImpl({
  required Future<String> Function() getDatabasesPath,
}) async {
  return join(await getDatabasesPath(), 'jewellery.db');
}
