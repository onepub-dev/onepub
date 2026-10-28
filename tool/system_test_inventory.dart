import 'dart:io';

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
