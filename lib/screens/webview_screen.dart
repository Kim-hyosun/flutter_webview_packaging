import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/device_info.dart';
import '../services/external_link.dart';
import '../services/fcm.dart';
import '../services/session.dart';

class WebViewScreen extends StatefulWidget {
  final String serviceUrl;
  final String baseUrl;

  const WebViewScreen({
    super.key,
    required this.serviceUrl,
    required this.baseUrl,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final String _allowedHost;

  bool _hasError = false;
  String _errorMessage = '';
  DateTime? _lastBackPressedAt;

  static const _backToExitToast = '한 번 더 누르면 종료됩니다';
  static const _backToExitWindow = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _allowedHost = Uri.parse(widget.serviceUrl).host;
    _initController();
  }

  void _initController() {
    // iPhone Safari UA — 서버측 UA 분기 호환을 위함.
    // (스토어 심사상 정당화 어려우면 native UA 로 교체 권장)
    const iphoneSafariUA =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
        'Mobile/15E148 Safari/604.1';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(iphoneSafariUA)
      ..addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: _onJsChannelMessage,
      )
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (_hasError) setState(() => _hasError = false);
          },
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..loadRequest(Uri.parse(widget.serviceUrl));
  }

  Future<void> _onJsChannelMessage(JavaScriptMessage message) async {
    final msg = message.message;
    debugPrint('🟢 JavaScriptChannel 메시지: $msg');

    if (msg == 'LOGIN_SUCCESS') {
      await SessionService.instance.refresh(widget.serviceUrl);
      await DeviceInfoService.instance.sendToServer(
        baseUrl: widget.baseUrl,
        fcmToken: FcmService.instance.token,
      );
    }

    if (msg == 'keep-alive') {
      await SessionService.instance.refresh(widget.serviceUrl);
      debugPrint('🔄 keep-alive로 세션 쿠키 갱신');
    }

    if (msg == 'LOGOUT') {
      SessionService.instance.clear();
    }
  }

  /// 외부 도메인 / mailto / tel 등은 OS 기본 앱으로 보내고 WebView 내 이동은 차단.
  NavigationDecision _onNavigationRequest(NavigationRequest req) {
    if (ExternalLinkService.isExternal(req.url, allowedHost: _allowedHost)) {
      ExternalLinkService.open(req.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _onPageFinished(String url) {
    debugPrint('✅ Loaded URL: $url');

    // ⚠️ 강제 hash 라우팅 (window.location.hash = '#/solis') 제거됨 —
    // hash 기반 라우팅을 더 이상 사용하지 않음. 서버가 응답한 경로 그대로 표시.

    // ⚠️ 백업 device-info 전송 분기 — hash 라우팅 안 쓰므로 비활성.
    //    LOGIN_SUCCESS JS 채널이 메인 트리거 (위 _onJsChannelMessage 참조).
    // (() async {
    //   if (!DeviceInfoService.instance.sent && url.contains('#/pages/home/index')) {
    //     await SessionService.instance.refresh(widget.serviceUrl);
    //     if (SessionService.instance.value != null) {
    //       await DeviceInfoService.instance.sendToServer(
    //         baseUrl: widget.baseUrl,
    //         fcmToken: FcmService.instance.token,
    //       );
    //     } else {
    //       debugPrint('home에서 retry: ❌ session 쿠키가 없어 디바이스 정보 전송 불가');
    //     }
    //   }
    // })();
  }

  void _onWebResourceError(WebResourceError error) {
    // sub-resource (이미지/광고 등) 실패는 무시. main frame 실패만 처리.
    if (error.isForMainFrame != true) {
      debugPrint('WebView sub-resource error (ignored): ${error.description}');
      return;
    }
    debugPrint('❌ WebView main-frame error: ${error.description}');
    setState(() {
      _hasError = true;
      _errorMessage = error.description.isEmpty
          ? '페이지를 불러올 수 없습니다'
          : error.description;
    });
  }

  Future<void> _reload() async {
    setState(() => _hasError = false);
    try {
      await _controller.reload();
    } catch (e) {
      debugPrint('❌ reload 실패: $e');
    }
  }

  /// Android 뒤로가기: webview 히스토리 우선 → 마지막에서는 두 번 눌러야 종료.
  Future<bool> _onPopInvoked() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > _backToExitWindow) {
      _lastBackPressedAt = now;
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(_backToExitToast),
              duration: _backToExitWindow,
            ),
          );
      }
      return false;
    }
    return true; // 종료 허용
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onPopInvoked();
        if (shouldExit && mounted) {
          // 시스템 종료 신호 — Android 만 실효
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _hasError ? _ErrorView(message: _errorMessage, onRetry: _reload) : WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              '연결할 수 없습니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
