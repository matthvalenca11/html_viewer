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
          builder: (context) => HtmlViewerPage(fileAbsolutePath: path),
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
    return Scaffold(
      backgroundColor: surface,
      body: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : FilledButton(
                onPressed: _pickAndOpen,
                child: const Text('Abrir Arquivo'),
              ),
      ),
    );
  }
}

class HtmlViewerPage extends StatefulWidget {
  const HtmlViewerPage({super.key, required this.fileAbsolutePath});

  final String fileAbsolutePath;

  @override
  State<HtmlViewerPage> createState() => _HtmlViewerPageState();
}

class _HtmlViewerPageState extends State<HtmlViewerPage> {
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

  @override
  Widget build(BuildContext context) {
    final filePath = widget.fileAbsolutePath;
    final readAccessDir = p.dirname(filePath);
    final fileUri = WebUri.uri(Uri.file(filePath));
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final usePhoneDesktopLayout = shortest < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: InAppWebView(
          initialSettings: _settingsFor(
            readAccessDir,
            usePhoneDesktopLayout: usePhoneDesktopLayout,
          ),
          initialUserScripts: usePhoneDesktopLayout
              ? UnmodifiableListView<UserScript>([_kDesktopViewportUserScript])
              : null,
          initialUrlRequest: URLRequest(url: fileUri),
          onDownloadStartRequest: (_, __) async {},
          onReceivedError: (controller, request, error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro ao carregar página: ${error.description}',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
