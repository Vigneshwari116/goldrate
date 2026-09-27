import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/api/api_reachability.dart';

void main() {
  test('network failures are detected from timeout messages', () {
    expect(
      ApiReachability.isNetworkFailure(
        Exception('Cannot reach server at https://example.com'),
      ),
      isTrue,
    );
    expect(
      ApiReachability.isNetworkFailure(Exception('Invalid password')),
      isFalse,
    );
  });
}
