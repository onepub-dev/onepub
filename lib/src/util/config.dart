/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:validators2/validators.dart';
import '../onepub_settings.dart';

///
class ConfigCommand {
  static final testingFlagPath = join(HOME, '.onepubtesting');

  ///
  void config({required bool dev}) {
    print('Configure OnePub');

    OnePubSettings.load();

    promptForConfig(dev: dev);
  }

  void promptForConfig({required bool dev}) {
    var url = OnePubSettings.defaultOnePubUrl;
    if (dev) {
      url = ask('OnePub URL:', validator: UrlValidator(), defaultValue: url);
      testingFlagPath.write('onepubtesting');
    }

    OnePubSettings().onepubUrl = url;
    OnePubSettings().save();
  }
}

class UrlValidator extends AskValidator {
  @override
  String validate(String line) {
    final finalLine = line.trim().toLowerCase();

    if (!line.startsWith('https://')) {
      throw AskValidatorException(red('Must start with https://'));
    }
    final fqdn = finalLine.replaceFirst('https://', '');
    if (!isFQDN(fqdn)) {
      throw AskValidatorException(red('Invalid FQDN.'));
    }
    return finalLine;
  }
}
