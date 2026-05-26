// 기본 smoke test — WebView/Firebase 가 들어가는 실 앱은 통합 테스트(integration_test)로 검증.
//
// 여기서는 ExternalLinkService 의 isExternal 분기 같은 순수 로직만 단위 테스트.

import 'package:flutter_test/flutter_test.dart';
import 'package:solis_monitor/services/external_link.dart';

void main() {
  group('ExternalLinkService.isExternal', () {
    const allowedHost = 'www.energyus-vppc.com';

    test('같은 도메인 https 는 internal', () {
      expect(
        ExternalLinkService.isExternal(
          'https://www.energyus-vppc.com/some/path',
          allowedHost: allowedHost,
        ),
        isFalse,
      );
    });

    test('다른 도메인 https 는 external', () {
      expect(
        ExternalLinkService.isExternal(
          'https://example.com/foo',
          allowedHost: allowedHost,
        ),
        isTrue,
      );
    });

    test('mailto: 는 external', () {
      expect(
        ExternalLinkService.isExternal(
          'mailto:hello@example.com',
          allowedHost: allowedHost,
        ),
        isTrue,
      );
    });

    test('tel: 은 external', () {
      expect(
        ExternalLinkService.isExternal(
          'tel:01012345678',
          allowedHost: allowedHost,
        ),
        isTrue,
      );
    });

    test('sms: 는 external', () {
      expect(
        ExternalLinkService.isExternal(
          'sms:01012345678',
          allowedHost: allowedHost,
        ),
        isTrue,
      );
    });

    test('빈 호스트 (about:blank 등) 는 internal', () {
      expect(
        ExternalLinkService.isExternal('about:blank', allowedHost: allowedHost),
        isFalse,
      );
    });
  });
}
