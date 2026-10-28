/// Cache a verified publication, not a test outcome. Each named assertion still
/// executes even when it reuses publication setup from another assertion.
class SharedPublishFixture<T> {
  T? _value;

  Future<T> get(Future<T> Function() publishAndVerify) async =>
      _value ??= await publishAndVerify();

  void deleted() {
    _value = null;
  }
}

/// Publishing is always selected unless explicitly disabled, even if every
/// optional consumer is disabled. This preserves the former publish-only case.
Map<String, bool> publishJourneySelection({
  required bool skipPublish,
  required bool skipMetadata,
  required bool skipArchive,
  required bool skipPubGet,
  required bool skipCleanup,
}) =>
    {
      'publish package': !skipPublish,
      'pub metadata': !skipPublish && !skipMetadata,
      'pub archive': !skipPublish && !skipArchive,
      'pub get': !skipPublish && !skipPubGet,
      'cleanup package': !skipPublish && !skipCleanup,
    };
