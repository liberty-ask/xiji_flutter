import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/utils/constants.dart';

void main() {
  test('default page size is configured', () {
    expect(AppConstants.defaultPageSize, greaterThan(0));
  });
}
