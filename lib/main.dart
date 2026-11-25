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
import 'bookmarks_screen.dart';
import 'score_library.dart';
import 'score_metadata_screen.dart';
import 'setlists_screen.dart';

const _stand = Color(0xff202a28);
const _rail = Color(0xff2e3a36);
const _paper = Color(0xfff0eddf);
const _brass = Color(0xffe9bd75);

enum _ReaderDisplay {
  fit,
  zoomIn,
  zoomOut,
  previousPage,
  previousScore,
  bookmarks,
  performance,
  hideControls,
  gestures,
  keepAwake,
  nextTitle,
}

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
  ScoreBookmark? _itemBookmark;
  XFile? _file;
  Uint8List? _bytes;
  int _revision = 0;
  int _page = 1;
  int _initialPage = 1;
  int? _previousPage;
  ({String? id, int page})? _previousItem;
  int _pages = 0;
  double? _seek;
  bool _showControls = true;
  bool _inking = false;
  bool _allowFinger = false;
  bool _picking = false;
  bool _saveWarning = false;
  bool _inkSaveWarning = false;
  InkTool _tool = InkTool.pen;
  double? _penWidth;
  int? _penColor;
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

  int get _firstPage =>
      (_itemBookmark?.page ?? 1).clamp(1, _pages > 0 ? _pages : 1);
  int get _lastPage => (_itemBookmark?.endPage ?? _pages).clamp(
    _firstPage,
    _pages > 0 ? _pages : 1,
  );

  String? get _nextTitle {
    if (!_preferences.showNextTitle ||
        !_hasNextScore ||
        _pages == 0 ||
        _page != _lastPage)
      return null;
    final next = _library.lookupSelection(_playing!.scores[_setIndex + 1]);
    return next?.$2?.title ?? next?.$1.title;
  }

  String get _title => _itemBookmark?.title ?? _entry?.title ?? 'First Light';
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
        if (_performance || _preferences.keepAwake) _keepScreenAwake(true);
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
        if (_preferences.keepAwake) _keepScreenAwake(true);
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
                onPressed: () => Navigator.pop(
                  context,
                  ReaderPreferences(
                    keepAwake: _preferences.keepAwake,
                    showNextTitle: _preferences.showNextTitle,
                  ),
                ),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  ReaderPreferences(
                    left: left,
                    center: center,
                    right: right,
                    keepAwake: _preferences.keepAwake,
                    showNextTitle: _preferences.showNextTitle,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (configured == null || !mounted) return;
    await _savePreferences(configured);
  }

  Future<void> _savePreferences(ReaderPreferences configured) async {
    try {
      await _library.updatePreferences(configured.toJson());
      if (mounted) {
        setState(() => _preferences = configured);
        _keepScreenAwake(_performance || _preferences.keepAwake);
      }
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
    if (_performance || _preferences.keepAwake) _keepScreenAwake(false);
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
                library: _library,
                scores: _library.recent,
                setlists: _library.setlists,
                persistent: _library.storage.persistent,
              ),
            );
      if (result == null || !mounted) return;
      if (result == 'batch') {
        final edit = await editBatchMetadata(context, _library.recent);
        if (edit != null) {
          await _library.batchMetadata(
            edit.ids,
            edit.field,
            edit.value,
            append: edit.append,
          );
          if (mounted && _entry != null) {
            setState(() => _entry = _library.lookup(_entry!.id));
          }
        }
        return;
      }
      if (result.startsWith('edit:')) {
        final score = _library.lookup(result.substring(5));
        if (score != null) await _editScore(score);
        return;
      }
      if (result.startsWith('set:')) {
        final match = _library.setlists.firstWhere(
          (list) => list.id == result.substring(4),
        );
        if (match.scores.isNotEmpty) await _playScore(match, 0);
        return;
      }
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
      if (result.startsWith('bookmark:')) {
        final parts = result.split(':');
        final entry = _library.lookup(parts[1])!;
        final bookmark = entry.bookmarks.firstWhere(
          (item) => item.id == parts[2],
        );
        await _openLibraryScore(
          entry,
          startPage: bookmark.page,
          item: bookmark.isItem ? bookmark : null,
        );
      } else {
        await _openLibraryScore(_library.lookup(result)!);
      }
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

  Future<void> _openLibraryScore(
    ScoreEntry entry, {
    int? startPage,
    ScoreBookmark? item,
  }) async {
    if (_entry?.id != entry.id || _itemBookmark?.id != item?.id) {
      final local = await _library.storage.openScore(entry.id);
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      final annotations = await _library.readInk(entry.id);
      if (!mounted) return;
      _load(
        entry,
        local,
        bytes,
        annotations: annotations,
        startPage: startPage,
        item: item,
      );
    } else if (startPage != null) {
      _jumpToPage(startPage);
    }
    setState(() => _playing = null);
    _remember(entry.id, _page, opened: true);
  }

  Future<void> _showBookmarks() async {
    final entry = _entry;
    if (entry == null || _picking || _pages == 0) return;
    setState(() => _picking = true);
    try {
      final bookmark = await _openReaderPanel<ScoreBookmark>(
        (_) => BookmarksScreen(
          library: _library,
          scoreId: entry.id,
          page: _page,
          pageCount: _pages,
        ),
      );
      if (mounted && bookmark != null) {
        if (bookmark.isItem || _itemBookmark != null) {
          await _openLibraryScore(
            entry,
            startPage: bookmark.page,
            item: bookmark.isItem ? bookmark : null,
          );
        } else {
          _jumpToPage(bookmark.page);
        }
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _playScore(Setlist setlist, int index) async {
    final selection = _library.lookupSelection(setlist.scores[index]);
    if (selection == null) throw StateError('Setlist score is missing');
    final (entry, item) = selection;
    final local = await _library.storage.openScore(entry.id);
    final bytes = kIsWeb ? await local.readAsBytes() : null;
    final annotations = await _library.readInk(entry.id);
    if (!mounted) return;
    final start = item?.page ?? 1;
    _load(
      entry,
      local,
      bytes,
      annotations: annotations,
      startPage: start,
      item: item,
    );
    setState(() {
      _playing = setlist;
      _setIndex = index;
    });
    _remember(entry.id, start, opened: true);
  }

  Future<void> _editScore(ScoreEntry score) async {
    final updated = await editScoreMetadata(context, score);
    if (updated == null || !mounted) return;
    try {
      await _library.editMetadata(score.id, updated.title, updated.fields);
      if (mounted && _entry?.id == score.id) {
        setState(() => _entry = _library.lookup(score.id));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save score details.')),
        );
    }
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
      if (enabled && mounted && (_performance || _preferences.keepAwake)) {
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
    _keepScreenAwake(_performance || _preferences.keepAwake);
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
    ScoreBookmark? item,
  }) {
    if (_entry?.id != entry?.id) {
      _previousItem = (id: _entry?.id, page: _page);
    }
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
      _itemBookmark = item;
      _file = file;
      _bytes = bytes;
      _revision++;
      _viewer = PdfViewerController();
      _ink.clear();
      _ink.addAll(restoredInk);
      _page = _initialPage = startPage ?? entry?.page ?? 1;
      _previousPage = null;
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
    if (page > _lastPage && _hasNextScore) {
      _nextScore();
      return;
    }
    _jumpToPage(page);
  }

  void _jumpToPage(int page) {
    if (!_viewer.isReady || _pages == 0) return;
    final target = page.clamp(_firstPage, _lastPage);
    if (target == _page) return;
    _ink[_page]?.finish(commit: false);
    _previousPage = _page;
    setState(() => _page = target);
    _viewer.goToPage(pageNumber: target, duration: Duration.zero);
    _remember(_entry?.id, target);
  }

  Future<void> _returnToPreviousScore() async {
    final previous = _previousItem;
    if (previous == null || _picking) return;
    setState(() => _picking = true);
    try {
      final id = previous.id;
      if (id == null) {
        _playing = null;
        _load(null, null, null, startPage: previous.page);
        return;
      }
      final score = _library.lookup(id);
      if (score == null) return;
      final local = await _library.storage.openScore(id);
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      final annotations = await _library.readInk(id);
      if (!mounted) return;
      _playing = null;
      _load(
        score,
        local,
        bytes,
        annotations: annotations,
        startPage: previous.page,
      );
      _remember(id, _page, opened: true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reopen the previous score.')),
        );
    } finally {
      _finishPicking();
    }
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
                    (_itemBookmark != null &&
                        (destination.pageNumber < _firstPage ||
                            destination.pageNumber > _lastPage)) ||
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
                  _page == _lastPage &&
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
        if (page < _firstPage || page > _lastPage) {
          _viewer.goToPage(
            pageNumber: page.clamp(_firstPage, _lastPage),
            duration: Duration.zero,
          );
          return;
        }
        _previousPage = _page;
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
        if (details.type == PdfViewerGeneralTapType.doubleTap) {
          if (controller.currentZoom > controller.coverScale * 1.02) {
            _fit();
          } else {
            controller.zoomUpOnLocalPosition(
              localPosition: details.localPosition,
            );
          }
          return true;
        }
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
            width: _tool == InkTool.pen ? _penWidth : null,
            color: _tool == InkTool.pen ? _penColor : null,
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
        initialPageNumber: _initialPage,
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
              if (_nextTitle case final title?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Next: $title', overflow: TextOverflow.ellipsis),
                ),
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
            child: GestureDetector(
              onTap: _entry == null || _picking
                  ? null
                  : () => _editScore(_entry!),
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
                      case _ReaderDisplay.zoomIn:
                        if (_viewer.isReady) _viewer.zoomUp();
                      case _ReaderDisplay.zoomOut:
                        if (_viewer.isReady) _viewer.zoomDown();
                      case _ReaderDisplay.previousPage:
                        if (_previousPage case final page?) _go(page);
                      case _ReaderDisplay.previousScore:
                        _returnToPreviousScore();
                      case _ReaderDisplay.bookmarks:
                        _showBookmarks();
                      case _ReaderDisplay.performance:
                        _togglePerformance();
                      case _ReaderDisplay.hideControls:
                        setState(() => _showControls = false);
                      case _ReaderDisplay.gestures:
                        _configureGestures();
                      case _ReaderDisplay.keepAwake:
                        _savePreferences(
                          ReaderPreferences(
                            left: _preferences.left,
                            center: _preferences.center,
                            right: _preferences.right,
                            keepAwake: !_preferences.keepAwake,
                            showNextTitle: _preferences.showNextTitle,
                          ),
                        );
                      case _ReaderDisplay.nextTitle:
                        _savePreferences(
                          ReaderPreferences(
                            left: _preferences.left,
                            center: _preferences.center,
                            right: _preferences.right,
                            keepAwake: _preferences.keepAwake,
                            showNextTitle: !_preferences.showNextTitle,
                          ),
                        );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _ReaderDisplay.fit,
                      child: Text('Fit page'),
                    ),
                    const PopupMenuItem(
                      value: _ReaderDisplay.zoomIn,
                      child: Text('Zoom in'),
                    ),
                    const PopupMenuItem(
                      value: _ReaderDisplay.zoomOut,
                      child: Text('Zoom out'),
                    ),
                    PopupMenuItem(
                      value: _ReaderDisplay.previousPage,
                      enabled: _previousPage != null,
                      child: const Text('Jump back to previous page'),
                    ),
                    PopupMenuItem(
                      value: _ReaderDisplay.previousScore,
                      enabled: _previousItem != null,
                      child: const Text('Return to previous score'),
                    ),
                    PopupMenuItem(
                      value: _ReaderDisplay.bookmarks,
                      enabled: _entry != null,
                      child: const Text('Bookmarks'),
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
                    CheckedPopupMenuItem(
                      value: _ReaderDisplay.keepAwake,
                      checked: _preferences.keepAwake,
                      child: const Text('Keep screen awake'),
                    ),
                    CheckedPopupMenuItem(
                      value: _ReaderDisplay.nextTitle,
                      checked: _preferences.showNextTitle,
                      child: const Text('Show next score title'),
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

  Future<void> _showThumbnails() async {
    if (_picking || _pages == 0 || !_viewer.isReady) return;
    final document = _viewer.document;
    final start = _firstPage;
    final count = _lastPage - start + 1;
    setState(() => _picking = true);
    int? destination;
    try {
      destination = await _openReaderPanel<int>(
        (context) => Scaffold(
          appBar: AppBar(title: const Text('Pages')),
          body: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 142,
              childAspectRatio: .68,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: count,
            itemBuilder: (context, index) {
              final page = index + start;
              return OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(6),
                  side: BorderSide(color: page == _page ? _brass : _rail),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context, page),
                child: Column(
                  children: [
                    Expanded(
                      child: PdfPageView(
                        document: document,
                        pageNumber: page,
                        maximumDpi: 54,
                      ),
                    ),
                    Text('Page $page'),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } finally {
      _finishPicking();
    }
    if (mounted && destination != null) _go(destination);
  }

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
                if (_tool == InkTool.pen)
                  PopupMenuButton<(double, int)>(
                    tooltip: 'Pen style',
                    icon: const Icon(Icons.color_lens_outlined),
                    onSelected: (style) => setState(() {
                      _penWidth = style.$1;
                      _penColor = style.$2;
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: (.003, 0xff9b352e),
                        child: Text('Fine red'),
                      ),
                      PopupMenuItem(
                        value: (.006, 0xff9b352e),
                        child: Text('Broad red'),
                      ),
                      PopupMenuItem(
                        value: (.003, 0xff244a91),
                        child: Text('Fine blue'),
                      ),
                      PopupMenuItem(
                        value: (.006, 0xff262626),
                        child: Text('Broad black'),
                      ),
                    ],
                  ),
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
                IconButton(
                  tooltip: 'Redo stroke',
                  onPressed: () => _ink[_page]?.redo(),
                  icon: const Icon(Icons.redo),
                ),
              ],
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page <= _firstPage ? null : () => _go(_page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Slider(
                  // A saved page is known before the PDF has loaded its count.
                  value: _lastPage > _firstPage
                      ? (_seek ?? _page.toDouble()).clamp(
                          _firstPage.toDouble(),
                          _lastPage.toDouble(),
                        )
                      : _firstPage.toDouble(),
                  min: _firstPage.toDouble(),
                  max: _lastPage > _firstPage
                      ? _lastPage.toDouble()
                      : (_firstPage + 1).toDouble(),
                  divisions: _lastPage > _firstPage
                      ? _lastPage - _firstPage
                      : null,
                  semanticFormatterCallback: (value) => 'Page ${value.round()}',
                  onChanged: _lastPage > _firstPage
                      ? (value) => setState(() => _seek = value)
                      : null,
                  onChangeEnd: (value) {
                    setState(() => _seek = null);
                    _go(value.round());
                    _focus.requestFocus();
                  },
                ),
              ),
              TextButton(
                onPressed: _pages == 0 ? null : _showThumbnails,
                child: Text(
                  _pages == 0 ? '–' : '${(_seek ?? _page).round()} / $_pages',
                ),
              ),
              IconButton(
                tooltip: _page == _lastPage && _hasNextScore
                    ? 'Next score'
                    : 'Next page',
                onPressed: _pages == 0 || (_page >= _lastPage && !_hasNextScore)
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
  const _LibraryScreen({
    required this.library,
    required this.scores,
    required this.setlists,
    required this.persistent,
  });

  final List<ScoreEntry> scores;
  final ScoreLibrary library;
  final List<Setlist> setlists;
  final bool persistent;

  @override
  State<_LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<_LibraryScreen> {
  String _query = '';
  String _browseBy = 'Recent';
  String? _category;
  String? _collection;
  bool _excludeCollection = false;
  bool _unassigned = false;

  Future<void> _chooseCollection() => showDialog<void>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Libraries'),
      children: [
        SimpleDialogOption(
          onPressed: () => _filterCollection(dialog, null),
          child: const Text('All scores'),
        ),
        SimpleDialogOption(
          onPressed: () => _filterCollection(dialog, null, unassigned: true),
          child: const Text('Unassigned scores'),
        ),
        for (final name in widget.library.collections)
          ListTile(
            title: Text(name),
            onTap: () => _filterCollection(dialog, name),
            trailing: IconButton(
              tooltip: 'Exclude $name',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _filterCollection(dialog, name, exclude: true),
            ),
          ),
        SimpleDialogOption(
          onPressed: () {
            Navigator.pop(dialog);
            _createCollection();
          },
          child: const Text('New library'),
        ),
      ],
    ),
  );

  void _filterCollection(
    BuildContext dialog,
    String? name, {
    bool exclude = false,
    bool unassigned = false,
  }) {
    setState(() {
      _collection = name;
      _excludeCollection = exclude;
      _unassigned = unassigned;
      _category = null;
    });
    Navigator.pop(dialog);
  }

  Future<void> _createCollection() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('New library'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Library name'),
          onChanged: (value) => name = value,
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, name),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;
    await _saveCollectionChange(() => widget.library.createCollection(result));
  }

  Future<void> _assignCollections(ScoreEntry score) async {
    final checked = score.collections.toSet();
    final names = widget.library.collections;
    if (names.isEmpty) {
      await _createCollection();
      if (mounted && widget.library.collections.isNotEmpty)
        await _assignCollections(score);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: Text('Libraries for ${score.title}'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final name in names)
                  CheckboxListTile(
                    title: Text(name),
                    value: checked.contains(name),
                    onChanged: (selected) => refresh(() {
                      if (selected == true) {
                        checked.add(name);
                      } else {
                        checked.remove(name);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _saveCollectionChange(
        () => widget.library.assignCollections(score.id, checked),
      );
    }
  }

  Future<void> _saveCollectionChange(Future<void> Function() save) async {
    try {
      await save();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save libraries.')),
        );
    }
  }

  static const _fields = {
    'Composer': 'composer',
    'Genre': 'genre',
    'Label': 'label',
    'Tag': 'tags',
  };

  Iterable<String> _categories(ScoreEntry score) =>
      (score.metadata[_fields[_browseBy]] ?? '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final inCollection = widget.library.recent.where((score) {
      if (_unassigned) return score.collections.isEmpty;
      if (_collection == null) return true;
      return score.collections.contains(_collection) != _excludeCollection;
    }).toList();
    final visible = inCollection
        .where(
          (score) => [
            score.title,
            ...score.metadata.values,
          ].any((value) => value.toLowerCase().contains(_query)),
        )
        .where(
          (score) =>
              _category == null || _categories(score).contains(_category),
        )
        .toList();
    final categories = inCollection.expand(_categories).toSet().toList()
      ..sort();
    if (_browseBy != 'Recent') {
      visible.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }
    final matchingSets = _query.isEmpty
        ? <Setlist>[]
        : widget.setlists
              .where(
                (setlist) =>
                    setlist.scores.isNotEmpty &&
                    setlist.name.toLowerCase().contains(_query),
              )
              .toList();
    final actions =
        {
              'import': 'Import PDF',
              'setlists': 'Setlists',
              if (widget.persistent) 'backup': 'Backup & restore',
              'sample': 'Open sample score',
            }.entries
            .where(
              (entry) =>
                  _query.isNotEmpty &&
                  entry.value.toLowerCase().contains(_query),
            )
            .toList();
    final matchingBookmarks = [
      for (final score in inCollection)
        for (final bookmark in score.bookmarks)
          if ((bookmark.isItem || _query.isNotEmpty) &&
              bookmark.title.toLowerCase().contains(_query))
            (score, bookmark),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _unassigned
              ? 'Unassigned scores'
              : _collection == null
              ? 'Score library'
              : _excludeCollection
              ? 'Outside $_collection'
              : _collection!,
        ),
        actions: [
          IconButton(
            tooltip: 'Libraries',
            onPressed: _chooseCollection,
            icon: const Icon(Icons.folder_copy_outlined),
          ),
          IconButton(
            tooltip: 'Edit multiple scores',
            onPressed: widget.scores.isEmpty
                ? null
                : () => Navigator.pop(context, 'batch'),
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
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
                      labelText: 'Search library',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _browseBy,
                    items: [
                      for (final mode in ['Recent', 'Title', ..._fields.keys])
                        DropdownMenuItem(
                          value: mode,
                          child: Text('Browse by $mode'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _browseBy = value ?? 'Recent';
                      _category = null;
                    }),
                  ),
                  if (categories.isNotEmpty)
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _category ?? '',
                      items: [
                        for (final category in ['', ...categories])
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              category.isEmpty ? 'All values' : category,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => _category = value == '' ? null : value,
                      ),
                    ),
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
                    child:
                        visible.isEmpty &&
                            matchingBookmarks.isEmpty &&
                            matchingSets.isEmpty &&
                            actions.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'No imported scores yet.'
                                  : 'No matching scores.',
                            ),
                          )
                        : ListView.builder(
                            itemCount:
                                visible.length +
                                matchingBookmarks.length +
                                matchingSets.length +
                                actions.length,
                            itemBuilder: (context, index) {
                              if (index >= visible.length &&
                                  index <
                                      visible.length +
                                          matchingBookmarks.length) {
                                final (score, bookmark) =
                                    matchingBookmarks[index - visible.length];
                                return ListTile(
                                  leading: const Icon(Icons.bookmark_outline),
                                  title: Text(bookmark.title),
                                  subtitle: Text(
                                    '${score.title} · Page ${bookmark.page}',
                                  ),
                                  onTap: () => Navigator.pop(
                                    context,
                                    'bookmark:${score.id}:${bookmark.id}',
                                  ),
                                );
                              }
                              if (index >= visible.length)
                                index -= matchingBookmarks.length;
                              if (index >=
                                  visible.length + matchingSets.length) {
                                final action =
                                    actions[index -
                                        visible.length -
                                        matchingSets.length];
                                return ListTile(
                                  leading: const Icon(Icons.arrow_outward),
                                  title: Text(action.value),
                                  onTap: () =>
                                      Navigator.pop(context, action.key),
                                );
                              }
                              if (index >= visible.length) {
                                final setlist =
                                    matchingSets[index - visible.length];
                                return ListTile(
                                  leading: const Icon(Icons.queue_music),
                                  title: Text(setlist.name),
                                  subtitle: const Text('Setlist'),
                                  onTap: () => Navigator.pop(
                                    context,
                                    'set:${setlist.id}',
                                  ),
                                );
                              }
                              final score = visible[index];
                              return ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(score.title),
                                subtitle: Text('Resume at page ${score.page}'),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Options for ${score.title}',
                                  onSelected: (action) {
                                    if (action == 'libraries') {
                                      _assignCollections(score);
                                    } else {
                                      Navigator.pop(
                                        context,
                                        'edit:${score.id}',
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'details',
                                      child: Text('Score details'),
                                    ),
                                    PopupMenuItem(
                                      value: 'libraries',
                                      child: Text('Assign to libraries'),
                                    ),
                                  ],
                                ),
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
