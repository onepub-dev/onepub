#! /usr/bin/env dart

import '../../check_system_test_prereqs.dart' as system_tests;

/// Check the guarded test target and its isolated System Administrator token.
/// Never use the operator's normal OnePub settings or publishing credentials.
Future<void> main(List<String> args) => system_tests.main(args);
