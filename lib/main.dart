import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'page_ink.dart';
import 'reader_input.dart';
import 'reader_preferences.dart';
import 'library_backup_screen.dart';
import 'score_library.dart';
import 'setlists_screen.dart';

const _stand = Color(0xff202a28);
const _rail = Color(0xff2e3a36);
const _paper = Color(0xfff0eddf);
const _brass = Color(0xffe9bd75);

enum _ReaderDisplay { fit, performance, hideControls, gestures }

void main() => runApp(const EncoreSheets());

class EncoreSheets extends StatelessWidget {
  const EncoreSheets({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EncoreSheets',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _brass,
        onPrimary: _stand,
        surface: _rail,
        onSurface: _paper,
      ),
      scaffoldBackgroundColor: _stand,
    ),
    home: const Reader(),
  );
}

class Reader extends StatefulWidget {
  const Reader({super.key});

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  PdfViewerController _viewer = PdfViewerController();
  final _ink = <int, PageInk>{};
  final _focus = FocusNode(debugLabel: 'Score reader');
  late final _library = ScoreLibrary(LibraryStorage.create());
  late final _libraryReady = _library.load();
  ScoreEntry? _entry;
  XFile? _file;
  Uint8List? _bytes;
  int _revision = 0;
  int _page = 1;
  int _initialPage = 1;
  int _pages = 0;
  double? _seek;
  bool _showControls = true;
  bool _inking = false;
  bool _allowFinger = false;
  bool _picking = false;
  bool _saveWarning = false;
  bool _inkSaveWarning = false;
  InkTool _tool = InkTool.pen;
  final _edgeTaps = _EdgeTapTracker();
  bool _dispatchingEdgeLink = false;
  Setlist? _playing;
  int _setIndex = 0;
  bool _performance = false;
  ReaderPreferences _preferences = const ReaderPreferences();
  static const _sharedImports = MethodChannel('encoresheets/import');
  bool _sharedWaiting = false;
  late final AppLifecycleListener _lifecycle;

  bool get _hasNextScore =>
      _playing != null && _setIndex + 1 < _playing!.scores.length;

  String get _title => _entry?.title ?? 'First Light';
  bool get _supportsSharedImport =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_performance) _keepScreenAwake(true);
      },
    );
    if (_supportsSharedImport) {
      _sharedImports.setMethodCallHandler((call) async {
        if (call.method == 'available') _requestSharedImport();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestSharedImport();
      });
    }
  }

  Future<void> _restorePreferences() async {
    try {
      final data = await _library.storage.readPreferences();
      if (mounted) {
        setState(() => _preferences = ReaderPreferences.fromJson(data));
      }
    } catch (_) {
      // Use the default controls if preferences are unavailable.
    }
  }

  void _performTap(int zone) {
    final action = _performance
        ? switch (zone) {
            -1 => ReaderTapAction.previous,
            1 => ReaderTapAction.next,
            _ => ReaderTapAction.none,
          }
        : switch (zone) {
            -1 => _preferences.left,
            1 => _preferences.right,
            _ => _preferences.center,
          };
    switch (action) {
      case ReaderTapAction.previous:
        _go(_page - 1);
      case ReaderTapAction.next:
        _go(_page + 1);
      case ReaderTapAction.controls:
        setState(() => _showControls = !_showControls);
      case ReaderTapAction.markup:
        _toggleInk();
      case ReaderTapAction.none:
        break;
    }
  }

  Future<void> _configureGestures() async {
    var left = _preferences.left;
    var center = _preferences.center;
    var right = _preferences.right;
    final configured = await showDialog<ReaderPreferences>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          Widget choice(
            String label,
            ReaderTapAction value,
            ValueChanged<ReaderTapAction> set,
          ) => DropdownButton<ReaderTapAction>(
            isExpanded: true,
            value: value,
            items: [
              for (final action in ReaderTapAction.values)
                DropdownMenuItem(
                  value: action,
                  child: Text('$label: ${action.label}'),
                ),
            ],
            onChanged: (action) {
              if (action != null) update(() => set(action));
            },
          );
          return AlertDialog(
            title: const Text('Reader gestures'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                choice('Left', left, (value) => left = value),
                choice('Center', center, (value) => center = value),
                choice('Right', right, (value) => right = value),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const ReaderPreferences()),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  ReaderPreferences(left: left, center: center, right: right),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (configured == null || !mounted) return;
    try {
      await _library.storage.writePreferences(configured.toJson());
      if (mounted) setState(() => _preferences = configured);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save reader settings.')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_supportsSharedImport) {
      _sharedImports.setMethodCallHandler(null);
    }
    _lifecycle.dispose();
    if (_performance) _keepScreenAwake(false);
    _focus.dispose();
    for (final ink in _ink.values) {
      ink.dispose();
    }
    super.dispose();
  }

  void _requestSharedImport() {
    _sharedWaiting = true;
    _drainSharedImports();
  }

  Future<void> _drainSharedImports() async {
    if (!_sharedWaiting || _picking || !mounted) return;
    _sharedWaiting = false;
    setState(() => _picking = true);
    try {
      final paths = await _sharedImports.invokeListMethod<String>('take') ?? [];
      if (paths.isEmpty || !mounted) return;
      await _libraryReady;
      await _importScores(paths.map(XFile.new).toList());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not receive the shared PDFs.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  void _finishPicking() {
    if (!mounted) return;
    setState(() => _picking = false);
    _focus.requestFocus();
    if (_sharedWaiting) _drainSharedImports();
  }

  Future<void> _open() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF scores',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ],
      );
      if (files.isEmpty || !mounted) return;
      await _libraryReady;
      await _importScores(files);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not import the selected PDF.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _importScores(List<XFile> files) async {
    (ScoreEntry, XFile)? first;
    var failed = 0;
    for (final file in files) {
      try {
        final imported = await _library.import(file);
        first ??= imported;
      } catch (_) {
        failed++;
      }
    }
    if (first case (final entry, final local)) {
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      if (!mounted) return;
      _playing = null;
      _load(entry, local, bytes);
    }
    if (failed > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not import $failed of ${files.length} selected PDFs.',
          ),
        ),
      );
    }
  }

  Future<T?> _openReaderPanel<T>(WidgetBuilder builder) {
    if (MediaQuery.sizeOf(context).width < 720) {
      return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
    }
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black38,
      pageBuilder: (context, _, _) => SafeArea(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 368,
            height: double.infinity,
            child: Material(
              elevation: 12,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadiusDirectional.only(
                topEnd: Radius.circular(16),
                bottomEnd: Radius.circular(16),
              ),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLibrary({bool setlists = false}) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      await _library.flush();
      if (!mounted) return;
      final result = setlists
          ? 'setlists'
          : await _openReaderPanel<String>(
              (_) => _LibraryScreen(
                scores: _library.recent,
                persistent: _library.storage.persistent,
              ),
            );
      if (result == null || !mounted) return;
      if (result == 'import') {
        setState(() => _picking = false);
        await _open();
        return;
      }
      if (result == 'sample') {
        _playing = null;
        if (_entry != null) _load(null, null, null);
        return;
      }
      if (result == 'setlists') {
        final setlist = await _openReaderPanel<Setlist>(
          (_) => SetlistsScreen(library: _library),
        );
        if (setlist != null && mounted) await _playScore(setlist, 0);
        return;
      }
      if (result == 'backup') {
        await _openReaderPanel<void>(
          (_) => LibraryBackupScreen(library: _library),
        );
        return;
      }
      final entry = _library.lookup(result)!;
      final local = await _library.storage.openScore(entry.id);
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      if (!mounted) return;
      if (_entry?.id != entry.id) {
        final annotations = await _library.readInk(entry.id);
        if (!mounted) return;
        _load(entry, local, bytes, annotations: annotations);
      }
      setState(() => _playing = null);
      _remember(entry.id, _page, opened: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the library or score.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _playScore(Setlist setlist, int index) async {
    final entry = _library.lookup(setlist.scores[index]);
    if (entry == null) throw StateError('Setlist score is missing');
    final local = await _library.storage.openScore(entry.id);
    final bytes = kIsWeb ? await local.readAsBytes() : null;
    final annotations = await _library.readInk(entry.id);
    if (!mounted) return;
    _load(entry, local, bytes, annotations: annotations, startPage: 1);
    setState(() {
      _playing = setlist;
      _setIndex = index;
    });
    _remember(entry.id, 1, opened: true);
  }

  Future<void> _nextScore() async {
    if (_picking || !_hasNextScore) return;
    setState(() => _picking = true);
    try {
      await _playScore(_playing!, _setIndex + 1);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the next score.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _keepScreenAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      if (enabled && mounted && _performance) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not keep the screen awake.')),
        );
      }
    }
  }

  void _togglePerformance() {
    _ink[_page]?.finish(commit: false);
    setState(() {
      _performance = !_performance;
      _inking = false;
      _showControls = true;
    });
    _keepScreenAwake(_performance);
    _focus.requestFocus();
  }

  Future<void> _remember(String? id, int page, {bool opened = false}) async {
    if (id == null) return;
    try {
      await _library.record(id, page, opened: opened);
      _saveWarning = false;
    } catch (_) {
      if (!mounted || _saveWarning) return;
      _saveWarning = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the reading position.')),
      );
    }
  }

  Future<void> _saveInk() async {
    final id = _entry?.id;
    if (id == null) return;
    final pages = <String, dynamic>{};
    for (final MapEntry(key: page, value: ink) in _ink.entries) {
      final strokes = ink.snapshot();
      if (strokes.isNotEmpty) pages['$page'] = strokes;
    }
    try {
      await _library.writeInk(id, pages);
      _inkSaveWarning = false;
    } catch (_) {
      if (!mounted || _inkSaveWarning) return;
      _inkSaveWarning = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save score annotations.')),
      );
    }
  }

  void _load(
    ScoreEntry? entry,
    XFile? file,
    Uint8List? bytes, {
    Map<String, dynamic> annotations = const {},
    int? startPage,
  }) {
    final restoredInk = {
      for (final MapEntry(key: page, value: strokes) in annotations.entries)
        int.parse(page): PageInk(
          saved: strokes as List<dynamic>,
          onChanged: _saveInk,
        ),
    };
    final retiredInk = _ink.values.toList();
    setState(() {
      _entry = entry;
      _file = file;
      _bytes = bytes;
      _revision++;
      _viewer = PdfViewerController();
      _ink.clear();
      _ink.addAll(restoredInk);
      _page = _initialPage = startPage ?? entry?.page ?? 1;
      _pages = 0;
      _seek = null;
      _inking = false;
      _showControls = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ink in retiredInk) {
        ink.dispose();
      }
    });
  }

  void _go(int page) {
    if (_picking || !_viewer.isReady || _pages == 0) return;
    if (page > _pages && _hasNextScore) {
      _nextScore();
      return;
    }
    final target = page.clamp(1, _pages);
    if (target == _page) return;
    _ink[_page]?.finish(commit: false);
    setState(() => _page = target);
    _viewer.goToPage(pageNumber: target, duration: Duration.zero);
    _remember(_entry?.id, target);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_performance && key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _togglePerformance();
      return KeyEventResult.handled;
    }
    final step = pageTurnForKey(key);
    if (step == 0 || _picking || _pages == 0) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _go(_page + step);
    return KeyEventResult.handled;
  }

  void _toggleInk() {
    if (_pages == 0) return;
    _ink[_page]?.finish(commit: false);
    setState(() {
      _inking = !_inking;
      _showControls = true;
    });
    _focus.requestFocus();
  }

  void _fit() {
    if (!_viewer.isReady) return;
    _viewer.goTo(_viewer.calcMatrixForFit(pageNumber: _page));
    _focus.requestFocus();
  }

  Widget _score() {
    final revision = _revision;
    final pageBeforeResize = _page;
    final params = PdfViewerParams(
      backgroundColor: _stand,
      layoutStrategy: const SequentialPagesLayout(
        scrollDirection: Axis.horizontal,
        fitMode: PdfFitMode.fit,
        margin: 12,
      ),
      paging: const PdfPaging(duration: Duration(milliseconds: 140)),
      pageAnchor: PdfPageAnchor.center,
      pageDropShadow: const BoxShadow(
        color: Colors.black54,
        blurRadius: 14,
        offset: Offset(0, 6),
      ),
      panEnabled: !_inking,
      scaleEnabled: !_inking && !_performance,
      enableKeyboardNavigation: false,
      horizontalCacheExtent: 1.5,
      maxImageBytesCachedOnMemory: 72 * 1024 * 1024,
      linkHandlerParams: _inking
          ? null
          : PdfLinkHandlerParams(
              enableAutoLinkDetection: false,
              linkColor: Colors.transparent,
              linkHoverColor: _brass.withValues(alpha: .22),
              onLinkTap: (link) {
                final destination = link.dest;
                if (destination == null ||
                    (_edgeTaps.handled && !_dispatchingEdgeLink) ||
                    revision != _revision ||
                    !_viewer.isReady) {
                  return;
                }
                _viewer.goToDest(destination, duration: Duration.zero);
              },
            ),
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _edgeTaps.down(
              event,
              size.width,
              canAdvance:
                  !_inking &&
                  _hasNextScore &&
                  _pages > 0 &&
                  _page == _pages &&
                  _viewer.isReady &&
                  _viewer.currentZoom <= _viewer.coverScale * 1.02,
            ),
            onPointerMove: _edgeTaps.move,
            onPointerCancel: _edgeTaps.cancel,
            onPointerUp: (event) {
              final (step, forwardSwipe) = _edgeTaps.up(event);
              if (forwardSwipe) {
                _nextScore();
                return;
              }
              if (step == 0 || _inking || !_viewer.isReady) return;
              _focus.requestFocus();
              // Route links before turning the page. Ignore the later tap
              // callback from the viewer's double-tap recognizer.
              _dispatchingEdgeLink = true;
              try {
                if (!handleLinkTap(event.localPosition)) _performTap(step);
              } finally {
                _dispatchingEdgeLink = false;
              }
            },
          ),
        ),
      ],
      onViewerReady: (document, controller) {
        if (!mounted || revision != _revision) return;
        final count = document.pages.length;
        if (count == 0) return;
        final restored = _page.clamp(1, count);
        setState(() {
          _pages = count;
          _page = restored;
        });
        _remember(_entry?.id, restored);
      },
      onViewSizeChanged: (size, previous, controller) {
        if (!mounted || previous == null || revision != _revision) return;
        // Keep the score on the same page when the controls resize the viewport.
        controller.goToPage(
          pageNumber: pageBeforeResize,
          duration: Duration.zero,
        );
      },
      onPageChanged: (page) {
        if (!mounted ||
            revision != _revision ||
            _pages == 0 ||
            page == null ||
            page == _page) {
          return;
        }
        setState(() => _page = page);
        _remember(_entry?.id, page);
      },
      onGeneralTap: (context, controller, details) {
        if (_inking) return true;
        if (_performance && details.type == PdfViewerGeneralTapType.doubleTap) {
          return true;
        }
        if (details.type == PdfViewerGeneralTapType.longPress) {
          if (!_performance) _toggleInk();
          return true;
        }
        final step = _EdgeTapTracker.direction(
          details.localPosition.dx,
          controller.viewSize.width,
        );
        if (step != 0) return true;
        if (details.type != PdfViewerGeneralTapType.tap) return false;
        _focus.requestFocus();
        _performTap(0);
        return true;
      },
      pageOverlaysBuilder: (context, rect, page) => [
        Positioned.fill(
          child: InkSurface(
            key: ValueKey(page.pageNumber),
            ink: _ink.putIfAbsent(
              page.pageNumber,
              () => PageInk(onChanged: _saveInk),
            ),
            enabled: _inking,
            allowFinger: _allowFinger,
            tool: _tool,
          ),
        ),
      ],
      loadingBannerBuilder: (_, _, _) =>
          const Center(child: CircularProgressIndicator()),
      errorBannerBuilder: (_, _, _, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 36),
              const SizedBox(height: 12),
              const Text('This PDF could not be opened.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _picking ? null : _open,
                    child: const Text('Open another PDF'),
                  ),
                  TextButton(
                    onPressed: () {
                      _playing = null;
                      _load(null, null, null);
                    },
                    child: const Text('Open sample'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final key = ValueKey(revision);
    final file = _file;
    if (file == null) {
      return PdfViewer.asset(
        'assets/first_light.pdf',
        key: key,
        controller: _viewer,
        params: params,
      );
    }
    final bytes = _bytes;
    if (bytes != null) {
      return PdfViewer.data(
        bytes,
        sourceName: file.name,
        initialPageNumber: _initialPage,
        key: key,
        controller: _viewer,
        params: params,
      );
    }
    return PdfViewer.file(
      file.path,
      initialPageNumber: _initialPage,
      key: key,
      controller: _viewer,
      params: params,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PopScope(
      canPop: !_performance,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _performance) _togglePerformance();
      },
      child: SafeArea(
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            children: [
              if (_showControls && !_performance) _header(),
              Expanded(key: const ValueKey('score-viewport'), child: _score()),
              if (_performance)
                _performanceBar()
              else if (_showControls)
                _footer(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Material(
    color: _rail,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Score library',
                  onPressed: _picking ? null : _showLibrary,
                  icon: const Icon(Icons.library_music_outlined),
                ),
                IconButton(
                  tooltip: 'Setlists',
                  onPressed: _picking
                      ? null
                      : () => _showLibrary(setlists: true),
                  icon: const Icon(Icons.queue_music),
                ),
              ],
            ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontFamily: 'serif',
                  color: _paper,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: _inking ? 'Done marking up' : 'Mark up score',
                  onPressed: _pages == 0 ? null : _toggleInk,
                  color: _inking ? _brass : null,
                  icon: Icon(_inking ? Icons.check : Icons.draw_outlined),
                ),
                PopupMenuButton<_ReaderDisplay>(
                  tooltip: 'Display options',
                  enabled: _pages > 0 && !_picking,
                  icon: const Icon(Icons.tune),
                  onSelected: (action) {
                    switch (action) {
                      case _ReaderDisplay.fit:
                        _fit();
                      case _ReaderDisplay.performance:
                        _togglePerformance();
                      case _ReaderDisplay.hideControls:
                        setState(() => _showControls = false);
                      case _ReaderDisplay.gestures:
                        _configureGestures();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _ReaderDisplay.fit,
                      child: Text('Fit page'),
                    ),
                    const PopupMenuItem(
                      value: _ReaderDisplay.performance,
                      child: Text('Performance mode'),
                    ),
                    PopupMenuItem(
                      value: _ReaderDisplay.hideControls,
                      enabled:
                          !_inking &&
                          [
                            _preferences.left,
                            _preferences.center,
                            _preferences.right,
                          ].contains(ReaderTapAction.controls),
                      child: const Text('Hide controls'),
                    ),
                    const PopupMenuItem(
                      value: _ReaderDisplay.gestures,
                      child: Text('Reader gestures'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _performanceBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _playing == null
                ? _title
                : '${_playing!.name} · ${_setIndex + 1}/${_playing!.scores.length} · $_title',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(_pages == 0 ? '–' : '$_page / $_pages'),
        IconButton(
          tooltip: 'Exit performance mode',
          onPressed: _togglePerformance,
          icon: const Icon(Icons.fullscreen_exit),
        ),
      ],
    ),
  );

  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
    child: Material(
      color: _rail,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_inking)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _toolButton(InkTool.pen, Icons.edit_outlined, 'Pen'),
                _toolButton(
                  InkTool.highlighter,
                  Icons.highlight,
                  'Highlighter',
                ),
                _toolButton(
                  InkTool.eraser,
                  Icons.backspace_outlined,
                  'Erase strokes',
                ),
                Semantics(
                  label: 'Allow finger drawing',
                  child: ChoiceChip(
                    label: const Text('Finger'),
                    selected: _allowFinger,
                    onSelected: (enabled) =>
                        setState(() => _allowFinger = enabled),
                  ),
                ),
                IconButton(
                  tooltip: 'Undo stroke',
                  onPressed: () => _ink[_page]?.undo(),
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page <= 1 ? null : () => _go(_page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Slider(
                  // A saved page is known before the PDF has loaded its count.
                  value: _pages > 1
                      ? (_seek ?? _page.toDouble()).clamp(
                          1.0,
                          _pages.toDouble(),
                        )
                      : 1.0,
                  min: 1,
                  max: _pages > 1 ? _pages.toDouble() : 2,
                  divisions: _pages > 1 ? _pages - 1 : null,
                  semanticFormatterCallback: (value) => 'Page ${value.round()}',
                  onChanged: _pages > 1
                      ? (value) => setState(() => _seek = value)
                      : null,
                  onChangeEnd: (value) {
                    setState(() => _seek = null);
                    _go(value.round());
                    _focus.requestFocus();
                  },
                ),
              ),
              Text(_pages == 0 ? '–' : '${(_seek ?? _page).round()} / $_pages'),
              IconButton(
                tooltip: _page == _pages && _hasNextScore
                    ? 'Next score'
                    : 'Next page',
                onPressed: _pages == 0 || (_page >= _pages && !_hasNextScore)
                    ? null
                    : () => _go(_page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _toolButton(InkTool tool, IconData icon, String label) => IconButton(
    tooltip: label,
    isSelected: _tool == tool,
    color: _tool == tool ? _brass : null,
    onPressed: () => setState(() => _tool = tool),
    icon: Icon(icon),
  );
}

class _EdgeTapTracker {
  static const _slop = 12.0;
  static const _maximumDuration = Duration(milliseconds: 300);
  final _pointers = <int>{};
  PointerDownEvent? _start;
  int _step = 0;
  bool _moved = false;
  bool _canAdvance = false;
  bool handled = false;

  static int direction(double x, double width) {
    if (x < width * .24) return -1;
    if (x > width * .76) return 1;
    return 0;
  }

  void down(PointerDownEvent event, double width, {required bool canAdvance}) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1) {
      _start = null;
      return;
    }
    handled = false;
    _moved = false;
    _canAdvance = canAdvance;
    _step = direction(event.localPosition.dx, width);
    _start = event.buttons == 1 ? event : null;
  }

  void move(PointerMoveEvent event) {
    final start = _start;
    if (start != null &&
        event.pointer == start.pointer &&
        (event.position - start.position).distance > _slop) {
      _moved = true;
    }
  }

  (int, bool) up(PointerUpEvent event) {
    final start = _start;
    cancel(event);
    if (start == null || start.pointer != event.pointer) return (0, false);
    final delta = event.position - start.position;
    if (_canAdvance && delta.dx < -45 && -delta.dx > delta.dy.abs() * 1.5) {
      return (0, true);
    }
    if (_step == 0 ||
        _moved ||
        event.timeStamp - start.timeStamp > _maximumDuration ||
        delta.distance > _slop)
      return (0, false);
    handled = true;
    return (_step, false);
  }

  void cancel(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_start?.pointer == event.pointer) _start = null;
  }
}

class _LibraryScreen extends StatefulWidget {
  const _LibraryScreen({required this.scores, required this.persistent});

  final List<ScoreEntry> scores;
  final bool persistent;

  @override
  State<_LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<_LibraryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.scores
        .where((score) => score.title.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Score library')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search scores',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'import'),
                        icon: const Icon(Icons.add),
                        label: const Text('Import PDF'),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, 'setlists'),
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Setlists'),
                      ),
                      if (widget.persistent)
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context, 'backup'),
                          icon: const Icon(Icons.settings_backup_restore),
                          label: const Text('Backup & restore'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!widget.persistent)
                    const Text(
                      'Browser preview keeps scores for this session.',
                    ),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'No imported scores yet.'
                                  : 'No matching scores.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final score = visible[index];
                              return ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(score.title),
                                subtitle: Text('Resume at page ${score.page}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(context, score.id),
                              );
                            },
                          ),
                  ),
                  if (_query.isEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, 'sample'),
                        child: const Text('Open sample score'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
