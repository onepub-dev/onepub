import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:boolean_selector/boolean_selector.dart';

/// Mirrors the runner's pre-load exclusion of library-level tags. Positive
/// name/tag filters run after loading, so those files still require evidence.
({List<String> requiredFiles, Map<String, List<String>> excludedFiles})
    effectiveTestInventory(String root, List<String> candidates,
        List<String> arguments, String configuredExclusion) {
  var selector = BooleanSelector.parse(configuredExclusion);
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    String? expression;
    if (['--exclude-tags', '--exclude-tag', '-x'].contains(argument)) {
      expression = arguments[++index];
    } else if (argument.startsWith('--exclude-tags=') ||
        argument.startsWith('--exclude-tag=')) {
      expression = argument.substring(argument.indexOf('=') + 1);
    } else if (argument.startsWith('-x') && argument.length > 2) {
      expression = argument.substring(2);
    }
    if (expression != null) {
      for (final part in expression.split(',')) {
        selector = selector.union(BooleanSelector.parse(part));
      }
    }
  }
  final required = <String>[];
  final excluded = <String, List<String>>{};
  for (final path in candidates) {
    final unit = parseString(content: File('$root/$path').readAsStringSync());
    final tags = <String>{};
    for (final directive
        in unit.unit.directives.whereType<LibraryDirective>()) {
      for (final annotation in directive.metadata) {
        if (annotation.name.toSource().split('.').last != 'Tags') {
          continue;
        }
        final arguments = annotation.arguments?.arguments;
        if (arguments == null ||
            arguments.length != 1 ||
            arguments.single is! ListLiteral) {
          throw FormatException('Cannot audit library test tags: $path');
        }
        for (final element in (arguments.single as ListLiteral).elements) {
          if (element is! StringLiteral || element.stringValue == null) {
            throw FormatException('Cannot audit library test tags: $path');
          }
          tags.add(element.stringValue!);
        }
      }
    }
    if (selector.evaluate(tags.contains)) {
      excluded[path] = tags.toList()..sort();
    } else {
      required.add(path);
    }
  }
  return (requiredFiles: required, excludedFiles: excluded);
}

/// Audited tests using only process-local state or their own loopback fixtures.
/// New and untagged tests default to the serial lane until explicitly audited.
const independentTestFiles = <String>{
  'test/fixture_retry_test.dart',
  'test/fixture_roles_test.dart',
  'test/fixture_creation_race_test.dart',
  'test/test_settings_test.dart',
  'test/system_test_settings_test.dart',
  'test/src/onepub_settings_test.dart',
  'test/src/api/release_contract_test.dart',
  'test/src/api/import_audit_test.dart',
  'test/src/api/oidc_exchange_test.dart',
  'test/src/auth/oidc_token_acquirer_test.dart',
  'test/src/auth/ci_provider_test.dart',
  'test/src/auth/oidc_token_reader_test.dart',
  'test/src/tool/oidc_github_workflow_test.dart',
  'test/src/tool/critical_test_auth_hook_test.dart',
  'test/src/tool/prepare_trusted_publishing_test.dart',
  'test/src/tool/trusted_publishing_e2e_test.dart',
  'test/src/tool/system_test_inventory_test.dart',
  'test/src/tool/test_evidence_test.dart',
  'test/src/tool/shared_publish_fixture_test.dart',
  'test/src/util/send_command_test.dart',
};

({List<String> independent, List<String> serial}) systemTestInventory(
    String root) {
  final files = Directory('$root/test')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((file) => file.path.substring(root.length + 1))
      .where((path) => path.endsWith('_test.dart'))
      .toList()
    ..sort();
  return partitionTestFiles(files);
}

({List<String> independent, List<String> serial}) partitionTestFiles(
        List<String> files) =>
    (
      independent: files.where(independentTestFiles.contains).toList(),
      serial:
          files.where((file) => !independentTestFiles.contains(file)).toList(),
    );
