import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/store_extension_mapper.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

void main() {
  test('SAFE maps to not-18+', () {
    expect(isNsfwFromWarning(Enum$ContentWarning.SAFE), false);
  });
  test('MIXED and NSFW map to 18+', () {
    expect(isNsfwFromWarning(Enum$ContentWarning.MIXED), true);
    expect(isNsfwFromWarning(Enum$ContentWarning.NSFW), true);
  });
  test('unknown future enum value maps to 18+ (safe failure)', () {
    expect(isNsfwFromWarning(Enum$ContentWarning.$unknown), true);
  });
}
