import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/util/login_file_transaction.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File journal;
  late Map<String, File> files;
  late LoginFileTransaction transaction;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('onepub-transaction-');
    journal = File('${directory.path}/recovery.json');
    files = {
      'token': File('${directory.path}/token.json'),
      'account': File('${directory.path}/account.yaml'),
      'routing': File('${directory.path}/routing.json'),
    };
    for (final entry in files.entries) {
      await entry.value.writeAsString('old-${entry.key}');
    }
    transaction = LoginFileTransaction(journal, files);
  });
  tearDown(() => directory.delete(recursive: true));

  final next = {
    'token': 'new-token',
    'account': 'new-account',
    'routing': 'new-routing'
  };

  test('commits all files and removes recovery record', () async {
    await transaction.locked(() => transaction.commit(next));
    for (final entry in files.entries) {
      expect(await entry.value.readAsString(), next[entry.key]);
    }
    expect(journal.existsSync(), isFalse);
  });

  test('failure after each replacement restores previous complete login',
      () async {
    for (var failurePoint = 1; failurePoint <= files.length; failurePoint++) {
      await expectLater(
          transaction.locked(
              () => transaction.commit(next, afterReplacement: (count) async {
                    if (count == failurePoint) {
                      throw const FileSystemException('Injected write failure');
                    }
                  })),
          throwsA(isA<FileSystemException>()));
      for (final entry in files.entries) {
        expect(await entry.value.readAsString(), 'old-${entry.key}');
      }
      expect(journal.existsSync(), isFalse);
    }
  });

  test('next operation recovers interrupted write before reading login',
      () async {
    await journal.writeAsString(jsonEncode({
      'version': 1,
      'destinations':
          files.map((key, file) => MapEntry(key, file.absolute.path)),
      'previous': {
        'token': base64Encode(utf8.encode('old-token')),
        'account': base64Encode(utf8.encode('old-account')),
        'routing': null,
      },
    }));
    await files['token']!.writeAsString('partial-new-token');
    await transaction.locked(() async {
      expect(await files['token']!.readAsString(), 'old-token');
      expect(await files['account']!.readAsString(), 'old-account');
      expect(files['routing']!.existsSync(), isFalse);
    });
    expect(journal.existsSync(), isFalse);
  });

  test('invalid recovery record cannot choose destinations or partly restore',
      () async {
    await journal.writeAsString(jsonEncode({
      'version': 1,
      'destinations':
          files.map((key, file) => MapEntry(key, file.absolute.path)),
      'previous': {
        'token': base64Encode(utf8.encode('different-token')),
        'account': 'not base64!',
        'routing': null,
      },
    }));
    await expectLater(transaction.locked(() async {}), throwsFormatException);
    expect(await files['token']!.readAsString(), 'old-token');
    expect(journal.existsSync(), isTrue);
  });
}
