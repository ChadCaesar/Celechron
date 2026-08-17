import 'package:celechron/http/zjuServices/response_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('campus-card authentication classification', () {
    test('recognizes explicit service status codes', () {
      for (final status in [401, 403, 901]) {
        expect(jsonIndicatesAuthenticationFailure({'code': status}), isTrue);
        expect(
          jsonIndicatesAuthenticationFailure({'status': '$status'}),
          isTrue,
        );
      }
    });

    test('recognizes top-level and nested kickout', () {
      expect(jsonIndicatesAuthenticationFailure({'kickout': 1}), isTrue);
      expect(
        jsonIndicatesAuthenticationFailure({
          'data': {'kickout': '1'},
        }),
        isTrue,
      );
    });

    test('requires a failed response for textual auth markers', () {
      expect(
        jsonIndicatesAuthenticationFailure({
          'success': false,
          'message': 'token 已过期',
        }),
        isTrue,
      );
      expect(
        jsonIndicatesAuthenticationFailure({
          'success': true,
          'message': 'token refreshed',
        }),
        isFalse,
      );
    });

    test('does not confuse ordinary service errors with expiry', () {
      expect(
        jsonIndicatesAuthenticationFailure({
          'code': 500,
          'success': false,
          'message': '服务暂时不可用',
        }),
        isFalse,
      );
      expect(
        jsonIndicatesAuthenticationFailure({
          'code': 429,
          'success': false,
          'message': '请求过于频繁',
        }),
        isFalse,
      );
    });
  });
}
