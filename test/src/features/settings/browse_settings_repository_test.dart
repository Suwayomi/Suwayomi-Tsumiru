import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/data/browse_settings_repository.dart';

void main() {
  test('legacy repo write document targets extensionRepos input field', () {
    // The raw document is a compile-time constant; assert its shape so a
    // refactor can't silently drop the only write path old servers have.
    expect(
      BrowseSettingsRepository.updateExtensionReposDocument,
      contains('extensionRepos: \$extensionRepos'),
    );
    expect(
      BrowseSettingsRepository.updateExtensionReposDocument,
      contains('mutation UpdateExtensionRepos'),
    );
  });
}
