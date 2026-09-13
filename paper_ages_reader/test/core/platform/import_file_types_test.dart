import 'package:file_selector/file_selector.dart';
import 'package:file_selector_ios/file_selector_ios.dart';
// The real iOS Dart adapter is tested with only its native transport replaced.
import 'package:file_selector_ios/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/platform/import_file_types.dart';

class PickerApi extends FileSelectorApi {
  List<String>? types;
  @override
  Future<List<String>> openFile(FileSelectorConfig config) async {
    types = config.utis;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS reproduces extension-only error before calling native picker',
    () async {
      final api = PickerApi();
      await expectLater(
        FileSelectorIOS(api: api).openFile(
          acceptedTypeGroups: const [
            XTypeGroup(extensions: ['txt']),
          ],
        ),
        throwsArgumentError,
      );
      expect(api.types, isNull);
    },
  );
  for (final group in [
    ImportFileTypes.books,
    ImportFileTypes.text,
    ImportFileTypes.sources,
    ImportFileTypes.fonts,
  ]) {
    test(
      'iOS opens ${group.label} picker and cancellation returns null',
      () async {
        final api = PickerApi();
        final result = await FileSelectorIOS(api: api)
            .openFile(acceptedTypeGroups: [group]);
        expect(api.types, group.uniformTypeIdentifiers);
        expect(api.types, isNotEmpty);
        expect(result, isNull);
        expect(group.extensions, isNotEmpty);
      },
    );
  }
}
