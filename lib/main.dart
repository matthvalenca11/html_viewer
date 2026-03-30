import 'dart:collection';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'local_html_path.dart';

/// Largura lógica “desktop” para viewport (CSS / media queries), alinhada a ~iPad horizontal.
const int _kDesktopViewportWidth = 1280;

/// User-Agent de desktop (Chrome/macOS) para páginas que decidem layout pelo UA.
const String _kDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// Injeta/substitui meta viewport antes do layout, para não cair no modo “mobile estreito”.
final String _kDesktopViewportUserScriptSource = '''
(function() {
  var w = '$_kDesktopViewportWidth';
  var content = 'width=' + w + ', initial-scale=1, shrink-to-fit=no, maximum-scale=5, user-scalable=yes, viewport-fit=cover';
  function patch() {
    try {
      var m = document.querySelector('meta[name="viewport"]');
      if (m) {
        m.setAttribute('content', content);
      } else if (document.head) {
        m = document.createElement('meta');
        m.setAttribute('name', 'viewport');
        m.setAttribute('content', content);
        document.head.insertBefore(m, document.head.firstChild);
      }
    } catch (e) {}
  }
  patch();
  document.addEventListener('readystatechange', function() {
    if (document.readyState === 'interactive' || document.readyState === 'complete') patch();
  });
})();
''';

final UserScript _kDesktopViewportUserScript = UserScript(
  source: _kDesktopViewportUserScriptSource,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  groupName: 'desktop_viewport',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HtmlViewerApp());
}

class HtmlViewerApp extends StatelessWidget {
  const HtmlViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Impact Arrow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const OpenFilePage(),
    );
  }
}

class OpenFilePage extends StatefulWidget {
  const OpenFilePage({super.key});

  @override
  State<OpenFilePage> createState() => _OpenFilePageState();
}

class _OpenFilePageState extends State<OpenFilePage> {
  bool _busy = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  WebUri? _parseUserUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return WebUri(uri.toString());
  }

  void _openUrl() {
    if (kIsWeb) {
      _toast('Disponível apenas em iOS, iPadOS e Android.');
      return;
    }
    final webUri = _parseUserUrl(_urlController.text);
    if (webUri == null) {
      _toast('Digite um endereço válido (ex.: exemplo.com ou https://…).');
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => FullScreenWebViewerPage.url(webUri),
      ),
    );
  }

  Future<void> _pickAndOpen() async {
    if (kIsWeb) {
      _toast('Disponível apenas em iOS, iPadOS e Android.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['html', 'htm'],
        allowMultiple: false,
        withReadStream: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        return;
      }
      final picked = result.files.single;
      if (!isHtmlFileName(picked.name)) {
        _toast('Selecione um arquivo .html ou .htm.');
        return;
      }
      final path = await resolveLocalHtmlPath(picked);
      if (!mounted) return;
      if (path == null) {
        _toast('Não foi possível acessar o arquivo.');
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => FullScreenWebViewerPage.file(path),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.sizeOf(context).height -
                        padding.vertical -
                        48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: _pickAndOpen,
                        child: const Text('Abrir arquivo HTML'),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(child: Divider(color: surface)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'ou abrir um site',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          Expanded(child: Divider(color: surface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _openUrl(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'https://exemplo.com',
                          labelText: 'Endereço do site',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _openUrl,
                        child: const Text('Abrir link'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Visualização em tela inteira: arquivo local [file] ou página remota [url].
class FullScreenWebViewerPage extends StatefulWidget {
  FullScreenWebViewerPage._({
    this.fileAbsolutePath,
    this.initialWebUri,
  })  : assert(
          (fileAbsolutePath != null) ^ (initialWebUri != null),
          'Informe arquivo ou URL.',
        ),
        super();

  factory FullScreenWebViewerPage.file(String fileAbsolutePath) {
    return FullScreenWebViewerPage._(fileAbsolutePath: fileAbsolutePath);
  }

  factory FullScreenWebViewerPage.url(WebUri initialWebUri) {
    return FullScreenWebViewerPage._(initialWebUri: initialWebUri);
  }

  final String? fileAbsolutePath;
  final WebUri? initialWebUri;

  @override
  State<FullScreenWebViewerPage> createState() =>
      _FullScreenWebViewerPageState();
}

class _FullScreenWebViewerPageState extends State<FullScreenWebViewerPage> {
  /// iOS: `transparentBackground: true` often leaves WKWebView visually blank.
  /// `allowingReadAccessTo` must be set on [InAppWebViewSettings] when using
  /// [initialUrlRequest] with `file://` (see plugin docs).
  ///
  /// Em telefones (menor lado abaixo de 600): UA + viewport “desktop” e Android sem
  /// zoom-out automático — layout como navegador/iPad. Tablets não são alterados.
  InAppWebViewSettings _settingsFor(
    String readAccessDir, {
    required bool usePhoneDesktopLayout,
  }) =>
      InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        useOnDownloadStart: true,
        transparentBackground: false,
        allowFileAccess: true,
        allowContentAccess: true,
        hardwareAcceleration: true,
        allowingReadAccessTo: WebUri.uri(Uri.directory(readAccessDir)),
        userAgent: usePhoneDesktopLayout ? _kDesktopUserAgent : '',
        // Android: não encolher a página inteira à largura do ecrã (comportamento “overview”).
        useWideViewPort: true,
        loadWithOverviewMode: usePhoneDesktopLayout ? false : true,
      );

  InAppWebViewSettings _settingsForRemote({
    required bool usePhoneDesktopLayout,
  }) =>
      InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useOnDownloadStart: true,
        transparentBackground: false,
        hardwareAcceleration: true,
        userAgent: usePhoneDesktopLayout ? _kDesktopUserAgent : '',
        useWideViewPort: true,
        loadWithOverviewMode: usePhoneDesktopLayout ? false : true,
      );

  InAppWebViewController? _controller;
  double _edgeDragAccumDx = 0;

  /// Volta no histórico da WebView; se não houver, fecha o viewer (home).
  Future<void> _handleNavigateBack() async {
    if (!mounted) return;
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Faixa invisível na borda esquerda: arrastar para a direita = voltar (histórico ou sair).
  /// Tela inteira não recebe o gesto para não roubar toques da página.
  static const double _kBackGestureEdgeWidth = 48;

  Widget _wrapRemoteWithEdgeBackGesture(Widget webView) {
    return Stack(
      fit: StackFit.expand,
      children: [
        webView,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _kBackGestureEdgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _edgeDragAccumDx = 0,
            onHorizontalDragUpdate: (details) {
              _edgeDragAccumDx += details.delta.dx;
            },
            onHorizontalDragEnd: (details) async {
              final vx = details.primaryVelocity ?? 0;
              final wentRight = _edgeDragAccumDx > 56 ||
                  (vx > 220 && _edgeDragAccumDx > 6);
              _edgeDragAccumDx = 0;
              if (!wentRight || !mounted) return;
              await _handleNavigateBack();
            },
            onHorizontalDragCancel: () => _edgeDragAccumDx = 0,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  Widget _buildWebView({
    required InAppWebViewSettings settings,
    required URLRequest initialRequest,
    UnmodifiableListView<UserScript>? userScripts,
  }) {
    return InAppWebView(
      initialSettings: settings,
      initialUserScripts: userScripts,
      initialUrlRequest: initialRequest,
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onDownloadStartRequest: (_, __) async {},
      onReceivedError: (controller, request, error) {
        // Alguns redirecionamentos podem gerar `NSURLErrorDomain error -999`
        // mesmo com o destino carregando normalmente. Não exibimos popup
        // porque não ajuda na UX.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final usePhoneDesktopLayout = shortest < 600;
    final userScripts = usePhoneDesktopLayout
        ? UnmodifiableListView<UserScript>([_kDesktopViewportUserScript])
        : null;

    if (widget.initialWebUri != null) {
      final remoteUri = widget.initialWebUri!;
      final webView = _buildWebView(
        settings: _settingsForRemote(
          usePhoneDesktopLayout: usePhoneDesktopLayout,
        ),
        initialRequest: URLRequest(url: remoteUri),
        userScripts: userScripts,
      );

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleNavigateBack();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: _wrapRemoteWithEdgeBackGesture(webView),
          ),
        ),
      );
    }

    final filePath = widget.fileAbsolutePath!;
    final readAccessDir = p.dirname(filePath);
    final fileUri = WebUri.uri(Uri.file(filePath));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: _buildWebView(
          settings: _settingsFor(
            readAccessDir,
            usePhoneDesktopLayout: usePhoneDesktopLayout,
          ),
          initialRequest: URLRequest(url: fileUri),
          userScripts: userScripts,
        ),
      ),
    );
  }
}
