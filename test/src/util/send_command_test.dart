import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

void main() {
  group('EndpointResponse', () {
    test('treats empty error bodies as empty responses', () {
      final response = EndpointResponse(500, StringBuffer(), CommandType.cli);

      expect(response.success, isFalse);
      expect(response.errorMessage, 'Empty response');
    });

    test('treats plain-text error bodies as errors instead of crashing', () {
      final response = EndpointResponse(
        502,
        StringBuffer('Upstream temporarily unavailable'),
        CommandType.cli,
      );

      expect(response.success, isFalse);
      expect(response.errorMessage, 'Upstream temporarily unavailable');
    });
  });
}
