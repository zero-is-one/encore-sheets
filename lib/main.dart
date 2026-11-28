import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'page_ink.dart';
import 'page_note_dialog.dart';
import 'drawing_settings.dart';
import 'drawing_settings_dialog.dart';
import 'page_crop.dart';
import 'page_crop_dialog.dart';
import 'ink_layers_dialog.dart';
import 'ink_layer_package.dart';
import 'pdf_assembly_screen.dart';
import 'pdf_export_screen.dart';
import 'pdf_rearrange.dart';
import 'pdf_rearrange_screen.dart';
import 'reader_input.dart';
import 'reader_shortcuts_dialog.dart';
import 'reader_preferences.dart';
import 'three_page_layout.dart';
import 'vertical_score_layout.dart';
import 'library_backup_screen.dart';
import 'library_sync.dart';
import 'assistant_connection.dart';
import 'assistant_connection_screen.dart';
import 'library_sync_screen.dart';
import 'webdav_library_sync.dart';
import 'bookmarks_screen.dart';
import 'jump_links_screen.dart';
import 'half_page_turn.dart';
import 'score_library.dart';
import 'score_action.dart';
import 'score_action_destination.dart';
import 'score_actions_screen.dart';
import 'score_audio.dart';
import 'score_audio_dialog.dart';
import 'practice_recordings.dart';
import 'practice_recordings_dialog.dart';
import 'metronome_dialog.dart';
import 'metadata_csv_screen.dart';
import 'cloud_files_screen.dart';
import 'embedded_pdf_info.dart';
import 'midi_devices_dialog.dart';
import 'turn_touch.dart';
import 'audio_page_cues.dart';
import 'midi_automation_dialog.dart';
import 'ensemble_dialog.dart';
import 'ensemble_session.dart';
import 'rehearsal_piano.dart';
import 'pdf_template.dart';
import 'text_score_pdf.dart';
import 'pdf_text_font.dart';
import 'practice_activity.dart';
import 'practice_dashboard.dart';
import 'practice_goals.dart';
import 'face_page_turn.dart';
import 'measure_clipboard.dart';
import 'settings_profiles.dart';
import 'metadata_symbols.dart';
import 'share_reader_link.dart';
import 'reader_appearance_options.dart';
import 'library_search_options.dart';
import 'library_score_preview.dart';
import 'program_duration.dart';
import 'local_maintenance.dart';
import 'launcher_icons.dart';
import 'reader_restrictions.dart';
import 'support_screen.dart';
import 'app_localization.dart';
import 'reader_deep_link.dart';
import 'score_clipboard.dart';
import 'rehearsal_metronome.dart';
import 'reference_tone.dart';
import 'reflow_screen.dart';
import 'reflow_zones.dart';
import 'tuner_dialog.dart';
import 'scan_cleanup_screen.dart';
import 'score_management_screen.dart';
import 'score_metadata_screen.dart';
import 'score_text_search_screen.dart';
import 'score_text_search.dart';
import 'setlists_screen.dart';
import 'text_annotation_dialog.dart';

enum _ReaderMenu { display, score, tools }

enum _AudioUtility { metronome, pitch, tuner }

enum _CornerMenu { scores, bookmarks, setlists, search, audio, tools }

enum _ToolbarShortcut {
  services('Services', Icons.cloud_outlined),
  annotations('Annotations', Icons.draw_outlined),
  display('Display options', Icons.dashboard_outlined),
  find('Find in score', Icons.find_in_page_outlined),
  metronome('Metronome', Icons.timer_outlined),
  piano('Piano', Icons.piano_outlined),
  note('Page note', Icons.sticky_note_2_outlined),
  hidden('Hidden', Icons.visibility_off_outlined);

  const _ToolbarShortcut(this.label, this.icon);
  final String label;
  final IconData icon;

  static _ToolbarShortcut read(Object? value, _ToolbarShortcut fallback) =>
      values.where((shortcut) => shortcut.name == value).firstOrNull ??
      fallback;
}

enum _ReaderDisplay {
  readerSettings,
  toolbarShortcuts,
  annotate,
  rearrangeScore,
  librarySync,
  importScore,
  migrateLibrary,
  scanScore,
  cloudServices,
  scoreTemplates,
  libraryBackup,
  nowPlaying,
  findInScore,
  pageNote,
  pageActions,
  scoreAudio,
  practiceRecordings,
  practiceActivity,
  restrictions,
  assistantConnections,
  support,
  language,
  profiles,
  metadataSymbols,
  themeOptions,
  maintenance,
  appIcon,
  metronome,
  tuner,
  piano,
  inputShortcuts,
  faceTurns,
  copyMeasure,
  pasteMeasure,
  midiDevices,
  midiAutomation,
  ensemble,
  scoreWindow,
  presentation,
  appearance,
  accessibility,
  reflow,
  panelOptions,
  embeddedPdf,
  fit,
  fittingMode,
  scrollMode,
  autoScroll,
  zoomIn,
  zoomOut,
  previousPage,
  previousScore,
  bookmarks,
  jumpLinks,
  halfTurns,
  halfSplit,
  halfIndicator,
  landscapeWidth,
  spreads,
  scoreTabs,
  exportPdf,
  crop,
  drawingSettings,
  shareScorePackage,
  shareScoreLink,
  performance,
  hideControls,
  cleanStartup,
  gestures,
  keepAwake,
  nextTitle,
}

void main() => runApp(const EncoreSheets());

class EncoreSheets extends StatefulWidget {
  const EncoreSheets({super.key});

  @override
  State<EncoreSheets> createState() => _EncoreSheetsState();
}

class _EncoreSheetsState extends State<EncoreSheets> {
  Locale? _locale;
  ReaderAppearanceOptions _appearance = const ReaderAppearanceOptions();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EncoreSheets',
    debugShowCheckedModeBanner: false,
    locale: _locale,
    supportedLocales: readerLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: _appearance.palette.light
          ? Brightness.light
          : Brightness.dark,
      colorScheme:
          (_appearance.palette.light
                  ? const ColorScheme.light()
                  : const ColorScheme.dark())
              .copyWith(
                primary: _appearance.palette.accent,
                onPrimary: _appearance.palette.light
                    ? Colors.white
                    : _appearance.backdrop,
                surface: _appearance.palette.bar,
                onSurface: _appearance.palette.text,
                onSurfaceVariant: _appearance.palette.text,
              ),
      iconTheme: IconThemeData(
        color: _appearance.palette.text,
        weight: _appearance.boldIcons ? 700 : 400,
      ),
      scaffoldBackgroundColor: _appearance.backdrop,
    ),
    home: Reader(
      onAppearance: (appearance) => setState(() => _appearance = appearance),
      onLanguage: (language) {
        final resolved = language == null ? null : Locale(language);
        if (_locale != resolved) setState(() => _locale = resolved);
      },
    ),
  );
}

class Reader extends StatefulWidget {
  const Reader({super.key, this.onLanguage, this.onAppearance});
  final ValueChanged<String?>? onLanguage;
  final ValueChanged<ReaderAppearanceOptions>? onAppearance;

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  PdfViewerController _viewer = PdfViewerController();
  late final _autoScrollTicker = Ticker(_tickAutoScroll);
  bool _autoScrollAdvancing = false;
  Duration _autoScrollLast = Duration.zero;
  Duration _autoScrollAtEnd = Duration.zero;
  final _ink = <int, PageInk>{};
  final _focus = FocusNode(debugLabel: 'Score reader');
  late final _library = ScoreLibrary(LibraryStorage.create());
  late Future<void> _libraryReady = _loadLibrary();
  bool _openingFirstScore = true;
  bool _appleScoreWindowsSupported = false;
  ScoreEntry? _entry;
  ScoreBookmark? _itemBookmark;
  XFile? _file;
  Uint8List? _bytes;
  int _revision = 0;
  int _page = 1;
  int _initialPage = 1;
  int? _previousPage;
  ({String id, int page})? _previousItem;
  int _pages = 0;
  double? _seek;
  bool _showControls = true;
  bool _markupPaletteAtTop = false;
  Map<String, dynamic> _libraryBrowseState = {};
  bool _inking = false;
  int? _annotationPage;
  bool? _fingerDrawingOverride;
  Timer? _recentStylus;
  bool get _allowFinger =>
      _fingerDrawingOverride ??
      (!_stylusDrawing && !(_recentStylus?.isActive ?? false));
  bool _picking = false;
  static const _dockWidth = 368.0;
  static const _dockMinimumWidth = 900.0;
  Widget? _readerDock;
  GlobalKey<NavigatorState>? _readerDockNavigator;
  VoidCallback? _completeReaderDock;
  ({int revision, int page, double center, double scale})? _dockVerticalAnchor;
  bool _saveWarning = false;
  bool _inkSaveWarning = false;
  bool _editingText = false;
  InkTool _tool = InkTool.pen;
  InkShape? _shape;
  InkShape? _favoriteShape;
  bool _showRuler = false;
  InkRulerGuide _ruler = (
    start: const Offset(.15, .45),
    end: const Offset(.85, .45),
  );
  bool _freeformSelection = false;
  List<Map<String, dynamic>> _inkClipboard = [];
  List<InkLayer> _inkLayers = [defaultInkLayer];
  String? _activeInkLayer = defaultInkLayer.id;
  String? _stamp;
  List<String> _personalStamps = [];
  List<String> _favoriteStamps = [];
  DrawingSettings _drawing = const DrawingSettings();
  bool _stylusDrawing = false;
  bool _lastReaderPointerStylus = false;
  final _edgeTaps = _EdgeTapTracker();
  bool _dispatchingEdgeLink = false;
  int _pdfLinkNavigations = 0;
  Setlist? _playing;
  ScoreAudioSession? _scoreAudio;
  late final _practice = PracticeActivity(
    _library,
    onSaved: _requestWidgetRefresh,
  );
  static const _faceChannel = MethodChannel('encoresheets/face');
  FacePageTurn? _faceTurns;
  Timer? _scoreExpiry;
  MeasureClip? _measureClipboard;
  bool _selectingPdf = false;
  bool _placingMeasure = false;
  bool _copyingMeasure = false;
  int? _pdfSelectionPage;
  List<Offset> _pdfSelection = [];
  _ToolbarShortcut _leftToolbarShortcut = _ToolbarShortcut.services;
  _ToolbarShortcut _rightToolbarShortcut = _ToolbarShortcut.annotations;
  final _cornerToolsMenuController = MenuController();
  _CornerMenu _lastLeftMenu = _CornerMenu.scores;
  _CornerMenu _lastRightMenu = _CornerMenu.tools;
  Map<String, String> _metadataSymbols = {};
  ReaderAppearanceOptions _appearance = const ReaderAppearanceOptions();

  Color get _stand => _appearance.backdrop;
  Color get _rail => _appearance.palette.bar;
  Color get _paper => _appearance.palette.text;
  Color get _brass => _appearance.palette.accent;
  bool _faceReverse = false;
  double _faceSensitivity = 23;
  FaceGestureMode _faceGestureMode = FaceGestureMode.headTurn;
  ReaderRestrictions? _restrictions;
  String? _language;
  late final Future<void> _startupPreferences;
  static const _linksChannel = MethodChannel('encoresheets/links');
  bool _linksWaiting = false;
  EnsembleSession? _ensemble;
  bool _leadingSpread = false;
  bool _followingSpread = false;
  bool _missingFacingPage = false;
  bool _presenting = false;
  int _presentationUpdate = 0;
  static const _presentationChannel = MethodChannel(
    'encoresheets/presentation',
  );
  AudioPageCueMode _audioCueMode = AudioPageCueMode.off;
  StreamSubscription<Duration>? _audioCuePlayback;
  String? _audioCueFile;
  List<AudioPageCue> _audioCues = [];
  AudioPageCue? _lastAudioCue;
  Future<void> _audioCueWrite = Future.value();
  RehearsalMetronome? _metronome;
  int _meterPageStart = 0;
  int? _meterPage;
  ReferenceTone? _referenceTone;
  RehearsalPiano? _piano;
  bool _midiPiano = false;
  Map<String, ReaderShortcut> _shortcuts = {};
  final _midiShortcuts = StreamController<String>.broadcast();
  TurnTouch? _turnTouch;
  StreamSubscription<MidiPacket>? _midiInput;
  late final _midi = MidiCommand(
    bleTransport: _supportsSharedImport ? UniversalBleMidiTransport() : null,
  );
  List<String> _libraryQueue = const [];
  int _setIndex = 0;
  bool _performance = false;
  bool _halfPreview = false;
  Duration? _lastHalfScroll;
  ReaderPreferences _preferences = const ReaderPreferences();
  List<String> _scoreTabIds = [];
  String? _selectedTabInstance;
  String? _lastOpenedScoreTab;
  final Map<String, int> _scoreTabPages = {};
  bool _savingTabs = false;
  static const _sharedImports = MethodChannel('encoresheets/import');
  static const _stylusChannel = MethodChannel('encoresheets/stylus');
  bool _sharedWaiting = false;
  late final AppLifecycleListener _lifecycle;
  final _syncEndpoint = AppleLibrarySync();
  WebDavLibrarySync? _webDavSync;
  late final _assistantConnection = AssistantConnection(_library);
  Timer? _assistantTimer;
  Timer? _syncTimer;
  Future<DateTime>? _syncRunning;
  DateTime? _lastSync;

  bool get _hasNextScore =>
      _playing != null && _setIndex + 1 < _playing!.scores.length;
  bool get _hasPreviousScore => _playing != null && _setIndex > 0;

  int get _firstPage =>
      (_itemBookmark?.page ?? 1).clamp(1, _pages > 0 ? _pages : 1);
  int get _lastPage => (_itemBookmark?.endPage ?? _pages).clamp(
    _firstPage,
    _pages > 0 ? _pages : 1,
  );

  String? get _nextTitle {
    if (!_preferences.showNextTitle || !_hasNextScore || _pages == 0)
      return null;
    final next = _library.lookupSelection(_playing!.scores[_setIndex + 1]);
    return next?.$2?.title ?? next?.$1.title;
  }

  String get _title =>
      _itemBookmark?.title ??
      _entry?.title ??
      (_openingFirstScore ? 'Opening library…' : 'No score open');
  bool get _supportsSharedImport =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _isAppleMobile =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _supportsScoreWindows =>
      _supportsSharedImport && (!_isAppleMobile || _appleScoreWindowsSupported);
  bool get _autoStylus =>
      _drawing.autoEnter &&
      !_performance &&
      !_picking &&
      !_restricted(RestrictedTool.markup);

  bool _restricted(RestrictedTool tool) =>
      _restrictions?.tools.contains(tool) ?? false;

  bool _readerActionAllowed(_ReaderDisplay? action) => switch (action) {
    _ReaderDisplay.annotate ||
    _ReaderDisplay.rearrangeScore ||
    _ReaderDisplay.pageNote ||
    _ReaderDisplay.pageActions ||
    _ReaderDisplay.jumpLinks ||
    _ReaderDisplay.crop ||
    _ReaderDisplay.drawingSettings ||
    _ReaderDisplay.pasteMeasure ||
    _ReaderDisplay.halfSplit => !_restricted(RestrictedTool.markup),
    _ReaderDisplay.copyMeasure =>
      !_restricted(RestrictedTool.markup) && _entry?.validUntil == null,
    _ReaderDisplay.exportPdf =>
      !_restricted(RestrictedTool.transfers) && _entry?.validUntil == null,
    _ReaderDisplay.shareScorePackage ||
    _ReaderDisplay.shareScoreLink ||
    _ReaderDisplay.practiceRecordings ||
    _ReaderDisplay.scoreAudio => !_restricted(RestrictedTool.transfers),
    _ReaderDisplay.ensemble ||
    _ReaderDisplay.midiAutomation ||
    _ReaderDisplay.midiDevices ||
    _ReaderDisplay.inputShortcuts => !_restricted(RestrictedTool.connections),
    _ReaderDisplay.assistantConnections =>
      !kIsWeb && !_restricted(RestrictedTool.connections),
    _ReaderDisplay.faceTurns => !_restricted(RestrictedTool.connections),
    _ReaderDisplay.presentation || _ReaderDisplay.scoreWindow =>
      !_restricted(RestrictedTool.connections) && _entry?.validUntil == null,
    _ => true,
  };

  @override
  void initState() {
    super.initState();
    _startupPreferences = _restorePreferences(startup: true);
    unawaited(_openFirstScore());
    if (!kIsWeb) {
      _assistantTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => unawaited(_syncAssistantIfReady()),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_syncAssistantIfReady()),
      );
      _syncTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => _syncIfReady(),
      );
    }
    if (_isAppleMobile) {
      unawaited(_checkScoreWindowSupport());
      _stylusChannel.setMethodCallHandler((call) async {
        if (call.method == 'switchTool') _switchStylusTool();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncIfReady());
    }
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!kIsWeb) unawaited(_syncAssistantIfReady());
        _checkScoreExpiry();
        _requestWidgetRefresh();
        _focusPractice();
        if (_supportsSharedImport) _requestScoreLinks();
        if (_performance || _preferences.keepAwake) _keepScreenAwake(true);
        if (_isAppleMobile || _webDavSync != null) _syncIfReady();
      },
      onHide: () {
        _stopAutoScroll();
        unawaited(_practice.suspend().catchError((Object _) {}));
        _stopFaceTurns();
      },
    );
    if (_supportsSharedImport) {
      _faceChannel.setMethodCallHandler((call) async {
        final detector = _faceTurns;
        if (call.method != 'sample' || detector == null || !mounted) return;
        if (_picking ||
            _inking ||
            _restricted(RestrictedTool.connections) ||
            ModalRoute.isCurrentOf(context) == false) {
          detector.update(null);
          return;
        }
        final step = detector.update(detector.mode.readSample(call.arguments));
        if (step != 0) _turn(_faceReverse ? -step : step);
      });
      _sharedImports.setMethodCallHandler((call) async {
        if (call.method == 'available') _requestSharedImport();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestSharedImport();
          _requestScoreLinks();
        }
      });
      _linksChannel.setMethodCallHandler((call) async {
        if (call.method == 'available') _requestScoreLinks();
      });
    }
  }

  Future<void> _loadLibrary() async {
    await _library.load();
    try {
      await _library.seedSampleScore(() async {
        final pdf = await rootBundle.load('assets/first_light.pdf');
        return XFile.fromData(
          pdf.buffer.asUint8List(pdf.offsetInBytes, pdf.lengthInBytes),
          name: 'First Light.pdf',
          mimeType: 'application/pdf',
        );
      });
    } catch (error) {
      debugPrint('Could not add the bundled score: $error');
    }
  }

  Future<void> _openFirstScore() async {
    try {
      await _libraryReady;
      await _startupPreferences;
      final scores = _library.recent;
      final score =
          scores.where((score) => score.isSample).firstOrNull ??
          scores.firstOrNull;
      if (mounted && _revision == 0 && score != null) {
        await _openLibraryScore(score, onlyIfUnchanged: true);
      }
    } catch (error) {
      debugPrint('Could not open the initial score: $error');
    } finally {
      if (mounted) setState(() => _openingFirstScore = false);
    }
  }

  Future<void> _restorePreferences({bool startup = false}) async {
    try {
      final data = await _library.storage.readPreferences();
      if (mounted) {
        final indexedTabs = data['scoreTabs'];
        final ids = indexedTabs is List
            ? indexedTabs.whereType<String>().toSet().toList()
            : <String>[];
        if (ids.isNotEmpty) await _libraryReady;
        if (!mounted) return;
        setState(() {
          _leftToolbarShortcut = _ToolbarShortcut.read(
            data['leftToolbarShortcut'],
            _ToolbarShortcut.services,
          );
          _rightToolbarShortcut = _ToolbarShortcut.read(
            data['rightToolbarShortcut'],
            _ToolbarShortcut.annotations,
          );
          _preferences = ReaderPreferences.fromJson(data);
          _markupPaletteAtTop = data['markupPaletteAtTop'] == true;
          _favoriteStamps = switch (data['favoriteStamps']) {
            final List values =>
              values
                  .whereType<String>()
                  .where((stamp) => stamp.isNotEmpty && stamp.length <= 80)
                  .toSet()
                  .take(4)
                  .toList(),
            _ => [],
          };
          _favoriteShape = InkShape.values
              .where((shape) => shape.name == data['favoriteInkShape'])
              .firstOrNull;
          _libraryBrowseState =
              (data['libraryBrowseState'] is Map<String, dynamic>)
              ? data['libraryBrowseState'] as Map<String, dynamic>
              : {};
          if (startup &&
              _preferences.startWithControlsHidden &&
              [
                _preferences.left,
                _preferences.center,
                _preferences.right,
              ].contains(ReaderTapAction.controls)) {
            _showControls = false;
          }
          _practice.enabled = data['practiceTracking'] == true;
          _metadataSymbols = readMetadataSymbols(data['metadataSymbols']);
          _appearance = ReaderAppearanceOptions.fromJson(
            data['appearanceOptions'],
          );
          final language = data['readerLanguage'];
          _language =
              language is String && readerLanguageNames.containsKey(language)
              ? language
              : null;
          _restrictions = ReaderRestrictions.fromJson(
            data['readerRestrictions'],
          );
          _midiPiano = data['midiPiano'] == true;
          if (data['readerShortcuts'] case final Map saved) {
            _shortcuts = {
              for (final entry in saved.entries)
                if (entry.key is String)
                  if (ReaderShortcut.values
                          .where((item) => item.name == entry.value)
                          .firstOrNull
                      case final shortcut?)
                    entry.key as String: shortcut,
            };
          }
          _drawing = DrawingSettings.fromJson(data['drawingSettings']);
          _scoreTabIds = ids.where((id) => _lookupTab(id) != null).toList();
          _scoreTabPages.clear();
          if (data['scoreTabPages'] case final Map pages) {
            for (final id in _scoreTabIds) {
              if (pages[id] case final int page when page > 0) {
                _scoreTabPages[id] = page;
              }
            }
          }
          if (data['personalStamps'] case final List stamps) {
            _personalStamps = stamps
                .whereType<String>()
                .where((stamp) => stamp.isNotEmpty)
                .toList();
          }
        });
        _listenToMidi();
        widget.onLanguage?.call(_language);
        widget.onAppearance?.call(_appearance);
        _applyStatusBar();
        _focusPractice();
        _requestWidgetRefresh();
        if (_preferences.keepAwake) _keepScreenAwake(true);
        if (data['activeScoreTab'] case final String id
            when startup &&
                _scoreTabIds.contains(id) &&
                _entry == null &&
                !_picking) {
          await _switchScoreTab(id);
        }
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
        _turn(-1);
      case ReaderTapAction.next:
        _turn(1);
      case ReaderTapAction.controls:
        setState(() => _showControls = !_showControls);
      case ReaderTapAction.markup:
        _toggleInk();
      case ReaderTapAction.none:
        break;
    }
  }

  bool _handleCornerShortcut(int edge, Offset position, Size viewport) {
    if (!_preferences.cornerShortcuts ||
        _showControls ||
        _performance ||
        _picking ||
        position.dy > math.min(64, viewport.height * .12))
      return false;
    final cornerWidth = math.min(64, viewport.width * .16);
    if (edge < 0 && position.dx <= cornerWidth) {
      final menu =
          _lastLeftMenu == _CornerMenu.bookmarks &&
              (_entry == null || _pages == 0)
          ? _CornerMenu.scores
          : _lastLeftMenu;
      _openCornerMenu(menu);
      return true;
    }
    if (edge > 0 && position.dx >= viewport.width - cornerWidth) {
      final menu =
          _lastRightMenu == _CornerMenu.audio && !ScoreAudioSession.supported
          ? _CornerMenu.tools
          : _lastRightMenu;
      _openCornerMenu(menu);
      return true;
    }
    return false;
  }

  void _openCornerMenu(_CornerMenu menu) {
    switch (menu) {
      case _CornerMenu.scores:
        _lastLeftMenu = menu;
        unawaited(_showLibrary());
      case _CornerMenu.bookmarks:
        _lastLeftMenu = menu;
        unawaited(_showBookmarks());
      case _CornerMenu.setlists:
        _lastLeftMenu = menu;
        unawaited(_showLibrary(setlists: true));
      case _CornerMenu.search:
        _lastRightMenu = menu;
        unawaited(_showLibrary(focusSearch: true));
      case _CornerMenu.audio:
        _lastRightMenu = menu;
        unawaited(_showMetronome(showUtilities: true));
      case _CornerMenu.tools:
        _lastRightMenu = menu;
        _cornerToolsMenuController.open();
    }
  }

  Future<void> _configureGestures() async {
    var left = _preferences.left;
    var center = _preferences.center;
    var right = _preferences.right;
    var cornerShortcuts = _preferences.cornerShortcuts;
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
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Expanded(child: Center(child: Text('Left'))),
                      Expanded(child: Center(child: Text('Center'))),
                      Expanded(child: Center(child: Text('Right'))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                choice('Left', left, (value) => left = value),
                choice('Center', center, (value) => center = value),
                choice('Right', right, (value) => right = value),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Corner shortcuts'),
                  subtitle: const Text(
                    'With controls hidden, tap a top corner to reopen the '
                    'last menu you used on that side.',
                  ),
                  value: cornerShortcuts,
                  onChanged: (value) => update(() => cornerShortcuts = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _preferences.copyWith(
                    left: ReaderTapAction.previous,
                    center: ReaderTapAction.controls,
                    right: ReaderTapAction.next,
                    cornerShortcuts: false,
                  ),
                ),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _preferences.copyWith(
                    left: left,
                    center: center,
                    right: right,
                    cornerShortcuts: cornerShortcuts,
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
        final enabledHalfTurns =
            configured.halfPageTurns && !_preferences.halfPageTurns;
        final fittingChanged = configured.pageFit != _preferences.pageFit;
        final previousMode = _scrollMode;
        setState(() {
          if (!configured.halfPageTurns) _halfPreview = false;
          _preferences = configured;
          if (previousMode != _scrollMode) _resetScoreLayout();
        });
        if (enabledHalfTurns) _fit();
        if (fittingChanged) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fit();
          });
        }
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
    _completeReaderDock?.call();
    _autoScrollTicker.dispose();
    _scoreExpiry?.cancel();
    _recentStylus?.cancel();
    if (_supportsSharedImport) {
      _stopFaceTurns(rebuild: false);
      _faceChannel.setMethodCallHandler(null);
    }
    unawaited(_midiInput?.cancel());
    unawaited(_turnTouch?.dispose().catchError((Object _) {}));
    unawaited(_midiShortcuts.close());
    unawaited(_referenceTone?.dispose());
    unawaited(_piano?.dispose().catchError((Object _) {}));
    _metronome?.dispose();
    unawaited(_scoreAudio?.dispose());
    unawaited(_practice.suspend().catchError((Object _) {}));
    unawaited(_ensemble?.close());
    if (_presenting) {
      unawaited(
        _presentationChannel
            .invokeMethod<void>('hide')
            .catchError((Object _) {}),
      );
    }
    unawaited(_audioCuePlayback?.cancel());
    _syncTimer?.cancel();
    if (!kIsWeb) {
      _assistantTimer?.cancel();
      _assistantConnection.close();
    }
    if (_isAppleMobile) _stylusChannel.setMethodCallHandler(null);
    _webDavSync?.close();
    if (_supportsSharedImport) {
      _sharedImports.setMethodCallHandler(null);
      _linksChannel.setMethodCallHandler(null);
    }
    _lifecycle.dispose();
    if (_performance || _preferences.keepAwake) _keepScreenAwake(false);
    _focus.dispose();
    for (final ink in _ink.values) {
      ink.dispose();
    }
    super.dispose();
  }

  void _stopFaceTurns({bool rebuild = true}) {
    if (_faceTurns == null) return;
    if (rebuild && mounted) {
      setState(() => _faceTurns = null);
    } else {
      _faceTurns = null;
    }
    unawaited(
      _faceChannel.invokeMethod<void>('stop').catchError((Object _) {}),
    );
  }

  bool get _pdfSelectionAvailable =>
      _pages > 0 &&
      _entry?.validUntil == null &&
      !_restricted(RestrictedTool.markup);

  Rect? get _pdfSelectionBounds {
    if (_pdfSelection.length < (_freeformSelection ? 3 : 2)) return null;
    var bounds = Rect.fromPoints(_pdfSelection.first, _pdfSelection.last);
    for (final point in _pdfSelection) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    return bounds.width >= .006 && bounds.height >= .006 ? bounds : null;
  }

  void _selectPdf({bool paste = false}) {
    if (_picking || !_viewer.isReady || _restricted(RestrictedTool.markup)) {
      return;
    }
    if (paste
        ? _measureClipboard == null || _activeInkLayer == null
        : !_pdfSelectionAvailable) {
      return;
    }
    if (!_inking) _toggleInk();
    setState(() {
      _tool = InkTool.selection;
      _stamp = null;
      _shape = null;
      _selectingPdf = true;
      _placingMeasure = paste;
      _pdfSelection = [];
      _pdfSelectionPage = null;
    });
  }

  Future<void> _copyPdfSelection({required bool cut}) async {
    final number = _pdfSelectionPage;
    final area = _pdfSelectionBounds;
    if (!_pdfSelectionAvailable ||
        !_viewer.isReady ||
        _copyingMeasure ||
        number == null ||
        area == null ||
        cut && _activeInkLayer == null) {
      return;
    }
    final revision = _revision;
    final page = _viewer.document.pages[number - 1];
    final selection = _pdfSelection;
    final layer = _activeInkLayer;
    final outline = _freeformSelection ? selection : const <Offset>[];
    bool stillSelected() =>
        mounted &&
        revision == _revision &&
        _inking &&
        _pdfSelectionAvailable &&
        _tool == InkTool.selection &&
        _selectingPdf &&
        identical(selection, _pdfSelection) &&
        (!cut || layer == _activeInkLayer);
    setState(() => _copyingMeasure = true);
    try {
      final clip = await copyMeasure(page, area, outline: outline);
      if (!stillSelected()) return;
      final cover = cut
          ? await copyMeasure(page, area, outline: outline, cover: true)
          : null;
      if (!stillSelected()) return;
      if (cover != null) {
        _ink
            .putIfAbsent(number, _newPageInk)
            .pasteRaster(cover.png, area, select: false);
      }
      setState(() {
        _measureClipboard = clip;
        if (cut) _annotationPage = number;
        _pdfSelection = [];
        _pdfSelectionPage = null;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy the selected music.')),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingMeasure = false);
    }
  }

  void _placeMeasure(PdfPage page, Offset point) {
    final clip = _measureClipboard;
    if (_restricted(RestrictedTool.markup) ||
        _activeInkLayer == null ||
        clip == null) {
      return;
    }
    final number = page.pageNumber;
    _ink
        .putIfAbsent(number, _newPageInk)
        .pasteRaster(clip.png, measurePlacement(page, clip, point));
    setState(() {
      _annotationPage = number;
      _placingMeasure = false;
      _selectingPdf = false;
    });
  }

  Widget _pdfSelectionSurface(PdfPage page) => LayoutBuilder(
    builder: (_, limits) {
      final size = limits.biggest;
      Offset normalized(Offset local) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );
      final number = page.pageNumber;
      final outline = number == _pdfSelectionPage
          ? _pdfSelection
          : const <Offset>[];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _copyingMeasure
            ? null
            : (event) {
                if (_placingMeasure) {
                  _placeMeasure(page, normalized(event.localPosition));
                } else {
                  setState(() {
                    _pdfSelection = [];
                    _pdfSelectionPage = null;
                  });
                }
              },
        onPanDown: _placingMeasure || _copyingMeasure
            ? null
            : (event) {
                setState(() {
                  _pdfSelectionPage = number;
                  _pdfSelection = [normalized(event.localPosition)];
                });
              },
        onPanUpdate: _placingMeasure || _copyingMeasure
            ? null
            : (event) {
                if (number != _pdfSelectionPage || _pdfSelection.isEmpty)
                  return;
                final point = normalized(event.localPosition);
                setState(() {
                  if (_freeformSelection) {
                    _pdfSelection = [..._pdfSelection, point];
                  } else {
                    _pdfSelection = [_pdfSelection.first, point];
                  }
                });
              },
        onPanCancel: () {
          if (number != _pdfSelectionPage || _pdfSelection.length > 1) return;
          setState(() {
            _pdfSelection = [];
            _pdfSelectionPage = null;
          });
        },
        child: CustomPaint(
          painter: PdfSelectionOutline(outline, freeform: _freeformSelection),
          child: const SizedBox.expand(),
        ),
      );
    },
  );

  bool _faceSetupComplete = false;

  Future<void> _configureFaceTurns({bool configure = false}) async {
    if (_faceTurns != null && !configure) {
      _stopFaceTurns();
      return;
    }
    var sense = _faceSensitivity;
    var reverse = _faceReverse;
    var mode = _faceGestureMode;
    if (_faceSetupComplete && !configure) {
      await _startFaceTurns(mode, sense, reverse);
      return;
    }
    final enabled = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Face gestures'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FaceGestureMode>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Gesture'),
                items: [
                  for (final gesture in FaceGestureMode.values)
                    DropdownMenuItem(
                      value: gesture,
                      child: Text(gesture.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) refresh(() => mode = value);
                },
              ),
              const SizedBox(height: 12),
              Text(mode.instructions),
              const Text('Camera images stay on this device.'),
              const SizedBox(height: 12),
              const Text('Gesture threshold'),
              Slider(
                value: sense,
                min: 15,
                max: 35,
                divisions: 20,
                label: mode == FaceGestureMode.headTurn
                    ? '${sense.round()}°'
                    : '${((sense - 15) * 5).round()}%',
                onChanged: (value) => refresh(() => sense = value),
              ),
              SwitchListTile(
                title: Text(
                  mode == FaceGestureMode.mouth
                      ? 'Turn to the previous page'
                      : 'Reverse directions',
                ),
                value: reverse,
                onChanged: (value) => refresh(() => reverse = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Use front camera'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || enabled != true) return;
    _faceSetupComplete = true;
    if (_faceTurns != null) _stopFaceTurns();
    await _startFaceTurns(mode, sense, reverse);
  }

  Future<void> _startFaceTurns(
    FaceGestureMode mode,
    double sense,
    bool reverse,
  ) async {
    final threshold = switch (mode) {
      FaceGestureMode.headTurn => sense,
      FaceGestureMode.wink => .40 + (sense - 15) * .015,
      FaceGestureMode.mouth => .07 + (sense - 15) * .005,
    };
    final detector = FacePageTurn(threshold: threshold, mode: mode);
    setState(() {
      _faceSensitivity = sense;
      _faceGestureMode = mode;
      _faceReverse = reverse;
      _faceTurns = detector;
    });
    try {
      await _faceChannel.invokeMethod<void>('start', mode.name);
    } catch (_) {
      if (!mounted || _faceTurns != detector) return;
      _stopFaceTurns();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start the front camera. Check camera permissions.',
          ),
        ),
      );
    }
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
      await _startupPreferences;
      if (_restricted(RestrictedTool.transfers) || !mounted) return;
      await _libraryReady;
      final files = paths.map(XFile.new).toList();
      await _importScores([
        for (final file in files)
          if (file.name.toLowerCase().endsWith('.pdf')) file,
      ]);
      final audio = files
          .where(
            (file) => const {
              'mp3',
              'm4a',
              'aac',
              'wav',
              'flac',
              'ogg',
              'aif',
              'aiff',
            }.contains(file.name.split('.').last.toLowerCase()),
          )
          .firstOrNull;
      if (audio != null && mounted) await _linkDroppedAudio(audio);
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

  Future<void> _linkDroppedAudio(XFile file) async {
    final score = _entry;
    if (score == null || !ScoreAudioSession.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a score before dropping an audio track.'),
        ),
      );
      return;
    }
    final selection = _itemBookmark?.selectionId(score.id) ?? score.id;
    final audio = _scoreAudio ??= ScoreAudioSession(_library);
    final track = await audio.track(selection);
    if (!mounted) return;
    if (track != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Replace linked audio?'),
          content: Text('Link ${file.name} in place of ${track.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    await audio.attach(selection, file);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Linked ${file.name} to $_title.')),
      );
  }

  void _finishPicking() {
    if (!mounted) return;
    setState(() => _picking = false);
    _focus.requestFocus();
    if (_sharedWaiting) _drainSharedImports();
    if (_linksWaiting) _drainScoreLinks();
  }

  void _requestScoreLinks() {
    _linksWaiting = true;
    unawaited(_drainScoreLinks());
  }

  Future<void> _drainScoreLinks() async {
    if (!mounted || _picking || !_linksWaiting) return;
    _linksWaiting = false;
    setState(() => _picking = true);
    var showLibrary = false;
    var showPractice = false;
    try {
      final received =
          await _linksChannel.invokeListMethod<String>('take') ?? [];
      if (received.isEmpty || !mounted) return;
      await _startupPreferences;
      if (!mounted || _restricted(RestrictedTool.connections)) return;
      final link = received.reversed
          .map(parseReaderLink)
          .whereType<ReaderDeepLink>()
          .firstOrNull;
      if (link == null) return;
      showLibrary = link.target == ReaderLinkTarget.library;
      showPractice = link.target == ReaderLinkTarget.practice;
      if (showLibrary || showPractice) return;
      await _libraryReady;
      if (!mounted) return;
      if (link.target == ReaderLinkTarget.cloud) {
        if (_restricted(RestrictedTool.transfers)) return;
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => CloudFilesScreen(library: _library),
        );
        if (mounted && score != null) await _openLibraryScore(score);
        return;
      }
      final name = link.name?.toLowerCase();
      if (link.target == ReaderLinkTarget.setlist) {
        final matches = _library.setlists
            .where(
              (list) => link.id == null
                  ? list.name.toLowerCase() == name
                  : list.id == link.id,
            )
            .take(2)
            .toList();
        if (matches.length != 1 || matches.single.scores.isEmpty) {
          throw StateError('The linked setlist is unavailable or ambiguous.');
        }
        await _playScore(matches.single, 0);
        return;
      }
      if (link.target == ReaderLinkTarget.score) {
        final matches = _library.recent
            .where(
              (score) => link.id == null
                  ? score.title.toLowerCase() == name
                  : score.id == link.id,
            )
            .take(2)
            .toList();
        if (matches.length != 1) {
          throw StateError('The linked score is unavailable or ambiguous.');
        }
        await _openLibraryScore(matches.single, startPage: link.page);
        return;
      }
      final matches = [
        for (final score in _library.recent)
          for (final bookmark in score.bookmarks)
            if (link.id == null
                ? bookmark.title.toLowerCase() == name
                : bookmark.selectionId(score.id) == link.id)
              (score, bookmark),
      ];
      if (matches.length != 1) {
        throw StateError('The linked bookmark is unavailable or ambiguous.');
      }
      final (score, bookmark) = matches.single;
      await _openLibraryScore(
        score,
        startPage: bookmark.page,
        item: bookmark.isItem ? bookmark : null,
      );
    } on MissingPluginException {
      return;
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find a unique library item for this link.',
            ),
          ),
        );
    } finally {
      _finishPicking();
      if (showLibrary && mounted) unawaited(_showLibrary());
      if (showPractice && mounted) unawaited(_showPracticeActivity());
    }
  }

  Future<void> _open({bool migration = false}) async {
    if (_picking || _restricted(RestrictedTool.transfers)) return;
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
      if (migration && !await _confirmMigration(files)) return;
      await _libraryReady;
      if (mounted) await _importScores(files, migration: migration);
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

  Future<bool> _confirmMigration(List<XFile> files) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(
            'Import ${files.length} PDF${files.length == 1 ? '' : 's'}',
          ),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'EncoreSheets copies your PDFs. Flattened markings stay visible on the page. '
                  'Editable ink layers, score-reader bookmarks, and setlist order must be recreated. '
                  'Keep any editable exports from your original app.',
                ),
                const SizedBox(height: 12),
                for (final file in files)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(file.name),
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
              child: const Text('Import PDFs'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _importScores(
    List<XFile> files, {
    bool migration = false,
  }) async {
    (ScoreEntry, XFile)? first;
    final failed = <String>[];
    for (final file in files) {
      try {
        final imported = await _library.import(file);
        first ??= imported;
      } catch (_) {
        failed.add(file.name);
      }
    }
    if (first case (final entry, final local)) {
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      if (!mounted) return;
      _playing = null;
      _load(entry, local, bytes);
      _remember(entry.id, _page, opened: true);
    }
    if (migration && failed.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(
            'Imported ${files.length - failed.length} of ${files.length} PDFs',
          ),
          scrollable: true,
          content: Text('Could not import:\n${failed.join('\n')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else if (failed.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not import ${failed.length} of ${files.length} selected PDFs.',
          ),
        ),
      );
    }
  }

  XFile _generatedScore(Uint8List bytes, String title) {
    final stem = title.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_').trim();
    final filename = '${stem.isEmpty ? 'Untitled score' : stem}.pdf';
    return XFile.fromData(
      bytes,
      name: filename,
      path: filename,
      mimeType: 'application/pdf',
    );
  }

  Future<void> _importTextScores() async {
    final documents = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Text and Word documents',
          extensions: ['txt', 'rtf', 'doc', 'docx'],
          mimeTypes: [
            'text/plain',
            'application/rtf',
            'text/rtf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ],
          uniformTypeIdentifiers: [
            'public.plain-text',
            'public.rtf',
            'com.microsoft.word.doc',
            'org.openxmlformats.wordprocessingml.document',
          ],
        ),
      ],
    );
    final converted = <XFile>[];
    final failed = <String>[];
    if (documents.isEmpty) return;
    final fontData = await loadPdfTextFont();
    for (final file in documents) {
      if (!mounted) return;
      try {
        if (await file.length() > 8 * 1024 * 1024) {
          throw const FormatException('Choose a document under 8 MB.');
        }
        final name = file.name;
        final separator = name.lastIndexOf('.');
        if (separator <= 0)
          throw const FormatException('File type is missing.');
        final title = name.substring(0, separator);
        final extension = name.substring(separator + 1).toLowerCase();
        final source = await file.readAsBytes();
        final result = await compute(
          (Uint8List data) => convertTextScore(
            data,
            extension: extension,
            title: title,
            fontData: fontData,
          ),
          source,
        );
        converted.add(_generatedScore(result, title));
      } catch (error) {
        failed.add(
          error is FormatException
              ? '${file.name}: ${error.message}'
              : '${file.name} could not be converted.',
        );
      }
    }
    if (!mounted) return;
    await _importScores(converted);
    if (mounted && failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.length == 1
                ? failed.single
                : 'Could not convert ${failed.length} documents. ${failed.first}',
          ),
        ),
      );
    }
  }

  bool get _wideReaderDock =>
      _readerDock != null &&
      MediaQuery.sizeOf(context).width >= _dockMinimumWidth;

  bool get _pageNavigationBlocked => _picking && !_wideReaderDock;

  void _backFromReaderDock() {
    unawaited(_readerDockNavigator?.currentState?.maybePop());
  }

  void _captureDockVerticalAnchor() {
    if (!_verticalScrolling || !_viewer.isReady || _pages == 0) return;
    final pages = _viewer.layout.pageLayouts;
    final visible = _viewer.visibleRect;
    final pageNumber = verticalPageAt(
      visible,
      pages,
      first: _firstPage,
      last: _lastPage,
    );
    final page = pages[pageNumber - 1];
    if (page.isEmpty) return;
    _dockVerticalAnchor = (
      revision: _revision,
      page: pageNumber,
      center: ((visible.center.dy - page.top) / page.height).clamp(0, 1),
      scale: _viewer.currentZoom / _viewer.coverScale,
    );
  }

  Future<T?> _openReaderDock<T>(WidgetBuilder builder) async {
    final navigator = GlobalKey<NavigatorState>();
    final result = Completer<T?>();
    final route = MaterialPageRoute<T>(builder: builder);
    void complete(T? value) {
      if (!result.isCompleted) result.complete(value);
    }

    unawaited(route.popped.then(complete));
    _captureDockVerticalAnchor();
    setState(() {
      _readerDockNavigator = navigator;
      _completeReaderDock = () => complete(null);
      _readerDock = Navigator(
        key: navigator,
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
          route,
        ],
      );
    });
    try {
      return await result.future;
    } finally {
      if (mounted) {
        if (_wideReaderDock) _captureDockVerticalAnchor();
        setState(() {
          _readerDock = null;
          _readerDockNavigator = null;
          _completeReaderDock = null;
        });
      }
    }
  }

  Future<T?> _openReaderPanel<T>(
    WidgetBuilder builder, {
    bool dockable = false,
  }) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 720 || _preferences.fullScreenPanels) {
      return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
    }
    if (dockable &&
        _preferences.dockPanels &&
        _readerDock == null &&
        width >= _dockMinimumWidth) {
      return _openReaderDock<T>(builder);
    }
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: dockable ? Colors.black26 : Colors.black38,
      pageBuilder: (context, _, _) => SafeArea(
        child: Padding(
          padding: dockable
              ? const EdgeInsetsDirectional.fromSTEB(12, 54, 12, 12)
              : EdgeInsets.zero,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: _dockWidth,
              height: double.infinity,
              child: Material(
                elevation: 12,
                clipBehavior: Clip.antiAlias,
                borderRadius: dockable
                    ? BorderRadius.circular(12)
                    : const BorderRadiusDirectional.only(
                        topEnd: Radius.circular(16),
                        bottomEnd: Radius.circular(16),
                      ),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _rememberLibraryBrowse(Map<String, dynamic> state) {
    if (mapEquals(_libraryBrowseState, state)) return;
    _libraryBrowseState = state;
    unawaited(
      _library
          .updatePreferences({'libraryBrowseState': state})
          .catchError((Object _) {}),
    );
  }

  Future<void> _showLibrary({
    bool setlists = false,
    bool focusSearch = false,
    String? entryAction,
    String? revealScoreId,
  }) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      await _library.flush();
      if (!mounted) return;
      var selectedQueue = const <String>[];
      final result =
          entryAction ??
          (setlists
              ? 'setlists'
              : await _openReaderPanel<String>(
                  (_) => _LibraryScreen(
                    library: _library,
                    scores: _library.recent,
                    setlists: _library.setlists,
                    persistent: _library.storage.persistent,
                    canScan: _supportsSharedImport,
                    canSync: _library.storage.persistent,
                    transferRestricted: _restricted(RestrictedTool.transfers),
                    connectionsRestricted: _restricted(
                      RestrictedTool.connections,
                    ),
                    onScoreQueue: (ids) => selectedQueue = ids,
                    canOpenTabs: _appearance.showTabs,
                    onPinScore: (id) => _updateScoreTabs([
                      ..._scoreTabIds.where((value) => value != id),
                      id,
                    ]),
                    compact:
                        _preferences.compactLibrary ||
                        !_appearance.showMetadata,
                    metadataIconKeys: _metadataSymbols,
                    focusSearch: focusSearch,
                    revealScoreId: revealScoreId,
                    canSearchScore: _pages > 0 && _viewer.isReady,
                    browseState: _libraryBrowseState,
                    onBrowseState: _rememberLibraryBrowse,
                  ),
                  dockable: !focusSearch,
                ));
      if (!mounted) return;
      if (_entry case final current?) {
        if (_library.lookup(current.id) == null) {
          _playing = null;
          _load(null, null, null);
        }
      }
      if (result == null) return;
      if (_restricted(RestrictedTool.transfers) &&
          (const {
                'import',
                'import-images',
                'create-template',
                'import-text',
                'scan',
                'backup',
                'cloud-files',
                'metadata-csv',
                'import-package',
                'combine',
              }.contains(result) ||
              result.startsWith('extract:')))
        return;
      if (_restricted(RestrictedTool.connections) &&
          const {'sync', 'cloud-files', 'ai-connections'}.contains(result))
        return;
      if (result == 'find-in-current-score') {
        setState(() => _picking = false);
        await _findInScore();
        return;
      }
      if (result == 'ai-connections') {
        await _openReaderPanel<void>(
          (_) => AssistantConnectionScreen(connection: _assistantConnection),
        );
        return;
      }
      if (result == 'combine' || result.startsWith('extract:')) {
        final source = result == 'combine'
            ? null
            : _library.lookup(result.substring('extract:'.length));
        if (source?.validUntil != null) return;
        if (result != 'combine' && source == null) return;
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => PdfAssemblyScreen(library: _library, source: source),
        );
        if (score != null && mounted) await _openLibraryScore(score);
        return;
      }
      if (result == 'batch') {
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => ScoreManagementScreen(library: _library),
        );
        if (!mounted) return;
        if (_entry case final current?) {
          if (_library.lookup(current.id) case final refreshed?) {
            setState(() => _entry = refreshed);
          } else {
            _playing = null;
            _load(null, null, null);
          }
        }
        if (score != null) await _openLibraryScore(score);
        return;
      }
      if (result.startsWith('edit:')) {
        final score = _library.lookup(result.substring(5));
        if (score != null) await _editScore(score);
        return;
      }
      if (result.startsWith('clone:')) {
        final score = await _library.duplicateScore(result.substring(6));
        if (mounted) await _openLibraryScore(score);
        return;
      }
      if (result.startsWith('rearrange:')) {
        final original = _library.lookup(result.substring('rearrange:'.length));
        if (original == null) return;
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => PdfRearrangeScreen(library: _library, score: original),
        );
        if (score == null || !mounted) return;
        if (_library.lookup(original.id) == null &&
            _scoreTabIds.contains(original.id)) {
          await _updateScoreTabs([
            for (final id in _scoreTabIds) id == original.id ? score.id : id,
          ]);
        }
        if (mounted) await _openLibraryScore(score);
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
      if (result == 'import-images') {
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => ScanCleanupScreen(library: _library),
        );
        if (mounted && score != null) await _openLibraryScore(score);
        return;
      }
      if (result == 'create-template') {
        final config = await showDialog<ScoreTemplateConfig>(
          context: context,
          builder: (_) => const ScoreTemplateDialog(),
        );
        if (config == null || !mounted) return;
        final bytes = await createTemplatePdf(config);
        if (mounted)
          await _importScores([_generatedScore(bytes, config.title)]);
        return;
      }
      if (result == 'import-text') {
        await _importTextScores();
        return;
      }
      if (result == 'scan') {
        try {
          final path = await const MethodChannel('encoresheets/scanner')
              .invokeMethod<String>('scan');
          if (!mounted || path == null) return;
          final clean = await showDialog<bool>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('Review scan'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Arrange pages'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Clean up images'),
                ),
              ],
            ),
          );
          if (!mounted || clean == null) return;
          final score = await _openReaderPanel<ScoreEntry>(
            (_) => clean
                ? ScanCleanupScreen(library: _library, cameraPdf: XFile(path))
                : PdfRearrangeScreen.scanned(
                    library: _library,
                    scan: XFile(path),
                  ),
          );
          if (mounted && score != null) await _openLibraryScore(score);
        } on PlatformException catch (error) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  error.message ?? 'Could not start the document scanner.',
                ),
              ),
            );
        }
        return;
      }
      if (result == 'setlists') {
        final playback = await _openReaderPanel<SetlistPlayback>(
          (_) => SetlistsScreen(
            library: _library,
            allowTransfers: !_restricted(RestrictedTool.transfers),
          ),
          dockable: true,
        );
        if (playback != null && mounted) {
          await _playScore(playback.setlist, playback.startIndex);
        }
        return;
      }
      if (result == 'support') {
        await _openReaderPanel<void>((_) => SupportScreen(library: _library));
        return;
      }
      if (result == 'backup') {
        await _openReaderPanel<void>(
          (_) => LibraryBackupScreen(library: _library),
        );
        if (!mounted) return;
        await _restorePreferences();
        if (!mounted) return;
        if (_entry case final entry? when _library.lookup(entry.id) == null) {
          final previous = _library.recentlyUpdated
              .where((version) => version.id == entry.id)
              .firstOrNull;
          final replacement = previous == null
              ? null
              : _library.replacementFor(previous);
          if (replacement != null) {
            await _openLibraryScore(replacement);
          } else {
            _playing = null;
            _load(null, null, null);
          }
        }
        return;
      }
      if (result == 'metadata-csv') {
        await _openReaderPanel<void>(
          (_) => MetadataCsvScreen(library: _library),
        );
        if (_entry case final score? when mounted) {
          setState(() => _entry = _library.lookup(score.id));
        }
        return;
      }
      if (result == 'cloud-files') {
        final score = await _openReaderPanel<ScoreEntry>(
          (_) => CloudFilesScreen(library: _library),
        );
        if (mounted && score != null) await _openLibraryScore(score);
        return;
      }
      if (result == 'sync') {
        await _openReaderPanel<void>(
          (_) => LibrarySyncScreen(
            endpoint: _isAppleMobile ? _syncEndpoint : null,
            webDav: _webDavSync,
            setWebDav: (endpoint) async {
              try {
                await _syncRunning;
              } catch (_) {
                // A failed refresh does not prevent switching sync folders.
              }
              if (!mounted) {
                endpoint?.close();
                return;
              }
              _webDavSync?.close();
              _webDavSync = endpoint;
              _lastSync = null;
            },
            refresh: _syncLibrary,
            syncOverWifi: _supportsSharedImport
                ? (endpoint) async {
                    await _runLibrarySync(endpoint);
                  }
                : null,
            reset: _library.resetSyncState,
            lastSuccess: _lastSync,
          ),
        );
        return;
      }
      if (result == 'import-package') {
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'EncoreSheets score packages',
              extensions: ['zip'],
              mimeTypes: ['application/zip'],
              uniformTypeIdentifiers: ['public.zip-archive'],
            ),
          ],
        );
        if (file != null && mounted) {
          final score = await _library.restoreScorePackage(file);
          if (mounted) await _openLibraryScore(score);
        }
        return;
      }
      if (result.startsWith('tab-copy:')) {
        final score = _library.lookup(result.substring('tab-copy:'.length));
        if (score != null) await _openScoreInAnotherTab(score);
        return;
      }
      if (result.startsWith('tab:')) {
        final score = _library.lookup(result.substring(4));
        if (score == null) return;
        if (!_scoreTabIds.contains(score.id)) {
          await _updateScoreTabs([..._scoreTabIds, score.id]);
        }
        if (mounted && _scoreTabIds.contains(score.id)) {
          await _openLibraryScore(score);
        }
      } else if (result.startsWith('bookmark:')) {
        final parts = result.split(':');
        final entry = _library.lookup(parts[1])!;
        final bookmark = entry.bookmarks.firstWhere(
          (item) => item.id == parts[2],
        );
        await _openLibraryScore(
          entry,
          startPage: bookmark.page,
          item: bookmark.isItem ? bookmark : null,
          queue: selectedQueue,
        );
      } else {
        await _openLibraryScore(_library.lookup(result)!, queue: selectedQueue);
      }
    } on LibraryCatalogRecoveryRequired {
      if (!mounted || _restricted(RestrictedTool.transfers)) return;
      final restored = await _openReaderPanel<bool>(
        (_) => LibraryBackupScreen(library: _library, recoveryRequired: true),
      );
      if (restored == true && mounted) {
        _libraryReady = _library.load();
        await _restorePreferences();
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
    List<String> queue = const [],
    bool onlyIfUnchanged = false,
    String? tabInstance,
  }) async {
    final selection = item?.selectionId(entry.id) ?? entry.id;
    final reuse = !_scoreTabIds.contains(selection)
        ? _scoreTabIds.where((id) => _tabSelection(id) == selection).firstOrNull
        : null;
    tabInstance ??= reuse;
    if (reuse != null || _scoreTabIds.contains(selection)) {
      startPage ??= _scoreTabPages[tabInstance ?? selection];
    }
    final revision = _revision;
    if (_entry?.id != entry.id || _itemBookmark?.id != item?.id) {
      final local = await _library.storage.openScore(entry.id);
      final bytes = kIsWeb ? await local.readAsBytes() : null;
      final annotations = await _library.readInk(entry.id);
      if (!mounted || onlyIfUnchanged && revision != _revision) return;
      _load(
        entry,
        local,
        tabInstance: tabInstance,
        bytes,
        annotations: annotations,
        startPage: startPage,
        item: item,
      );
    } else {
      _selectedTabInstance = tabInstance;
      if (startPage != null) _jumpToPage(startPage);
    }
    setState(() {
      _playing = null;
      _libraryQueue = queue;
    });
    if (!onlyIfUnchanged) _remember(entry.id, _page, opened: true);
  }

  Future<void> _syncAssistantIfReady() async {
    try {
      await _startupPreferences;
      await _libraryReady;
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          _performance ||
          _restricted(RestrictedTool.connections)) {
        return;
      }
      await _assistantConnection.sync();
    } catch (_) {
      // The next foreground sync retries. AI Connections shows manual errors.
    }
  }

  Future<void> _syncIfReady() async {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        (!_isAppleMobile && _webDavSync == null) ||
        _picking ||
        _inking ||
        _stylusDrawing ||
        _performance ||
        _restricted(RestrictedTool.connections))
      return;
    try {
      if ((_webDavSync != null ||
              _isAppleMobile && await _syncEndpoint.configured) &&
          mounted &&
          !_picking &&
          !_inking &&
          !_stylusDrawing &&
          !_performance) {
        await _syncLibrary();
      }
    } catch (_) {
      // Files may still be downloading or the device may be offline.
      // The next foreground refresh retries; manual refresh reports the failure.
    }
  }

  Future<DateTime> _syncLibrary() => _syncRunning ??= _runLibrarySync()
      .whenComplete(() => _syncRunning = null);

  Future<DateTime> _runLibrarySync([LibrarySyncEndpoint? endpoint]) async {
    await _libraryReady;
    final updated = await _library.synchronize(
      endpoint ?? _webDavSync ?? _syncEndpoint,
      mayApply: () => mounted && !_inking && !_stylusDrawing && !_performance,
    );
    if (_entry case final current?
        when mounted && !_inking && !_stylusDrawing && !_performance) {
      if (updated.contains(current.id)) {
        final refreshed = _library.lookup(current.id);
        if (refreshed == null) {
          _playing = null;
          _load(null, null, null);
        } else {
          final revision = _revision;
          final annotations = await _library.readInk(current.id);
          if (mounted &&
              !_inking &&
              !_stylusDrawing &&
              !_performance &&
              revision == _revision) {
            final item = refreshed.bookmarks
                .where((bookmark) => bookmark.id == _itemBookmark?.id)
                .firstOrNull;
            _load(
              refreshed,
              _file,
              _bytes,
              annotations: annotations,
              startPage: _page,
              item: item,
            );
          }
        }
      }
    }
    final completed = DateTime.now();
    if (endpoint == null) _lastSync = completed;
    return completed;
  }

  Future<void> _updateScoreTabs(List<String> ids) async {
    if (_savingTabs) return;
    setState(() => _savingTabs = true);
    try {
      final pages = Map.of(_scoreTabPages)
        ..removeWhere((id, _) => !ids.contains(id));
      await _library.updatePreferences({
        'scoreTabs': ids,
        'scoreTabPages': pages,
        'activeScoreTab': ids.contains(_activeScoreTabId)
            ? _activeScoreTabId
            : null,
      });
      if (mounted) {
        setState(() {
          _scoreTabIds = ids;
          _scoreTabPages.removeWhere((id, _) => !ids.contains(id));
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save score tabs.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingTabs = false);
    }
  }

  String _tabSelection(String id) => id.split('|').first;

  (ScoreEntry, ScoreBookmark?)? _lookupTab(String id) =>
      _library.lookupSelection(_tabSelection(id));

  String? get _activeScoreTabId {
    if (_selectedTabInstance case final instance?
        when _scoreTabIds.contains(instance)) {
      return instance;
    }
    return _currentScoreSelection;
  }

  String? get _currentScoreSelection {
    final score = _entry;
    return score == null
        ? null
        : _itemBookmark?.selectionId(score.id) ?? score.id;
  }

  Future<void> _closeScoreTab(String id) async {
    final index = _scoreTabIds.indexOf(id);
    if (index < 0 || _savingTabs || _picking) return;
    final wasActive = id == _activeScoreTabId;
    final remaining = [..._scoreTabIds]..removeAt(index);
    await _updateScoreTabs(remaining);
    if (mounted && wasActive && !_scoreTabIds.contains(id)) {
      if (remaining.isNotEmpty) {
        await _switchScoreTab(remaining[math.min(index, remaining.length - 1)]);
      } else {
        setState(() => _selectedTabInstance = null);
      }
    }
  }

  Future<void> _switchScoreTab(String id) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      final target = _lookupTab(id);
      if (target == null) {
        await _updateScoreTabs(_scoreTabIds.where((tab) => tab != id).toList());
      } else if (mounted) {
        final (score, bookmark) = target;
        await _openLibraryScore(
          score,
          item: bookmark,
          startPage: _scoreTabPages[id] ?? bookmark?.page ?? score.page,
          tabInstance: id == _tabSelection(id) ? null : id,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this score.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _openNewScoreTab() async {
    if (_picking || _savingTabs) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      if (!mounted) return;
      final scores = [
        ..._library.recent,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      final id = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Open in new tab'),
          children: [
            if (scores.isEmpty)
              const SimpleDialogOption(
                child: Text('Import a PDF from the score library first.'),
              ),
            for (final score in scores) ...[
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, score.id),
                child: Text(score.title),
              ),
              for (final bookmark in score.bookmarks.where(
                (item) => item.isItem,
              ))
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.pop(dialog, bookmark.selectionId(score.id)),
                  child: Text('${score.title} · ${bookmark.title}'),
                ),
            ],
          ],
        ),
      );
      if (!mounted || id == null) return;
      final target = _library.lookupSelection(id);
      if (target == null) return;
      if (!_scoreTabIds.contains(id)) {
        await _updateScoreTabs([..._scoreTabIds, id]);
      }
      if (mounted && _scoreTabIds.contains(id)) {
        final (score, bookmark) = target;
        await _openLibraryScore(
          score,
          item: bookmark,
          startPage: _scoreTabPages[id] ?? bookmark?.page,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this score.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showBookmarks() async {
    final entry = _entry;
    if (entry == null || _picking || _pages == 0) return;
    setState(() => _picking = true);
    try {
      final destination = await _openReaderPanel<BookmarkDestination>(
        (_) => BookmarksScreen(
          library: _library,
          scoreId: entry.id,
          page: _page,
          pageCount: _pages,
          document: _viewer.document,
        ),
        dockable: true,
      );
      if (!mounted || destination == null) return;
      final score = _library.lookup(destination.scoreId);
      if (score == null) return;
      if (score.id != entry.id ||
          destination.item != null ||
          _itemBookmark != null) {
        await _openLibraryScore(
          score,
          startPage: destination.page,
          item: destination.item,
        );
      } else {
        _jumpToPage(destination.page);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the saved page.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showJumpLinks() async {
    final id = _entry?.id;
    if (id == null || _picking || !_viewer.isReady) return;
    final score = _library.lookup(id)!;
    final document = _viewer.document;
    setState(() => _picking = true);
    try {
      final links = await Navigator.of(context).push<List<ScoreJump>>(
        MaterialPageRoute(
          builder: (_) => JumpLinksScreen(
            document: document,
            page: _page,
            links: score.jumps,
          ),
        ),
      );
      if (links == null || !mounted) return;
      await _library.updateScore(id, (old) => old.copyWith(jumps: links));
      if (mounted) setState(() => _entry = _library.lookup(id));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save score links.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Iterable<(ScoreJump, JumpPoint, JumpPoint, bool)> _jumpMarkers() sync* {
    for (final link in _entry?.jumps ?? const <ScoreJump>[]) {
      if (link.source.page < _firstPage ||
          link.source.page > _lastPage ||
          link.target.page < _firstPage ||
          link.target.page > _lastPage)
        continue;
      yield (link, link.source, link.target, false);
      yield (link, link.target, link.source, true);
    }
  }

  Offset _jumpPosition(JumpPoint point) {
    final rect = _viewer.layout.pageLayouts[point.page - 1];
    return rect.topLeft + Offset(rect.width * point.x, rect.height * point.y);
  }

  bool _followJumpAt(Offset position) {
    if (_picking || _inking || !_viewer.isReady || _pages == 0) return false;
    for (final action in (_entry?.actions ?? const <ScoreAction>[]).reversed) {
      if (action.page > _pages ||
          action.page < _firstPage ||
          action.page > _lastPage ||
          _halfPreview && action.page == _page && action.y < _splitFor(_page))
        continue;
      final marker = JumpPoint(action.page, action.x, action.y);
      var hitLabel = false;
      if (action.showLabel) {
        final pageRect = _viewer.layout.pageLayouts[action.page - 1];
        final label = _actionLabelRect(
          action,
          pageRect.size,
        ).shift(pageRect.topLeft);
        hitLabel = Rect.fromPoints(
          _viewer.documentToLocal(label.topLeft),
          _viewer.documentToLocal(label.bottomRight),
        ).contains(position);
      }
      if (hitLabel ||
          (_viewer.documentToLocal(_jumpPosition(marker)) - position)
                  .distance <=
              _pageTargetRadius) {
        _runScoreAction(action);
        return true;
      }
    }
    for (final (_, marker, target, _) in _jumpMarkers()) {
      if (_halfPreview && marker.page == _page && marker.y < _splitFor(_page))
        continue;
      if ((_viewer.documentToLocal(_jumpPosition(marker)) - position)
              .distance <=
          _pageTargetRadius) {
        _followJump(target);
        return true;
      }
    }
    return false;
  }

  Rect _actionLabelRect(ScoreAction action, Size size) {
    final text = TextPainter(
      text: TextSpan(text: action.title, style: _actionLabelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: 102);
    final width = math.min(text.width.ceilToDouble() + 10, size.width);
    final height = text.height.ceilToDouble() + 4;
    text.dispose();
    final x = (action.x * size.width - width / 2).clamp(
      0.0,
      size.width - width,
    );
    final centerY = action.y * size.height;
    final below = centerY + _pageButtonSize / 2 + 2;
    final y = below + height <= size.height
        ? below
        : centerY - _pageButtonSize / 2 - height - 2;
    return Rect.fromLTWH(x, math.max(0, y), width, height);
  }

  static const _actionLabelStyle = TextStyle(color: Colors.white, fontSize: 12);

  Future<void> _runScoreAction(ScoreAction action) async {
    if (_picking || _inking) return;
    if (action.kind == ScoreActionKind.nextSetlist ||
        action.kind == ScoreActionKind.previousSetlist) {
      final setlist = _playing;
      final index =
          _setIndex + (action.kind == ScoreActionKind.nextSetlist ? 1 : -1);
      if (setlist == null ||
          index < 0 ||
          index >= setlist.scores.length ||
          _library.lookupSelection(setlist.scores[index]) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No adjacent score is available in this setlist.'),
          ),
        );
        return;
      }
      setState(() => _picking = true);
      try {
        await _playScore(setlist, index);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the setlist score.')),
          );
      } finally {
        _finishPicking();
      }
      return;
    }
    if (const {
      ScoreActionKind.website,
      ScoreActionKind.externalApp,
      ScoreActionKind.externalFile,
    }.contains(action.kind)) {
      await _openExternalScoreAction(action);
      return;
    }
    if (const {
      ScoreActionKind.tempo,
      ScoreActionKind.toggleMetronome,
      ScoreActionKind.pitch,
      ScoreActionKind.midi,
    }.contains(action.kind)) {
      await _runRehearsalAction(action);
      return;
    }
    if (action.kind == ScoreActionKind.note) {
      await _editPageNote(action.page);
      return;
    }
    if (action.kind == ScoreActionKind.audio) {
      final score = _entry;
      if (score == null) return;
      final selection = _itemBookmark?.selectionId(score.id) ?? score.id;
      try {
        if (ScoreAudioSession.supported) {
          final audio = _scoreAudio ??= ScoreAudioSession(_library);
          if (await audio.toggle(selection)) return;
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No playable audio is linked to this score.'),
            ),
          );
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play the linked audio.')),
          );
      }
      return;
    }
    final destination = _library.lookupSelection(action.selection ?? '');
    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The destination score is unavailable.')),
      );
      return;
    }
    setState(() => _picking = true);
    try {
      await _openLibraryScore(
        destination.$1,
        startPage: destination.$2?.page,
        item: destination.$2,
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the destination score.'),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _openExternalScoreAction(ScoreAction action) async {
    final isFile = action.kind == ScoreActionKind.externalFile;
    if (_restricted(
      isFile ? RestrictedTool.transfers : RestrictedTool.connections,
    ))
      return;
    _stopAutoScroll(rebuild: false);
    setState(() => _picking = true);
    try {
      if (await openScoreActionDestination(action)) return;
    } catch (_) {
      // A handler may be unavailable or the linked file may have moved.
    } finally {
      _finishPicking();
    }
    if (!mounted) return;
    final message = switch (action.kind) {
      ScoreActionKind.externalFile => 'Could not open the file. Check the attachment and that a compatible app is installed.',
      ScoreActionKind.externalApp => 'No installed app could open this link.',
      _ => 'Could not open this website.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runRehearsalAction(ScoreAction action) async {
    if (!ScoreAudioSession.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This action is unavailable on this device.'),
        ),
      );
      return;
    }
    setState(() => _picking = true);
    try {
      switch (action.kind) {
        case ScoreActionKind.toggleMetronome:
          final meter = _rehearsalMeter;
          if (meter.running) {
            await meter.stop();
          } else {
            meter.bpm = int.parse(action.parameter!);
            await meter.start();
          }
        case ScoreActionKind.tempo:
          final tempo = int.parse(action.parameter!);
          final meter = _rehearsalMeter;
          final wasRunning = meter.running;
          if (wasRunning) await meter.stop();
          meter.bpm = tempo;
          if (wasRunning) await meter.start();
          if (_entry case final score?) {
            await _library.updateScore(
              score.id,
              (old) =>
                  old.copyWith(metadata: {...old.metadata, 'tempo': '$tempo'}),
            );
            if (mounted && _entry?.id == score.id)
              setState(() => _entry = _library.lookup(score.id));
          }
        case ScoreActionKind.pitch:
          await (_referenceTone ??= ReferenceTone()).play(
            int.parse(action.parameter!),
            timbre: action.timbre,
          );
        case ScoreActionKind.midi:
          if (_restricted(RestrictedTool.connections)) return;
          final devices = await _midi.devices ?? [];
          final targets = devices.where((device) => device.connected).toList();
          if (targets.isEmpty) throw StateError('Connect a MIDI device first.');
          final bytes = Uint8List.fromList(
            ScoreAction.midiBytes(action.parameter!)!,
          );
          for (final device in targets) {
            _midi.sendData(bytes, deviceId: device.id);
          }
        default:
          break;
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'Could not run this action.',
            ),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _editScoreActions() async {
    final score = _entry;
    if (_picking ||
        score == null ||
        !_viewer.isReady ||
        _restricted(RestrictedTool.markup))
      return;
    setState(() => _picking = true);
    try {
      final actions = await _openReaderPanel<List<ScoreAction>>(
        (_) => ScoreActionsScreen(
          document: _viewer.document,
          page: _page,
          library: _library,
          actions: score.actions,
          allowFiles: !_restricted(RestrictedTool.transfers),
        ),
      );
      if (!mounted || actions == null) return;
      await _library.updateScore(
        score.id,
        (old) => old.copyWith(actions: actions),
      );
      if (mounted && _entry?.id == score.id)
        setState(() => _entry = _library.lookup(score.id));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save action buttons.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showScoreAudio() async {
    final score = _entry;
    if (!ScoreAudioSession.supported || _picking || score == null) return;
    final selection = _itemBookmark?.selectionId(score.id) ?? score.id;
    final audio = _scoreAudio ??= ScoreAudioSession(_library);
    AudioPageCueMode? mode;
    setState(() => _picking = true);
    try {
      await _audioCueWrite;
      if (!mounted) return;
      mode = await showDialog<AudioPageCueMode>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScoreAudioDialog(
          audio: audio,
          selection: selection,
          title: _title,
          cueMode: _audioCueMode,
        ),
      );
    } finally {
      _finishPicking();
    }
    if (!mounted) return;
    if (audio.loadedFile != _audioCueFile || mode != null) {
      _stopAudioCues();
    }
    if (mode == AudioPageCueMode.off) return;
    if (mode == null && _audioCueMode != AudioPageCueMode.replay) return;
    final file = audio.loadedFile;
    if (file == null) return;
    try {
      final cues = await audio.pageCues(file);
      if (!mounted || audio.loadedFile != file || _entry?.id != score.id)
        return;
      if (mode == null) {
        _audioCues = cues;
        return;
      }
      _audioCueFile = file;
      _audioCueMode = mode;
      _audioCues = cues;
      if (mode == AudioPageCueMode.record) {
        _recordAudioCue(_page, starting: true);
      } else {
        _audioCuePlayback = audio.player.positionStream.listen((_) {
          if (_picking || audio.loadedFile != _audioCueFile) return;
          final cue = audioCueAt(_audioCues, audio.timelinePosition);
          if (cue == _lastAudioCue) return;
          _lastAudioCue = cue;
          if (cue != null) _jumpToPage(cue.page);
        });
      }
      if (!audio.player.playing) await audio.toggle(selection);
    } catch (_) {
      _stopAudioCues();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start audio page turns.')),
        );
      }
    }
  }

  void _stopAudioCues() {
    unawaited(_audioCuePlayback?.cancel());
    _audioCuePlayback = null;
    _audioCueMode = AudioPageCueMode.off;
    _audioCueFile = null;
    _lastAudioCue = null;
  }

  void _recordAudioCue(int page, {bool starting = false}) {
    final audio = _scoreAudio;
    final file = _audioCueFile;
    if (_audioCueMode != AudioPageCueMode.record ||
        audio == null ||
        file == null ||
        audio.loadedFile != file ||
        (!starting && !audio.player.playing))
      return;
    final ms = audio.timelinePosition.inMilliseconds;
    final cues = [
      for (final cue in _audioCues)
        if (cue.milliseconds != ms) cue,
      (milliseconds: ms, page: page),
    ]..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    _audioCues = cues;
    _audioCueWrite = _audioCueWrite
        .then((_) => audio.savePageCues(file, cues))
        .catchError((Object _) {
          _stopAudioCues();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not save the page cue.')),
            );
          }
        });
  }

  Future<void> _showPracticeRecordings() async {
    final score = _entry;
    if (!_supportsSharedImport || _picking || score == null) return;
    final selection = _itemBookmark?.selectionId(score.id) ?? score.id;
    final audio = _scoreAudio ??= ScoreAudioSession(_library);
    setState(() => _picking = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PracticeRecordingsDialog(
          takes: PracticeRecordings(_library, selection),
          audio: audio,
        ),
      );
    } finally {
      _finishPicking();
    }
  }

  void _focusPractice({bool opened = false}) {
    final score = _entry;
    final bookmark = _itemBookmark;
    final list = _playing;
    _practice.focus([
      if (score != null)
        (kind: PracticeKind.score, id: score.id, title: score.title),
      if (score != null && bookmark != null)
        (
          kind: PracticeKind.bookmark,
          id: bookmark.selectionId(score.id),
          title: bookmark.title,
        ),
      if (score != null && list != null)
        (kind: PracticeKind.setlist, id: list.id, title: list.name),
    ], opened: opened);
  }

  Future<void> _showRestrictions() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final current = _restrictions;
      final draft = await showDialog<RestrictionDraft>(
        context: context,
        builder: (_) => RestrictionsDialog(current: current),
      );
      if (!mounted || draft == null) return;
      final next = draft.tools.isEmpty
          ? null
          : current == null
          ? await ReaderRestrictions.create(draft.passcode, draft.tools)
          : ReaderRestrictions(current.salt, current.digest, draft.tools);
      await _library.updatePreferences({'readerRestrictions': next?.toJson()});
      if (!mounted) return;
      setState(() {
        _restrictions = next;
        if (_restricted(RestrictedTool.markup)) _inking = false;
      });
      if (_restricted(RestrictedTool.connections)) {
        _stopFaceTurns();
        await _ensemble?.close();
        if (!mounted) return;
        setState(() => _followingSpread = _missingFacingPage = false);
        if (_presenting) await _togglePresentation();
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply the restrictions.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showSupport() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      if (mounted)
        await _openReaderPanel<void>((_) => SupportScreen(library: _library));
    } finally {
      _finishPicking();
    }
  }

  Future<void> _chooseLanguage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('App language'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, ''),
              child: Text(
                _language == null
                    ? '✓ Use device language'
                    : 'Use device language',
              ),
            ),
            for (final item in readerLanguageNames.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, item.key),
                child: Text(
                  _language == item.key ? '✓ ${item.value}' : item.value,
                ),
              ),
          ],
        ),
      );
      if (!mounted || result == null) return;
      final language = result.isEmpty ? null : result;
      await _library.updatePreferences({'readerLanguage': language});
      if (!mounted) return;
      _language = language;
      widget.onLanguage?.call(language);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the language setting.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showSettingsProfiles() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final data = await _library.storage.readPreferences();
      if (!mounted) return;
      final profile = await showDialog<SettingsProfile>(
        context: context,
        builder: (_) => SettingsProfilesDialog(
          saved: readSettingsProfiles(data['settingsProfiles']),
          current: (reader: _preferences, drawing: _drawing),
          save: (profiles) => _library.updatePreferences({
            'settingsProfiles': writeSettingsProfiles(profiles),
          }),
        ),
      );
      if (!mounted || profile == null) return;
      await _library.updatePreferences({
        ...profile.reader.toJson(),
        'drawingSettings': profile.drawing.toJson(),
      });
      if (!mounted) return;
      final previousMode = _scrollMode;
      setState(() {
        _preferences = profile.reader;
        _drawing = profile.drawing;
        _halfPreview = false;
        if (previousMode != _scrollMode) _resetScoreLayout();
      });
      _metronome?.soft = profile.reader.softMetronome;
      _keepScreenAwake(_performance || _preferences.keepAwake);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not use these settings profiles.'),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _editMetadataSymbols() async {
    final selected = await chooseMetadataSymbols(context, _metadataSymbols);
    if (!mounted || selected == null) return;
    try {
      await _library.updatePreferences({'metadataSymbols': selected});
      if (mounted) setState(() => _metadataSymbols = selected);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the metadata symbols.')),
        );
    }
  }

  void _applyStatusBar() {
    if (!_supportsSharedImport) return;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [
          if (_appearance.showStatusBar) SystemUiOverlay.top,
          SystemUiOverlay.bottom,
        ],
      ).catchError((Object _) {}),
    );
  }

  Future<void> _changeThemeOptions() async {
    final result = await chooseReaderAppearance(context, _appearance);
    if (!mounted || result == null) return;
    try {
      await _library.updatePreferences({'appearanceOptions': result.toJson()});
      if (!mounted) return;
      setState(() => _appearance = result);
      widget.onAppearance?.call(result);
      _applyStatusBar();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save theme settings.')),
        );
    }
  }

  Future<void> _showMaintenance() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final command = await showDialog<int>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Maintenance'),
          children: [
            for (final (id, label) in [
              (1, 'Reset reader display and menus'),
              if (!_restricted(RestrictedTool.markup))
                (2, 'Reset drawing settings and personal stamps'),
              if (!kIsWeb) (3, 'Remove old temporary files'),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, id),
                child: Text(label),
              ),
          ],
        ),
      );
      if (!mounted || command == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Apply maintenance change?'),
          content: Text(switch (command) {
            1 => 'Restore the default reader display, theme, quick-access tools, and library sorting.',
            2 => 'Restore default drawing tools and remove personal stamps.',
            _ => 'Remove app working copies last modified more than seven days ago.',
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      var message = 'Defaults restored.';
      if (command == 3) {
        final count = await cleanOldWorkingFiles();
        message = 'Removed $count old working copies.';
      } else {
        await _library.updatePreferences(
          command == 1
              ? {
                  ...const ReaderPreferences().toJson(),
                  'appearanceOptions': null,
                  'quickReaderTools': null,
                  'metadataSymbols': null,
                  'searchOptions': null,
                }
              : {
                  'drawingSettings': const DrawingSettings().toJson(),
                  'personalStamps': <String>[],
                },
        );
        if (!mounted) return;
        await _restorePreferences();
        if (mounted)
          setState(() {
            _stamp = null;
            _halfPreview = false;
          });
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not apply this maintenance change.'),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showPracticeActivity() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _libraryReady;
      await _practice.suspend();
      if (!mounted) return;
      await _openReaderPanel<void>(
        (_) => PracticeDashboard(
          activity: _practice,
          library: _library,
          allowExport: !_restricted(RestrictedTool.transfers),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open practice activity.')),
        );
    } finally {
      _requestWidgetRefresh();
      if (mounted) _focusPractice();
      _finishPicking();
    }
  }

  void _requestWidgetRefresh() {
    if (!_supportsSharedImport) return;
    unawaited(_publishPracticeWidget().catchError((Object _) {}));
  }

  Future<void> _publishPracticeWidget() async {
    final prefs = await _library.storage.readPreferences();
    final goals = readPracticeGoals(prefs['practiceGoals']);
    final history = readPracticeActivity(prefs['practiceActivity']);
    final now = DateTime.now();
    await const MethodChannel('encoresheets/widget')
        .invokeMethod<void>('practice', {
          'total': goals.length,
          'reached': goals
              .where((goal) => goalProgress(goal, history, now) >= goal.target)
              .length,
        });
  }

  RehearsalMetronome get _rehearsalMeter => _metronome ??= RehearsalMetronome()
    ..soft = _preferences.softMetronome
    ..addListener(_onMetronomeBeat);

  void _onMetronomeBeat() {
    final meter = _metronome;
    if (!mounted || meter == null) return;
    final elapsed = meter.elapsedBeats;
    if (_meterPage != _page ||
        _picking ||
        _inking ||
        _pages == 0 ||
        !meter.running ||
        meter.countingIn ||
        elapsed < _meterPageStart) {
      _meterPage = _page;
      _meterPageStart = elapsed;
      return;
    }
    final count = int.tryParse(
      _entry?.metadata['metronomePageBeats.$_page'] ?? '',
    );
    if (count == null || count <= 0 || elapsed - _meterPageStart < count) {
      return;
    }
    _meterPageStart = elapsed;
    if (_page < _lastPage && _audioCueMode != AudioPageCueMode.replay) {
      _jumpToPage(_page + math.max(1, _spreadStep));
      _meterPage = _page;
    }
  }

  Future<void> _showMetronome({bool showUtilities = false}) async {
    if (_picking || !ScoreAudioSession.supported) return;
    final score = _entry;
    final meter = _rehearsalMeter;
    final page = _page;
    final key = 'metronomePageBeats.$page';
    var pageBeats = int.tryParse(score?.metadata[key] ?? '') ?? 0;
    if (!meter.running && score != null) {
      final tempo = int.tryParse(score.metadata['tempo'] ?? '');
      if (tempo != null) meter.bpm = tempo.clamp(25, 280);
      final signature = score.metadata['time']?.split('/');
      if (signature != null && signature.length == 2) {
        final beats = int.tryParse(signature.first.trim());
        final unit = int.tryParse(signature.last.trim());
        if (beats != null) meter.beats = beats.clamp(1, 16);
        if (const [2, 4, 8, 16].contains(unit)) meter.unit = unit!;
      }
    }
    setState(() => _picking = true);
    try {
      var utility = _AudioUtility.metronome;
      ReferenceTone? tone;
      var switching = false;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => StatefulBuilder(
            builder: (dialog, update) {
              final title = showUtilities
                  ? Wrap(
                      spacing: 6,
                      children: [
                        for (final (tab, label) in const [
                          (_AudioUtility.metronome, 'Metronome'),
                          (_AudioUtility.pitch, 'Pitch'),
                          (_AudioUtility.tuner, 'Tuner'),
                        ])
                          if (tab != _AudioUtility.tuner ||
                              _supportsSharedImport)
                            ChoiceChip(
                              label: Text(label),
                              selected: utility == tab,
                              onSelected: switching || utility == tab
                                  ? null
                                  : (_) async {
                                      update(() => switching = true);
                                      try {
                                        if (tab == _AudioUtility.metronome) {
                                          await tone?.stop();
                                        } else {
                                          if (meter.running) await meter.stop();
                                          await _scoreAudio?.pause();
                                          await tone?.stop();
                                        }
                                        if (dialog.mounted)
                                          update(() => utility = tab);
                                      } catch (_) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Could not switch audio utilities.',
                                                  ),
                                                ),
                                              );
                                        }
                                      } finally {
                                        if (dialog.mounted)
                                          update(() => switching = false);
                                      }
                                    },
                            ),
                      ],
                    )
                  : null;
              if (utility == _AudioUtility.metronome) {
                return MetronomeDialog(
                  title: title,
                  metronome: meter,
                  page: score == null ? null : page,
                  initialPageBeats: pageBeats,
                  onPageBeatsChanged: (count) => pageBeats = count,
                );
              }
              return TunerDialog(
                key: ValueKey(utility),
                title: title,
                tone: tone ??= _referenceTone ??= ReferenceTone(),
                showPitch: utility == _AudioUtility.pitch,
                microphone: utility == _AudioUtility.tuner,
              );
            },
          ),
        );
      } finally {
        if (showUtilities && utility != _AudioUtility.metronome)
          await tone?.stop();
      }
      if (!mounted || score == null || _entry?.id != score.id) return;
      await _library.updateScore(
        score.id,
        (old) => old.copyWith(
          metadata: {
            ...Map.of(old.metadata)..remove(key),
            'tempo': '${meter.bpm}',
            'time': '${meter.beats}/${meter.unit}',
            if (pageBeats > 0) key: '$pageBeats',
          },
        ),
      );
      if (mounted && _entry?.id == score.id)
        setState(() => _entry = _library.lookup(score.id));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the metronome settings.'),
          ),
        );
    } finally {
      _finishPicking();
      _meterPageStart = meter.elapsedBeats;
      _meterPage = _page;
    }
  }

  Future<void> _showTuner() async {
    if (_picking || !ScoreAudioSession.supported) return;
    setState(() => _picking = true);
    try {
      await _metronome?.stop();
      await _scoreAudio?.pause();
      if (!mounted) return;
      final tone = _referenceTone ??= ReferenceTone();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            TunerDialog(tone: tone, microphone: _supportsSharedImport),
      );
      await tone.stop();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the tuner.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showPiano() async {
    if (_picking || !ScoreAudioSession.supported) return;
    setState(() => _picking = true);
    final before = _midiPiano;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => RehearsalPianoDialog(
          piano: _piano ??= RehearsalPiano(),
          midiSound: _midiPiano,
          onMidiSound: (enabled) {
            _midiPiano = enabled;
            if (enabled) _listenToMidi();
          },
        ),
      );
      if (before != _midiPiano) {
        await _library.updatePreferences({'midiPiano': _midiPiano});
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the MIDI piano setting.'),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  void _followJump(JumpPoint target) {
    if (_picking || !_viewer.isReady) return;
    _jumpToPage(target.page);
    final point = _jumpPosition(target);
    _viewer.ensureVisible(
      Rect.fromCenter(center: point, width: 1, height: 1),
      duration: Duration.zero,
    );
    _focus.requestFocus();
  }

  Future<void> _playScore(
    Setlist setlist,
    int index, {
    bool fromEnd = false,
  }) async {
    if (index == 0 && !fromEnd) {
      setlist = setlist.copyWith(
        scores: setlist.scores.where(
          (id) => _library.lookupSelection(id) != null,
        ),
      );
      if (setlist.scores.isEmpty) return;
    }
    final selection = _library.lookupSelection(setlist.scores[index]);
    if (selection == null) throw StateError('Setlist score is missing');
    final (entry, item) = selection;
    final local = await _library.storage.openScore(entry.id);
    final bytes = kIsWeb ? await local.readAsBytes() : null;
    final annotations = await _library.readInk(entry.id);
    var start = item?.page ?? 1;
    if (fromEnd) {
      if (item?.endPage case final end?) {
        start = end;
      } else {
        final document = bytes == null
            ? await PdfDocument.openFile(local.path)
            : await PdfDocument.openData(bytes, sourceName: local.name);
        try {
          start = document.pages.length;
        } finally {
          await document.dispose();
        }
      }
    }
    if (!mounted) return;
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
    unawaited(
      _library
          .recordSetlistPlay(setlist.id, setlist.scores[index])
          .catchError((Object _) {}),
    );
  }

  Future<void> _editScore(ScoreEntry score) async {
    final setlists = _library.setlists;
    final originalMembership = {
      for (final list in setlists)
        if (list.scores.contains(score.id)) list.id,
    };
    final updated = await editScoreMetadata(
      context,
      score,
      loadPdfInfo: () async =>
          readEmbeddedPdfInfo(await _library.storage.openScore(score.id)),
      preview: (page) => renderLibraryScorePreview(
        _library,
        score,
        pageNumber: page,
      ).catchError((Object _) => null),
      setlists: setlists,
      libraries: _library.collections,
      onMidi: _restricted(RestrictedTool.connections)
          ? null
          : () => _editMidiAutomation(_library.lookup(score.id) ?? score),
      onAudio:
          ScoreAudioSession.supported && !_restricted(RestrictedTool.transfers)
          ? () => _editScoreAudioLink(score)
          : null,
    );
    if (updated == null || !mounted) return;
    try {
      await _library.editMetadata(score.id, updated.title, updated.fields);
      if (!setEquals(updated.libraries, score.collections.toSet())) {
        await _library.assignCollections(score.id, updated.libraries);
      }
      for (final list in _library.setlists) {
        final include = updated.setlists.contains(list.id);
        if (include == originalMembership.contains(list.id)) continue;
        final present = list.scores.contains(score.id);
        if (include == present) continue;
        await _library.saveSetlist(
          list.copyWith(
            scores: [
              for (final id in list.scores)
                if (id != score.id) id,
              if (include) score.id,
            ],
          ),
        );
      }
      if (mounted && _entry?.id == score.id) {
        setState(() => _entry = _library.lookup(score.id));
      }
      if (updated.openPage case final page? when mounted) {
        if (_entry?.id == score.id &&
            _viewer.isReady &&
            page >= _firstPage &&
            page <= _lastPage) {
          _jumpToPage(page);
        } else if (_library.lookup(score.id) case final target?) {
          await _openLibraryScore(target, startPage: page);
        }
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save score details.')),
        );
    }
  }

  Future<void> _editScoreAudioLink(ScoreEntry score) async {
    final audio = _scoreAudio ??= ScoreAudioSession(_library);
    await showDialog<void>(
      context: context,
      builder: (_) => ScoreAudioDialog(
        audio: audio,
        selection: score.id,
        title: score.title,
        cueMode: AudioPageCueMode.off,
        linkOnly: true,
      ),
    );
    if (mounted && _audioCueFile != null && audio.loadedFile != _audioCueFile) {
      _stopAudioCues();
    }
  }

  Future<void> _nextScore() => _stepSetlist(1);

  Future<void> _stepSetlist(int step) async {
    if (_picking || (step > 0 ? !_hasNextScore : !_hasPreviousScore)) return;
    setState(() => _picking = true);
    try {
      await _playScore(_playing!, _setIndex + step, fromEnd: step < 0);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              step > 0
                  ? 'Could not open the next score.'
                  : 'Could not open the previous score.',
            ),
          ),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showNowPlaying() async {
    final current = _entry;
    if (_picking || current == null) return;
    final setlist = _playing;
    final active = _itemBookmark?.selectionId(current.id) ?? current.id;
    final queue =
        setlist?.scores ??
        (_libraryQueue.contains(active) ? _libraryQueue : [active]);
    final index = setlist == null ? queue.indexOf(active) : _setIndex;
    setState(() => _picking = true);
    try {
      final destination = await _openReaderPanel<int>(
        (context) => Scaffold(
          appBar: AppBar(title: const Text('Now playing')),
          body: SafeArea(
            child: ListView(
              children: [
                if (setlist != null)
                  ListTile(
                    title: Text(setlist.name),
                    subtitle: Text('${queue.length} scores'),
                  ),
                for (final (position, id) in queue.indexed)
                  ListTile(
                    leading: position == index
                        ? const Icon(Icons.play_arrow)
                        : Text('${position + 1}'),
                    selected: position == index,
                    title: Text(switch (_library.lookupSelection(id)) {
                      (final score, final item) => item?.title ?? score.title,
                      null => setlist?.placeholders[id] ?? 'Missing score',
                    }),
                    subtitle: position == index
                        ? const Text('Current score')
                        : null,
                    enabled: _library.lookupSelection(id) != null,
                    onTap: () => Navigator.pop(context, position),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || destination == null || destination == index) return;
      if (setlist != null) {
        await _playScore(setlist, destination);
      } else if (_library.lookupSelection(queue[destination]) case (
        final score,
        final item,
      )) {
        await _openLibraryScore(
          score,
          startPage: item?.page,
          item: item,
          queue: queue,
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the selected score.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _findInScore() async {
    if (_picking || _pages == 0 || !_viewer.isReady) return;
    final revision = _revision;
    final document = _viewer.document;
    final first = _firstPage;
    final last = _lastPage;
    setState(() => _picking = true);
    ScoreTextMatch? match;
    try {
      match = await _openReaderPanel<ScoreTextMatch>(
        (_) => ScoreTextSearchScreen(
          document: document,
          firstPage: first,
          lastPage: last,
          annotations: _inkSnapshot(),
          notes: _entry?.pageNotes ?? const {},
        ),
      );
    } finally {
      _finishPicking();
    }
    if (mounted && revision == _revision && match != null) {
      _go(match.page);
      if (match.source == ScoreTextSource.note) await _editPageNote(match.page);
    }
  }

  Future<void> _editPageNote(int page) async {
    final score = _entry;
    if (_picking ||
        score == null ||
        page < _firstPage ||
        page > _lastPage ||
        _restricted(RestrictedTool.markup))
      return;
    setState(() => _picking = true);
    try {
      final before = score.pageNotes[page] ?? '';
      final note = await showDialog<String>(
        context: context,
        builder: (_) => PageNoteDialog(page: page, note: before),
      );
      if (!mounted || note == null || note == before) return;
      await _library.savePageNote(score.id, page, note);
      if (mounted && _entry?.id == score.id)
        setState(() => _entry = _library.lookup(score.id));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the page note.')),
        );
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
    _ink[_annotationPage ?? _page]?.finish(commit: false);
    setState(() {
      _performance = !_performance;
      _inking = false;
      _annotationPage = null;
      _showControls = true;
    });
    _keepScreenAwake(_performance || _preferences.keepAwake);
    _focus.requestFocus();
  }

  Future<void> _remember(String? id, int page, {bool opened = false}) async {
    if (opened && mounted) _focusPractice(opened: true);
    if (_presenting) unawaited(_updatePresentation());
    if (id == null) return;
    final selection = _activeScoreTabId;
    final saveTabPage =
        _entry?.id == id &&
        selection != null &&
        _scoreTabIds.contains(selection) &&
        _page == page &&
        _scoreTabPages[selection] != page;
    if (saveTabPage) _scoreTabPages[selection] = page;
    final saveActiveTab =
        opened && _entry?.id == id && _scoreTabIds.contains(selection);
    try {
      await _library.record(id, page, opened: opened);
      if (saveTabPage || saveActiveTab) {
        await _library.updatePreferences({
          if (saveTabPage)
            'scoreTabPages': {
              for (final tab in _scoreTabIds)
                if (_scoreTabPages[tab] case final int page) tab: page,
            },
          if (saveActiveTab &&
              selection == _activeScoreTabId &&
              _scoreTabIds.contains(selection))
            'activeScoreTab': selection,
        });
      }
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
    final pages = _inkSnapshot();
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

  Map<String, dynamic> _inkSnapshot() {
    final pages = <String, dynamic>{};
    if (_inkLayers.length != 1 ||
        _inkLayers.single != defaultInkLayer ||
        _activeInkLayer != defaultInkLayer.id) {
      pages['layers'] = [
        for (final layer in _inkLayers)
          {
            'id': layer.id,
            'name': layer.name,
            'visible': layer.visible,
            if (layer.id == _activeInkLayer) 'active': true,
          },
      ];
    }
    for (final MapEntry(key: page, value: ink) in _ink.entries) {
      final strokes = ink.snapshot();
      if (strokes.isNotEmpty) pages['$page'] = strokes;
    }
    return pages;
  }

  Future<void> _showPdfExport() async {
    final source = _file;
    if (_picking || source == null || _pages == 0) return;
    setState(() => _picking = true);
    try {
      await _openReaderPanel<void>(
        (_) => PdfExportScreen(
          source: source,
          title: _title,
          firstPage: _firstPage,
          lastPage: _lastPage,
          pageCount: _pages,
          annotations: _inkSnapshot(),
        ),
      );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _shareEditableScore() async {
    final entry = _entry;
    if (_picking || entry == null || !_viewer.isReady) return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _picking = true);
    try {
      final days = await showDialog<int>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Editable score access'),
          children: [
            for (final (days, label) in const [
              (0, 'No expiration'),
              (1, 'Expires in 1 day'),
              (7, 'Expires in 7 days'),
              (30, 'Expires in 30 days'),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, days),
                child: Text(label),
              ),
          ],
        ),
      );
      if (!mounted || days == null || entry.expired) return;
      final requested = days == 0
          ? null
          : DateTime.now().toUtc().add(Duration(days: days));
      final existing = entry.validUntil;
      final expiration =
          existing != null &&
              (requested == null || existing.isBefore(requested))
          ? existing
          : requested;
      final shared = entry.copyWith(validUntil: expiration);
      final bookmark = _itemBookmark;
      final XFile package;
      if (bookmark == null) {
        package = await _library.createScorePackage(shared);
      } else {
        final source = _viewer.document;
        final pages = [
          for (var page = _firstPage; page <= _lastPage; page++)
            EditedPdfPage(source.pages[page - 1], originalPage: page),
        ];
        final extracted = await writeRearrangedPdf('Excerpt.pdf', pages);
        final remapped = remapScorePages(shared, _inkSnapshot(), pages);
        package = await _library.createScorePackage(
          remapped.score.copyWith(title: bookmark.title, page: 1),
          extractedPdf: extracted,
          extractedInk: remapped.annotations,
        );
      }
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(files: [package], sharePositionOrigin: origin),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share the editable score.')),
        );
    } finally {
      _finishPicking();
    }
  }

  void _checkScoreExpiry() {
    _scoreExpiry?.cancel();
    final score = _entry;
    final expiry = score?.validUntil;
    if (!mounted || score == null || expiry == null) return;
    final remaining = expiry.difference(DateTime.now());
    if (remaining > Duration.zero) {
      _scoreExpiry = Timer(
        remaining > const Duration(minutes: 1)
            ? const Duration(minutes: 1)
            : remaining,
        _checkScoreExpiry,
      );
      return;
    }
    _playing = null;
    _load(null, null, null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This shared score has expired.')),
    );
  }

  void _load(
    ScoreEntry? entry,
    XFile? file,
    Uint8List? bytes, {
    Map<String, dynamic> annotations = const {},
    String? tabInstance,
    int? startPage,
    ScoreBookmark? item,
  }) {
    if (!_autoScrollAdvancing) _stopAutoScroll(rebuild: false);
    _scoreExpiry?.cancel();
    final scoreChanged = _entry?.id != entry?.id;
    final audio = _scoreAudio;
    _stopAudioCues();
    _meterPage = null;
    if (audio != null && audio.pinnedSelection == null) {
      unawaited(audio.stop().catchError((Object _) {}));
    }
    final meter = _metronome;
    if (meter != null && meter.running && _entry?.id != entry?.id) {
      unawaited(meter.stop().catchError((Object _) {}));
    }
    if (_entry case final current?
        when current.id != entry?.id && _library.lookup(current.id) != null) {
      _previousItem = (id: current.id, page: _page);
    }
    final savedLayers = annotations['layers'];
    final layers = <InkLayer>[
      if (savedLayers is List)
        for (final layer in savedLayers)
          if (layer case {
            'id': final String id,
            'name': final String name,
            'visible': final bool visible,
          })
            (id: id, name: name, visible: visible),
    ];
    if (layers.isEmpty) layers.add(defaultInkLayer);
    final visible = [
      for (final layer in layers)
        if (layer.visible) layer.id,
    ];
    final nomination = savedLayers is List
        ? savedLayers
              .whereType<Map>()
              .where((layer) => layer['active'] == true)
              .firstOrNull
        : null;
    final nominated = nomination?['id'] ?? defaultInkLayer.id;
    final active =
        visible.where((id) => id == nominated).firstOrNull ??
        visible.firstOrNull;
    final restoredInk = {
      for (final MapEntry(key: page, value: strokes) in annotations.entries)
        if (int.tryParse(page) case final pageNumber?)
          pageNumber: PageInk(
            saved: strokes as List<dynamic>,
            onChanged: _saveInk,
            activeLayer: active,
            visibleLayers: visible,
          ),
    };
    final retiredInk = _ink.values.toList();
    setState(() {
      _entry = entry;
      _itemBookmark = item;
      _selectedTabInstance = tabInstance;
      _halfPreview = false;
      _file = file;
      _stylusDrawing = false;
      _lastReaderPointerStylus = false;
      _bytes = bytes;
      _revision++;
      _viewer = PdfViewerController();
      _ink.clear();
      _ink.addAll(restoredInk);
      _inkLayers = layers;
      _activeInkLayer = active;
      _page = _initialPage = startPage ?? entry?.page ?? 1;
      _previousPage = null;
      _pages = 0;
      _seek = null;
      _inking = false;
      _annotationPage = null;
      _selectingPdf = false;
      _placingMeasure = false;
      _pdfSelection = [];
      _pdfSelectionPage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ink in retiredInk) {
        ink.dispose();
      }
    });
    if (scoreChanged && entry != null && ScoreAudioSession.supported) {
      unawaited(_sendScoreMidi(entry).catchError((Object _) {}));
    }
    _focusPractice();
    if (entry?.validUntil != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkScoreExpiry());
    }
    if (_presenting) unawaited(_updatePresentation());
  }

  PageInk _newPageInk() => PageInk(
    onChanged: _saveInk,
    activeLayer: _activeInkLayer,
    visibleLayers: [
      for (final layer in _inkLayers)
        if (layer.visible) layer.id,
    ],
  );

  Future<void> _showInkLayers() async {
    final revision = _revision;
    final canTransfer =
        _entry != null &&
        _entry?.validUntil == null &&
        _pages > 0 &&
        !_restricted(RestrictedTool.transfers);
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => InkLayersDialog(
        layers: _inkLayers,
        active: _activeInkLayer,
        onShare: canTransfer ? _shareInkLayer : null,
        canSelectPdf: _pdfSelectionAvailable,
        pdfSelected: _selectingPdf && _tool == InkTool.selection,
      ),
    );
    if (!mounted || revision != _revision) return;
    if (result == 'pdf') {
      _selectPdf();
      return;
    }
    if (result == 'import') {
      await _importInkLayer();
      return;
    }
    if (result is! InkLayerSettings) return;
    final settings = result;
    final visible = [
      for (final layer in settings.layers)
        if (layer.visible) layer.id,
    ];
    setState(() {
      _selectingPdf = false;
      _placingMeasure = false;
      _pdfSelection = [];
      _pdfSelectionPage = null;
      _inkLayers = settings.layers;
      _activeInkLayer = settings.active;
    });
    for (final ink in _ink.values) {
      ink.configureLayers(
        active: settings.active,
        visible: visible,
        changes: settings.changes,
      );
    }
    await _saveInk();
  }

  Future<String> _inkScoreDigest() async {
    final bytes = _bytes ?? await _file!.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  void _inkTransferError(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error is FormatException ? error.message : fallback),
      ),
    );
  }

  Future<void> _shareInkLayer(InkLayer layer) async {
    if (_entry == null ||
        _entry?.validUntil != null ||
        _restricted(RestrictedTool.transfers))
      return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final snapshot = _inkSnapshot();
    try {
      final bytes = encodeInkLayer(layer, await _inkScoreDigest(), snapshot);
      if (bytes.length > maxInkLayerBytes) {
        throw const FormatException('The annotation layer is too large.');
      }
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: ['Annotation layer.$inkLayerExtension'],
          sharePositionOrigin: origin,
        ),
      );
    } catch (error) {
      _inkTransferError(error, 'Could not share the annotation layer.');
    }
  }

  Future<void> _importInkLayer() async {
    final entry = _entry;
    if (entry == null ||
        entry.validUntil != null ||
        _restricted(RestrictedTool.transfers) ||
        _picking ||
        _pages == 0)
      return;
    final revision = _revision;
    setState(() => _picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Annotation layers',
            extensions: ['json'],
            mimeTypes: ['application/json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null || !mounted || revision != _revision) return;
      if (await file.length() > maxInkLayerBytes) {
        throw const FormatException('The annotation layer is too large.');
      }
      final layerId = 'imported-${DateTime.now().microsecondsSinceEpoch}';
      final layer = decodeInkLayer(
        await file.readAsBytes(),
        scoreDigest: await _inkScoreDigest(),
        pageCount: _pages,
        layerId: layerId,
      );
      if (!mounted || revision != _revision) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Import annotation layer'),
          content: Text('Add “${layer.name}” to “${entry.title}”?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || revision != _revision) return;
      final layers = [
        ..._inkLayers,
        (id: layerId, name: layer.name, visible: true),
      ];
      final visible = [
        for (final layer in layers)
          if (layer.visible) layer.id,
      ];
      final snapshot = _inkSnapshot();
      snapshot['layers'] = [
        for (final layer in layers)
          {
            'id': layer.id,
            'name': layer.name,
            'visible': layer.visible,
            if (layer.id == layerId) 'active': true,
          },
      ];
      for (final page in layer.pages.entries) {
        snapshot['${page.key}'] = [
          ...?_ink[page.key]?.snapshot(),
          ...page.value,
        ];
      }
      await _library.writeInk(entry.id, snapshot);
      if (!mounted || revision != _revision) return;
      final retired = <PageInk>[];
      setState(() {
        _inkLayers = layers;
        _activeInkLayer = layerId;
        for (final page in layer.pages.keys) {
          if (_ink[page] case final previous?) retired.add(previous);
          _ink[page] = PageInk(
            saved: snapshot['$page'] as List<dynamic>,
            onChanged: _saveInk,
            activeLayer: layerId,
            visibleLayers: visible,
          );
        }
        for (final page in _ink.keys.where(
          (page) => !layer.pages.containsKey(page),
        )) {
          _ink[page]!.configureLayers(
            active: layerId,
            visible: visible,
            changes: [],
          );
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final ink in retired) {
          ink.dispose();
        }
      });
    } catch (error) {
      _inkTransferError(error, 'Could not import the annotation layer.');
    } finally {
      _finishPicking();
    }
  }

  void _go(int page, {bool backwardTurn = false}) {
    if (_pageNavigationBlocked || !_viewer.isReady || _pages == 0) return;
    if (page > _lastPage && _hasNextScore) {
      _nextScore();
      return;
    }
    if (backwardTurn && page < _firstPage && _hasPreviousScore) {
      _stepSetlist(-1);
      return;
    }
    _jumpToPage(page);
  }

  void _turn(int step) {
    if (_pageNavigationBlocked || !_viewer.isReady || _pages == 0) return;
    _stopAutoScroll();
    if (_ensemble?.leading == true && _leadingSpread) {
      _go(_page - (_page - _firstPage) % 2 + step * 2, backwardTurn: step < 0);
      return;
    }
    if (_verticalScrolling && !_inking) {
      _turnVertical(step);
      return;
    }
    if (_spreadStep == 3) {
      final first = _page - (_page - 1) % 3;
      final target = first + step * 3;
      if (target <= _lastPage || _hasNextScore) {
        _go(target, backwardTurn: step < 0);
      }
      return;
    }
    if (_spreadStep > 0) {
      _go(_page + step * _spreadStep, backwardTurn: step < 0);
      return;
    }
    if (_readingAtWidth && !_inking && _turnPageSection(step)) return;
    if (!_halfPageTurns || _inking) {
      _go(_page + step, backwardTurn: step < 0);
      return;
    }
    if (step < 0 && _page == _firstPage && !_halfPreview && _hasPreviousScore) {
      _stepSetlist(-1);
      return;
    }
    final turn = advanceHalfTurn(
      page: _page,
      first: _firstPage,
      last: _lastPage,
      preview: _halfPreview,
      step: step,
    );
    if (turn.page != _page) _go(turn.page);
    if (_halfPreview != turn.preview)
      setState(() => _halfPreview = turn.preview);
  }

  bool get _canThreeUp {
    final view = MediaQuery.sizeOf(context);
    final width = view.width - (_wideReaderDock ? _dockWidth : 0);
    return width >= 1120 && width > view.height;
  }

  int get _spreadStep =>
      _verticalScrolling ||
          _inking ||
          _itemBookmark != null ||
          _halfPageTurns ||
          _ensemble?.leading == true && _leadingSpread ||
          _followingSpread
      ? 0
      : _preferences.spreadStep == 3 && !_canThreeUp
      ? 0
      : _preferences.spreadStep;

  ReaderScrollMode get _scrollMode =>
      _entry?.scrollMode ?? _preferences.scrollMode;

  bool get _verticalScrolling =>
      _scrollMode != ReaderScrollMode.paged &&
      !_followingSpread &&
      !(_ensemble?.leading == true && _leadingSpread);

  bool get _halfPageTurns => !_verticalScrolling && _preferences.halfPageTurns;

  bool get _canAutoScroll =>
      _verticalScrolling &&
      !_inking &&
      !_stylusDrawing &&
      _pages > 0 &&
      _viewer.isReady;

  void _stopAutoScroll({bool rebuild = true}) {
    if (!_autoScrollTicker.isActive) return;
    _autoScrollTicker.stop();
    if (mounted && rebuild) setState(() {});
  }

  void _toggleAutoScroll() {
    if (_autoScrollTicker.isActive) {
      _stopAutoScroll();
    } else if (_canAutoScroll && !_picking) {
      _autoScrollLast = _autoScrollAtEnd = Duration.zero;
      setState(() {
        _autoScrollTicker.start();
      });
    }
    _focus.requestFocus();
  }

  void _tickAutoScroll(Duration elapsed) {
    final delta = elapsed - _autoScrollLast;
    _autoScrollLast = elapsed;
    if (delta <= Duration.zero || _picking || _autoScrollAdvancing) return;
    if (!_verticalScrolling || _inking || _stylusDrawing) {
      _stopAutoScroll();
      return;
    }
    if (!_canAutoScroll) return;
    final frame = delta > const Duration(milliseconds: 50)
        ? const Duration(milliseconds: 50)
        : delta;
    final pixels =
        _viewer.viewSize.height *
        frame.inMicroseconds /
        (_preferences.autoScrollSeconds * Duration.microsecondsPerSecond);
    final current = _viewer.value;
    final offset = current.storage[13];
    final target = current.clone()..setEntry(1, 3, offset - pixels);
    final clamped = _viewer.makeMatrixInSafeRange(target, forceClamp: true);
    if ((clamped.storage[13] - offset).abs() > .001) {
      _autoScrollAtEnd = Duration.zero;
      _viewer.value = clamped;
      return;
    }
    if (!_preferences.autoScrollSetlist || !_hasNextScore) {
      _stopAutoScroll();
      return;
    }
    _autoScrollAtEnd += frame;
    if (_autoScrollAtEnd < const Duration(seconds: 4)) return;
    _autoScrollAtEnd = Duration.zero;
    _autoScrollAdvancing = true;
    final revision = _revision;
    unawaited(
      _nextScore().whenComplete(() {
        _autoScrollAdvancing = false;
        if (mounted && (revision == _revision || !_verticalScrolling)) {
          _stopAutoScroll();
        }
      }),
    );
  }

  Future<void> _showAutoScroll() async {
    if (!_canAutoScroll || _picking) return;
    var seconds = _preferences.autoScrollSeconds;
    var advance = _preferences.autoScrollSetlist;
    final running = _autoScrollTicker.isActive;
    setState(() => _picking = true);
    var start = false;
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Automatic scrolling'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$seconds seconds per screen'),
                Slider(
                  min: 5,
                  max: 60,
                  divisions: 55,
                  value: seconds.toDouble(),
                  onChanged: (value) => update(() => seconds = value.round()),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('Faster'), Text('Slower')],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Continue to the next setlist score'),
                  subtitle: const Text(
                    'Wait 4 seconds at the end of each score.',
                  ),
                  value: advance,
                  onChanged: (value) => update(() => advance = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(running ? 'Save' : 'Start scrolling'),
              ),
            ],
          ),
        ),
      );
      if (save != true || !mounted) return;
      await _savePreferences(
        _preferences.copyWith(
          autoScrollSeconds: seconds,
          autoScrollSetlist: advance,
        ),
      );
      start = !running;
    } finally {
      _finishPicking();
    }
    if (mounted && start) _toggleAutoScroll();
  }

  void _adjustAutoScrollSpeed(int step) {
    final seconds = (_preferences.autoScrollSeconds + step).clamp(5, 60);
    if (seconds == _preferences.autoScrollSeconds) return;
    setState(
      () => _preferences = _preferences.copyWith(autoScrollSeconds: seconds),
    );
    unawaited(
      _library.updatePreferences({'autoScrollSeconds': seconds}).catchError((
        Object _,
      ) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save the scrolling speed.'),
            ),
          );
      }),
    );
    _focus.requestFocus();
  }

  Widget _activeScrollControls() => Material(
    color: _rail,
    borderRadius: BorderRadius.circular(24),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Scroll slower',
          onPressed: _preferences.autoScrollSeconds >= 60
              ? null
              : () => _adjustAutoScrollSpeed(5),
          icon: const Icon(Icons.remove),
        ),
        IconButton.filledTonal(
          tooltip: 'Stop automatic scrolling',
          onPressed: _stopAutoScroll,
          icon: const Icon(Icons.pause),
        ),
        IconButton(
          tooltip: 'Scroll faster',
          onPressed: _preferences.autoScrollSeconds <= 5
              ? null
              : () => _adjustAutoScrollSpeed(-5),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );

  void _resetScoreLayout() {
    _stopAutoScroll(rebuild: false);
    _initialPage = _page;
    _halfPreview = false;
    _annotationPage = null;
    _revision++;
    _viewer = PdfViewerController();
    _pages = 0;
    _seek = null;
  }

  PageCrop? _cropFor(int page) => _entry?.crops[page];

  bool _fitCrop(int page, PdfViewerController controller) {
    final crop = _cropFor(page);
    if (crop == null ||
        _verticalScrolling ||
        _spreadStep > 0 ||
        !controller.isReady) {
      return false;
    }
    final bounds = crop.pdfBounds(controller.document.pages[page - 1]);
    if (_readingAtWidth) {
      final visible = controller.calcRectForRectInsidePage(
        pageNumber: page,
        rect: bounds,
      );
      final zoom = math.max(1, controller.viewSize.width - 24) / visible.width;
      controller.goToPosition(
        documentOffset: Offset(
          visible.left - 12 / zoom,
          visible.top - 12 / zoom,
        ),
        zoom: zoom,
      );
      return true;
    }
    controller.goToRectInsidePage(
      pageNumber: page,
      rect: bounds,
      anchor: PdfPageAnchor.center,
      duration: Duration.zero,
    );
    return true;
  }

  bool get _readingAtWidth =>
      !_verticalScrolling &&
      _spreadStep == 0 &&
      !_halfPageTurns &&
      (_preferences.pageFit == ReaderPageFit.zoomed ||
          _preferences.pageFit == ReaderPageFit.standard &&
              _preferences.landscapeWidth &&
              MediaQuery.orientationOf(context) == Orientation.landscape);

  void _turnVertical(int step) {
    final visible = _viewer.visibleRect;
    if (step < 0 && visible.top <= 1 && _hasPreviousScore) {
      _stepSetlist(-1);
      return;
    }
    final bottom = math.max(
      0.0,
      _viewer.layout.documentSize.height - visible.height,
    );
    if (step > 0 && visible.top >= bottom - 1 && _hasNextScore) {
      _nextScore();
      return;
    }
    final target = (visible.top + visible.height * .85 * step).clamp(
      0.0,
      bottom,
    );
    unawaited(
      _viewer.goToPosition(
        documentOffset: Offset(visible.left, target),
        duration: _appearance.animateTurns
            ? const Duration(milliseconds: 140)
            : Duration.zero,
      ),
    );
  }

  bool _turnPageSection(int step) {
    final visible = _viewer.visibleRect;
    final fullPage = _viewer.layout.pageLayouts[_page - 1];
    final page = _cropFor(_page)?.within(fullPage) ?? fullPage;
    final bottom = page.bottom - visible.height;
    if (bottom <= page.top) return false;
    if (step < 0 && visible.top <= page.top + 1 ||
        step > 0 && visible.top >= bottom - 1) {
      return false;
    }
    final target = (visible.top + visible.height * .88 * step).clamp(
      page.top,
      bottom,
    );
    if ((target - visible.top).abs() < 1) return false;
    _viewer.goToPosition(documentOffset: Offset(visible.left, target));
    return true;
  }

  void _jumpToPage(int page) {
    if (!_viewer.isReady || _pages == 0) return;
    final target = page.clamp(_firstPage, _lastPage);
    if (target == _page) {
      if (_halfPreview) setState(() => _halfPreview = false);
      if (_verticalScrolling) _positionVerticalPage(_viewer, target);
      return;
    }
    _ink[_annotationPage ?? _page]?.finish(commit: false);
    final wasCropped = _cropFor(_page) != null;
    _previousPage = _page;
    _pedalButton = null;
    setState(() {
      _page = target;
      _annotationPage = null;
      _pdfSelection = [];
      _pdfSelectionPage = null;
      _halfPreview = false;
    });
    if (_verticalScrolling) {
      _positionVerticalPage(_viewer, target);
    } else if (_spreadStep == 1) {
      final viewer = _viewer;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewer == viewer && viewer.isReady && _page == target) {
          viewer.goToPage(pageNumber: target, duration: Duration.zero);
        }
      });
    } else if (!_fitCrop(target, _viewer)) {
      if (wasCropped && _spreadStep == 0) {
        _viewer.goTo(
          _viewer.calcMatrixForFit(pageNumber: target),
          duration: Duration.zero,
        );
      } else {
        _viewer.goToPage(pageNumber: target, duration: Duration.zero);
      }
    }
    _remember(_entry?.id, target);
    _recordAudioCue(target);
  }

  Future<void> _returnToPreviousScore() async {
    final previous = _previousItem;
    if (previous == null || _picking) return;
    setState(() => _picking = true);
    try {
      final id = previous.id;
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
    final binding = _shortcuts[shortcutKey(key)];
    if (binding != null && !_picking && _pages > 0) {
      if (event is KeyDownEvent) _runShortcut(binding);
      return KeyEventResult.handled;
    }
    final step = pageTurnForKey(key);
    if (step == 0 || _pageNavigationBlocked || _pages == 0)
      return KeyEventResult.ignored;
    if (event is KeyDownEvent) _turn(step);
    return KeyEventResult.handled;
  }

  void _listenToMidi() {
    if (!ScoreAudioSession.supported || _midiInput != null) return;
    final stream = _midi.onMidiPacketReceived;
    _midiInput = stream?.listen((packet) {
      if (!mounted || _restricted(RestrictedTool.connections)) return;
      final bytes = packet.data;
      if (_midiPiano &&
          bytes.length == 3 &&
          bytes[0] & 0xf0 == 0x90 &&
          bytes[2] > 0) {
        final piano = _piano ??= RehearsalPiano();
        unawaited(
          piano.play(bytes[1], velocity: bytes[2]).catchError((Object _) {}),
        );
      }
      if (!_picking && !_inking) {
        final command = midiCommandKey(packet.data);
        final target = _library.recent
            .where((score) => score.metadata['midiOpen'] == command)
            .firstOrNull;
        if (target != null) {
          if (target.id != _entry?.id) unawaited(_openMidiScore(target));
          return;
        }
      }
      final key = shortcutMidi(packet.data);
      if (key != null) _handleControllerShortcut(key);
    }, onError: (Object _) {});
  }

  Future<void> _openMidiScore(ScoreEntry score) async {
    setState(() => _picking = true);
    try {
      await _openLibraryScore(score);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the MIDI-linked score.'),
          ),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _sendScoreMidi(ScoreEntry score) async {
    if (_restricted(RestrictedTool.connections)) return;
    final commands = score.metadata['midiSend'];
    if (commands == null || commands.isEmpty) return;
    final devices = await _midi.devices ?? [];
    if (!mounted || _entry?.id != score.id) return;
    final targets = devices.where((device) => device.connected).toList();
    for (final command in commands.split('\n')) {
      final bytes = ScoreAction.midiBytes(command);
      if (bytes == null) continue;
      final packet = Uint8List.fromList(bytes);
      for (final device in targets) {
        _midi.sendData(packet, deviceId: device.id);
      }
    }
  }

  Future<void> _showMidiAutomation() async {
    final score = _entry;
    if (score == null || _picking) return;
    setState(() => _picking = true);
    try {
      await _editMidiAutomation(score);
    } finally {
      _finishPicking();
    }
  }

  Future<void> _editMidiAutomation(ScoreEntry score) async {
    try {
      final prefs = await _library.storage.readPreferences();
      if (!mounted) return;
      final presets = <String, String>{
        if (prefs['midiCommandPresets'] case final Map values)
          for (final item in values.entries)
            if (item.key is String && item.value is String)
              item.key as String: item.value as String,
      };
      final result = await showDialog<MidiAutomation>(
        context: context,
        builder: (_) => MidiAutomationDialog(
          initial: (
            trigger: score.metadata['midiOpen'] ?? '',
            commands: score.metadata['midiSend'] ?? '',
          ),
          presets: presets,
          savePresets: (value) =>
              _library.updatePreferences({'midiCommandPresets': value}),
        ),
      );
      if (result == null || !mounted) return;
      final duplicate = result.trigger.isEmpty
          ? null
          : _library.recent
                .where(
                  (entry) =>
                      entry.id != score.id &&
                      entry.metadata['midiOpen'] == result.trigger,
                )
                .firstOrNull;
      if (duplicate != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('That MIDI message opens ${duplicate.title}.'),
          ),
        );
        return;
      }
      await _library.updateScore(
        score.id,
        (old) => old.copyWith(
          metadata: {
            ...Map.of(old.metadata)
              ..remove('midiOpen')
              ..remove('midiSend'),
            if (result.trigger.isNotEmpty) 'midiOpen': result.trigger,
            if (result.commands.isNotEmpty) 'midiSend': result.commands,
          },
        ),
      );
      if (mounted && _entry?.id == score.id) {
        setState(() => _entry = _library.lookup(score.id));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save MIDI automation.')),
        );
    }
  }

  Future<void> _showEnsemble() async {
    if (_picking || kIsWeb) return;
    final session = _ensemble ??= EnsembleSession();
    setState(() => _picking = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EnsembleDialog(
          session: session,
          leadingSpread: () => _leadingSpread,
          setLeadingSpread: (value) {
            setState(() => _leadingSpread = value);
            if (value && (_page - _firstPage).isOdd) _jumpToPage(_page - 1);
          },
          lead: () => session.lead(
            () => (
              id: _entry?.id,
              title: _entry?.title ?? _title,
              composer: _entry?.metadata['composer'] ?? '',
              page: _page,
            ),
          ),
          follow: (address, code, mode) async {
            await session.follow(
              address: address,
              code: code,
              hasScore: (position) => _ensembleScore(position) != null,
              onPosition: (position) => _followEnsemble(position, mode),
              onDisconnect: () {
                if (!mounted) return;
                setState(() => _followingSpread = _missingFacingPage = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ensemble session disconnected.'),
                  ),
                );
              },
            );
            if (mounted)
              setState(() {
                _followingSpread = mode == EnsembleFollowMode.facing;
                if (_followingSpread) _showControls = false;
              });
          },
        ),
      );
    } finally {
      if (mounted && !session.following) {
        setState(() => _followingSpread = _missingFacingPage = false);
      }
      _finishPicking();
    }
  }

  Future<void> _openScoreWindow() async {
    final file = _file;
    if (file == null ||
        !_supportsScoreWindows ||
        !_readerActionAllowed(_ReaderDisplay.scoreWindow))
      return;
    final revision = _revision;
    try {
      await _library.flush();
      if (!mounted || revision != _revision) return;
      await const MethodChannel('encoresheets/score-windows')
          .invokeMethod<void>('open', {
            'path': file.path,
            'title': _title,
            'page': _page,
            'library': [
              for (final score in _library.recent)
                if (score.validUntil == null)
                  {
                    'file': score.storedPdfId,
                    'title': score.title,
                    'page': score.page,
                  },
            ],
          });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open another score window.')),
        );
    }
  }

  Future<void> _checkScoreWindowSupport() async {
    try {
      final supported = await const MethodChannel('encoresheets/score-windows')
          .invokeMethod<bool>('isSupported');
      if (mounted && supported == true) {
        setState(() => _appleScoreWindowsSupported = true);
      }
    } on PlatformException {
      // Score windows are optional.
    } on MissingPluginException {
      // The native build does not expose the capability yet.
    }
  }

  Future<void> _togglePresentation() async {
    setState(() => _presenting = !_presenting);
    await _updatePresentation();
  }

  Future<void> _updatePresentation() async {
    final update = ++_presentationUpdate;
    final file = _file;
    try {
      if (_presenting && file != null) {
        await _presentationChannel.invokeMethod<void>('show', {
          'path': file.path,
          'page': _page,
        });
      } else {
        await _presentationChannel.invokeMethod<void>('hide');
      }
    } catch (_) {
      if (!mounted || update != _presentationUpdate) return;
      setState(() => _presenting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the score to a second display.'),
        ),
      );
    }
  }

  bool _matchesEnsembleScore(ScoreEntry score, EnsemblePosition position) =>
      score.title.toLowerCase() == position.title.toLowerCase() &&
      (score.metadata['composer'] ?? '').toLowerCase() ==
          position.composer.toLowerCase();

  ScoreEntry? _ensembleScore(EnsemblePosition position) {
    final exact = position.id == null ? null : _library.lookup(position.id!);
    if (exact != null && _matchesEnsembleScore(exact, position)) return exact;
    final options = _library.recent
        .where((score) => _matchesEnsembleScore(score, position))
        .take(2)
        .toList();
    return options.length == 1 ? options.single : null;
  }

  Future<void> _followEnsemble(
    EnsemblePosition position,
    EnsembleFollowMode mode,
  ) async {
    if (!mounted || _picking || _inking) return;
    final current = _entry;
    final sameScore = current == null
        ? position.id == null
        : _matchesEnsembleScore(current, position);
    final acceptPage = mode != EnsembleFollowMode.scores;
    final facing = mode == EnsembleFollowMode.facing;
    final targetPage = position.page + (facing ? 1 : 0);
    if (!sameScore && mode != EnsembleFollowMode.pages) {
      final target = _ensembleScore(position);
      if (target == null) return;
      final revision = _revision;
      final local = await _library.storage.openScore(target.id);
      final annotations = await _library.readInk(target.id);
      if (!mounted ||
          _picking ||
          _inking ||
          revision != _revision ||
          _ensemble?.following != true)
        return;
      _load(
        target,
        local,
        null,
        annotations: annotations,
        startPage: acceptPage && !facing ? targetPage : null,
      );
      _remember(target.id, _page, opened: true);
    } else if (acceptPage && (sameScore || mode == EnsembleFollowMode.pages)) {
      final missing = facing && _pages > 0 && targetPage > _lastPage;
      if (_missingFacingPage != missing) {
        setState(() => _missingFacingPage = missing);
      }
      if (!missing) _jumpToPage(targetPage);
    }
  }

  void _handleControllerShortcut(String key) {
    if (!mounted || _restricted(RestrictedTool.connections)) return;
    _midiShortcuts.add(key);
    if (_picking || _pages == 0) return;
    final action =
        _shortcuts[key] ??
        switch (key) {
          'turntouch:North' || 'turntouch:West' => ReaderShortcut.previous,
          'turntouch:East' || 'turntouch:South' => ReaderShortcut.next,
          _ => null,
        };
    if (action != null) _runShortcut(action);
  }

  ({String score, int page, int index})? _pedalButton;

  void _runOnPageShortcut({required bool selectNext}) {
    final score = _entry;
    if (score == null || _picking || _inking || !_viewer.isReady) return;
    final actions = score.actions
        .where(
          (action) =>
              action.page == _page &&
              (!_halfPreview || action.y >= _splitFor(_page)),
        )
        .toList();
    if (actions.isEmpty) return;
    final previous = _pedalButton;
    var index = previous?.score == score.id && previous?.page == _page
        ? previous!.index.clamp(0, actions.length - 1)
        : 0;
    if (selectNext) {
      if (previous?.score == score.id && previous?.page == _page) {
        index = (index + 1) % actions.length;
      }
      _pedalButton = (score: score.id, page: _page, index: index);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Selected button: ${actions[index].title}'),
            duration: const Duration(seconds: 1),
          ),
        );
      return;
    }
    _pedalButton = (score: score.id, page: _page, index: index);
    unawaited(_runScoreAction(actions[index]));
  }

  void _runShortcut(ReaderShortcut shortcut) {
    switch (shortcut) {
      case ReaderShortcut.next:
        _turn(1);
      case ReaderShortcut.previous:
        _turn(-1);
      case ReaderShortcut.controls:
        setState(() => _showControls = !_showControls);
      case ReaderShortcut.markup:
        if (!_performance) _toggleInk();
      case ReaderShortcut.audio:
        final score = _entry;
        if (score != null && ScoreAudioSession.supported) {
          final audio = _scoreAudio ??= ScoreAudioSession(_library);
          final selection = _itemBookmark?.selectionId(score.id) ?? score.id;
          unawaited(
            audio
                .toggle(selection)
                .then<void>((_) {})
                .catchError((Object _) {}),
          );
        }
      case ReaderShortcut.autoScroll:
        _toggleAutoScroll();
      case ReaderShortcut.selectOnPageAction:
        _runOnPageShortcut(selectNext: true);
      case ReaderShortcut.activateOnPageAction:
        _runOnPageShortcut(selectNext: false);
    }
  }

  Future<void> _showInputShortcuts() async {
    if (_picking) return;
    _listenToMidi();
    setState(() => _picking = true);
    try {
      final bindings = await showDialog<Map<String, ReaderShortcut>>(
        context: context,
        builder: (_) => ReaderShortcutsDialog(
          initial: _shortcuts,
          midi: _midiShortcuts.stream,
        ),
      );
      if (!mounted || bindings == null) return;
      await _library.updatePreferences({
        'readerShortcuts': {
          for (final entry in bindings.entries) entry.key: entry.value.name,
        },
      });
      if (mounted) setState(() => _shortcuts = bindings);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save input shortcuts.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showMidiDevices() async {
    if (_picking || !_supportsSharedImport) return;
    setState(() => _picking = true);
    try {
      _listenToMidi();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MidiDevicesDialog(
          midi: _midi,
          turnTouch: _turnTouch ??= TurnTouch(_handleControllerShortcut),
        ),
      );
    } finally {
      _finishPicking();
    }
  }

  static const _sepiaTint = Color(0xffffedd1);
  double get _pageTargetRadius => _preferences.largePageButtons ? 32 : 22;
  double get _pageButtonSize => _preferences.largePageButtons ? 52 : 36;

  Future<void> _showAccessibility() async {
    var draft = _preferences;
    final result = await showDialog<ReaderPreferences>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Accessible reader controls'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Full-screen menus'),
                  value: draft.fullScreenPanels,
                  onChanged: (value) => refresh(
                    () => draft = draft.copyWith(fullScreenPanels: value),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Larger links and action buttons'),
                  value: draft.largePageButtons,
                  onChanged: (value) => refresh(
                    () => draft = draft.copyWith(largePageButtons: value),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Double-tap and long-press gestures'),
                  value: draft.complexGestures,
                  onChanged: (value) => refresh(
                    () => draft = draft.copyWith(complexGestures: value),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Softer metronome click'),
                  value: draft.softMetronome,
                  onChanged: (value) => refresh(
                    () => draft = draft.copyWith(softMetronome: value),
                  ),
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
              onPressed: () => Navigator.pop(dialog, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      if (_metronome case final meter?) meter.soft = result.softMetronome;
      await _savePreferences(result);
    }
  }

  Future<void> _showPanelOptions() async {
    var draft = _preferences;
    final result = await showDialog<ReaderPreferences>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Sidebar and lists'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Show sidebar alongside score'),
                value: draft.dockPanels,
                onChanged: (value) => refresh(
                  () => draft = draft.copyWith(
                    dockPanels: value,
                    fullScreenPanels: value ? false : null,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Compact score lists'),
                value: draft.compactLibrary,
                onChanged: (value) => refresh(
                  () => draft = draft.copyWith(compactLibrary: value),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) await _savePreferences(result);
  }

  PdfAnnotationRenderingMode get _embeddedAnnotationMode =>
      switch (_preferences.embeddedPdfContent) {
        EmbeddedPdfContent.all => PdfAnnotationRenderingMode.annotationAndForms,
        EmbeddedPdfContent.annotations => PdfAnnotationRenderingMode.annotation,
        EmbeddedPdfContent.hidden => PdfAnnotationRenderingMode.none,
      };

  Future<void> _showEmbeddedPdfSettings() async {
    var mode = _preferences.embeddedPdfContent;
    var links = _preferences.embeddedPdfLinks;
    final result = await showDialog<(EmbeddedPdfContent, bool)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Embedded PDF content'),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<EmbeddedPdfContent>(
                  isExpanded: true,
                  value: mode,
                  items: [
                    for (final item in EmbeddedPdfContent.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) => refresh(() => mode = value!),
                ),
                SwitchListTile(
                  title: const Text('Follow embedded PDF links'),
                  value: links,
                  onChanged: (value) => refresh(() => links = value),
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
              onPressed: () => Navigator.pop(dialog, (mode, links)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) {
      await _savePreferences(
        _preferences.copyWith(
          embeddedPdfContent: result.$1,
          embeddedPdfLinks: result.$2,
        ),
      );
    }
  }

  Future<void> _showReflow() async {
    if (_picking || !_viewer.isReady || _pages == 0) return;
    final score = _entry;
    final first = _firstPage, last = _lastPage;
    setState(() => _picking = true);
    try {
      final zones = await Navigator.of(context).push<List<ReflowZone>>(
        MaterialPageRoute(
          builder: (_) => ReflowScreen(
            document: _viewer.document,
            first: first,
            last: last,
            initialPage: _page,
            saved: score?.reflowZones ?? const [],
            annotations: _embeddedAnnotationMode,
          ),
        ),
      );
      if (!mounted || zones == null || score == null) return;
      await _library.updateScore(
        score.id,
        (old) => old.copyWith(
          reflowZones: [
            for (final zone in old.reflowZones)
              if (zone.page < first || zone.page > last) zone,
            ...zones,
          ],
        ),
      );
      if (mounted && _entry?.id == score.id)
        setState(() => _entry = _library.lookup(score.id));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open or save score reflow.')),
        );
    } finally {
      _finishPicking();
    }
  }

  Future<void> _showAppearance() async {
    var sepia = _preferences.sepia;
    var dimming = _preferences.pageDimming;
    final result = await showDialog<(bool, double)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Reading appearance'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Sepia pages'),
                  value: sepia,
                  onChanged: (value) => refresh(() => sepia = value),
                ),
                Text('Page dimming · ${(dimming * 100).round()}%'),
                Slider(
                  value: dimming,
                  max: .75,
                  divisions: 15,
                  onChanged: (value) => refresh(() => dimming = value),
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
              onPressed: () => Navigator.pop(dialog, (sepia, dimming)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) {
      await _savePreferences(
        _preferences.copyWith(sepia: result.$1, pageDimming: result.$2),
      );
    }
  }

  Future<void> _editText(int page, Offset position, Size pageSize) async {
    if (_editingText || !_inking) return;
    final ink = _ink[page];
    if (ink == null) return;
    if (_stamp case final stamp?) {
      ink.setText(null, (
        value: stamp,
        position: Offset(
          position.dx.clamp(0.0, .9),
          position.dy.clamp(0.0, .94),
        ),
        size: .048,
      ));
      return;
    }
    final selected = ink.textAt(position, pageSize);
    _editingText = true;
    try {
      final result = await showDialog<({PageText? annotation, bool delete})>(
        context: context,
        builder: (_) => TextAnnotationDialog(
          initial: selected?.$2 ?? (value: '', position: position, size: .024),
          existing: selected != null,
        ),
      );
      if (!mounted || _ink[page] != ink || result == null) return;
      if (result.delete || result.annotation != null) {
        ink.setText(selected?.$1, result.annotation);
      }
    } finally {
      _editingText = false;
    }
  }

  Future<void> _selectStamp(String stamp) async {
    if (stamp.isEmpty) {
      var draft = '';
      final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Personal stamp'),
          content: TextField(
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Symbol or short text',
            ),
            onChanged: (value) => draft = value.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || value == null || value.isEmpty) return;
      stamp = value;
      if (!_personalStamps.contains(stamp)) {
        final next = [..._personalStamps, stamp];
        try {
          await _library.updatePreferences({'personalStamps': next});
          if (!mounted) return;
          _personalStamps = next;
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not save the personal stamp.'),
              ),
            );
          return;
        }
      }
    }
    setState(() {
      _stamp = stamp;
      _shape = null;
      _tool = InkTool.text;
    });
  }

  void _toggleInk() {
    if (_pages == 0 || _restricted(RestrictedTool.markup)) return;
    _stopAutoScroll(rebuild: false);
    _ink[_annotationPage ?? _page]?.finish(commit: false);
    setState(() {
      _inking = !_inking;
      _selectingPdf = false;
      _placingMeasure = false;
      _pdfSelection = [];
      _pdfSelectionPage = null;
      _fingerDrawingOverride = null;
      if (!_inking) _annotationPage = null;
      _halfPreview = false;
    });
    _focus.requestFocus();
  }

  void _switchStylusTool() {
    if (!_drawing.switchTools || _performance || _picking || _pages == 0)
      return;
    if (!_inking && _autoStylus) _toggleInk();
    if (!_inking) return;
    setState(() {
      _tool = _tool == InkTool.eraser ? InkTool.pen : InkTool.eraser;
      _stamp = null;
      _shape = null;
    });
  }

  void _stylusStarted() {
    if (!_stylusDrawing) setState(() => _stylusDrawing = true);
  }

  void _stylusFinished(bool commit) {
    if (!mounted || !_stylusDrawing) return;
    setState(() {
      _stylusDrawing = false;
      _recentStylus?.cancel();
      _recentStylus = Timer(const Duration(minutes: 15), () {
        if (mounted) setState(() => _recentStylus = null);
      });
    });
    if (!commit || _picking || _performance) return;
    if (_inking && _drawing.autoExit ||
        !_inking && _autoStylus && !_drawing.autoExit) {
      _toggleInk();
    }
  }

  Future<void> _saveDrawing(DrawingSettings settings) async {
    try {
      await _library.updatePreferences({'drawingSettings': settings.toJson()});
      if (mounted) setState(() => _drawing = settings);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the drawing settings.')),
        );
    }
  }

  Future<void> _configureDrawing() async {
    final settings = await showDialog<DrawingSettings>(
      context: context,
      builder: (_) => DrawingSettingsDialog(initial: _drawing),
    );
    if (settings != null && mounted) await _saveDrawing(settings);
  }

  void _fit() {
    if (!_viewer.isReady) return;
    if (_verticalScrolling) {
      _positionVerticalPage(_viewer, _page, resetZoom: true);
    } else if (!_fitCrop(_page, _viewer)) {
      if (_readingAtWidth) {
        _viewer.goToPage(
          pageNumber: _page,
          anchor: PdfPageAnchor.topCenter,
          duration: Duration.zero,
        );
      } else {
        _viewer.goTo(_viewer.calcMatrixForFit(pageNumber: _page));
      }
    }
    _focus.requestFocus();
  }

  void _positionVerticalPage(
    PdfViewerController controller,
    int page, {
    bool resetZoom = false,
  }) {
    final layout = controller.layout;
    final zoom = resetZoom ? controller.coverScale : controller.currentZoom;
    final center = resetZoom
        ? layout.documentSize.width / 2 - controller.viewSize.width / (2 * zoom)
        : controller.visibleRect.left;
    unawaited(
      controller.goToPosition(
        documentOffset: Offset(
          center,
          layout.pageLayouts[page - 1].top - layout.margin,
        ),
        zoom: zoom,
      ),
    );
  }

  Future<void> _chooseScrollMode() async {
    final scoreId = _entry?.id;
    final selected = await showDialog<(bool, ReaderScrollMode?)>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Scrolling display'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Text('Default for scores'),
          ),
          for (final mode in ReaderScrollMode.values)
            ListTile(
              title: Text(mode.label),
              selected: _preferences.scrollMode == mode,
              onTap: () => Navigator.pop(dialog, (false, mode)),
            ),
          if (scoreId != null) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text('Override for this score'),
            ),
            ListTile(
              title: const Text('Use default'),
              selected: _entry?.scrollMode == null,
              onTap: () => Navigator.pop(dialog, (true, null)),
            ),
            for (final mode in ReaderScrollMode.values)
              ListTile(
                title: Text(mode.label),
                selected: _entry?.scrollMode == mode,
                onTap: () => Navigator.pop(dialog, (true, mode)),
              ),
          ],
        ],
      ),
    );
    if (!mounted || selected == null) return;
    final (override, mode) = selected;
    await _setScrollMode(mode, scoreId: override ? scoreId : null);
  }

  Future<void> _setScrollMode(ReaderScrollMode? mode, {String? scoreId}) async {
    if (scoreId == null) {
      if (mode != null && mode != _preferences.scrollMode) {
        await _savePreferences(_preferences.copyWith(scrollMode: mode));
      }
      return;
    }
    if (_entry?.id != scoreId || _entry?.scrollMode == mode) {
      return;
    }
    try {
      await _library.updateScore(
        scoreId,
        (score) =>
            score.copyWith(scrollMode: mode, inheritScrollMode: mode == null),
      );
      if (!mounted || _entry?.id != scoreId) return;
      final previousMode = _scrollMode;
      setState(() {
        _entry = _library.lookup(scoreId);
        if (previousMode != _scrollMode) _resetScoreLayout();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the score display.')),
        );
      }
    }
  }

  Future<void> _quickFit(bool width) async {
    if (_verticalScrolling) {
      final mode = width ? ReaderScrollMode.fitWidth : ReaderScrollMode.fitPage;
      if (mode == _scrollMode) {
        _fit();
      } else {
        await _setScrollMode(mode, scoreId: _entry?.id);
      }
      return;
    }
    final fit = width ? ReaderPageFit.zoomed : ReaderPageFit.bestFit;
    if (fit == _preferences.pageFit) {
      _fit();
    } else {
      await _savePreferences(_preferences.copyWith(pageFit: fit));
    }
  }

  Future<void> _choosePageFit() async {
    final mode = await showDialog<ReaderPageFit>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Page fitting'),
        children: [
          for (final mode in ReaderPageFit.values)
            ListTile(
              title: Text(mode.label),
              subtitle: Text(mode.explanation),
              selected: mode == _preferences.pageFit,
              onTap: () => Navigator.pop(dialog, mode),
            ),
        ],
      ),
    );
    if (mounted && mode != null && mode != _preferences.pageFit) {
      await _savePreferences(_preferences.copyWith(pageFit: mode));
    }
  }

  Future<void> _showCrop() async {
    final score = _entry;
    if (_picking || score == null || !_viewer.isReady || _pages == 0) return;
    final current = _page;
    final document = _viewer.document;
    setState(() => _picking = true);
    try {
      final result = await showDialog<PageCropResult>(
        context: context,
        builder: (_) => PageCropDialog(
          pages: document.pages,
          startPage: current,
          initial: score.crops,
        ),
      );
      if (result == null || !mounted) return;
      final (:scope, :crop, :drafts) = result;
      final next = Map.of(score.crops);
      void save(int page, PageCrop value) {
        if (value.isIdentity) {
          next.remove(page);
        } else {
          next[page] = value;
        }
      }

      switch (scope) {
        case PageCropScope.current:
          drafts.forEach(save);
        case PageCropScope.allLikeCurrent:
          for (var page = 1; page <= document.pages.length; page++) {
            save(page, crop);
          }
        case PageCropScope.autoAll:
          for (final page in document.pages) {
            if (!mounted) return;
            final detected = await detectPageMargins(page);
            save(
              page.pageNumber,
              detected.copyWith(angle: next[page.pageNumber]?.angle),
            );
          }
        case PageCropScope.resetAll:
          next.clear();
      }
      await _library.saveCrop(score.id, next);
      if (!mounted || _entry?.id != score.id) return;
      setState(() => _entry = _library.lookup(score.id));
      _fit();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply the page crop.')),
        );
    } finally {
      _finishPicking();
    }
  }

  double _splitFor(int page) => _entry?.halfSplits[page] ?? .5;

  Future<void> _setHalfSplit() async {
    final page = _page;
    final scoreId = _entry?.id;
    if (scoreId == null) return;
    var fraction = _splitFor(page);
    final selected = await showDialog<double>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: Text('Page $page split'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reveal the top ${(fraction * 100).round()}% of the next page',
              ),
              Slider(
                min: .2,
                max: .8,
                divisions: 12,
                value: fraction,
                onChanged: (value) => refresh(() => fraction = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, fraction),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted || scoreId != _entry?.id) return;
    try {
      await _library.updateScore(
        scoreId,
        (old) => old.copyWith(halfSplits: {...old.halfSplits, page: selected}),
      );
      if (mounted && _entry?.id == scoreId)
        setState(() => _entry = _library.lookup(scoreId));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the page split.')),
        );
    }
  }

  Widget? _previewBand() {
    if (!_halfPageTurns ||
        _inking ||
        !_viewer.isReady ||
        _pages == 0 ||
        _page >= _lastPage)
      return null;
    final rect = _viewer.layout.pageLayouts[_page - 1];
    final topLeft = _viewer.documentToLocal(rect.topLeft);
    final bottomRight = _viewer.documentToLocal(rect.bottomRight);
    final delta = bottomRight - topLeft;
    final size = Size(delta.dx, delta.dy);
    if (size.isEmpty) return null;
    final next = _page + 1;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: size.width,
      height: size.height * _splitFor(_page),
      child: IgnorePointer(
        child: Opacity(
          opacity: _halfPreview ? 1 : 0,
          child: HalfPageBand(
            key: ValueKey(next),
            document: _viewer.document,
            page: next,
            fullSize: size,
            indicator: _preferences.halfPageIndicator,
            tint: _preferences.sepia ? _sepiaTint : Colors.white,
            dimming: _preferences.pageDimming,
            annotations: _embeddedAnnotationMode,
            overlay: InkSurface(
              ink: _ink.putIfAbsent(next, _newPageInk),
              enabled: false,
              allowFinger: false,
              tool: InkTool.pen,
            ),
          ),
        ),
      ),
    );
  }

  Widget _score() {
    final file = _file;
    if (file == null) {
      return Center(
        child: _openingFirstScore
            ? const CircularProgressIndicator()
            : FilledButton.icon(
                onPressed: _picking ? null : _showLibrary,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(ReaderText.library.of(context)),
              ),
      );
    }
    final revision = _revision;
    final markupHandlesGestures =
        _inking &&
        (_allowFinger || _selectingPdf && _tool == InkTool.selection);
    final pageBeforeResize = _page;
    final vertical = _verticalScrolling;
    final scrollLayout = SequentialPagesLayout(
      fitMode: _scrollMode == ReaderScrollMode.fitWidth
          ? PdfFitMode.fill
          : PdfFitMode.fit,
      margin: 12,
    );
    final item = _itemBookmark;
    final params = PdfViewerParams(
      backgroundColor: _stand,
      layoutStrategy: vertical
          ? item != null && item.endPage != null
                ? VerticalExcerptLayout(scrollLayout, item.page, item.endPage!)
                : scrollLayout
          : _spreadStep == 3
          ? const ThreePageLayout()
          : _spreadStep > 0
          ? FacingPagesLayout(
              coverPage: _spreadStep == 1 && _page.isEven,
              fitMode: PdfFitMode.fit,
              singlePagesFillAvailableWidth: true,
            )
          : _readingAtWidth
          ? const SequentialPagesLayout(fitMode: PdfFitMode.fill, margin: 12)
          : SequentialPagesLayout(
              scrollDirection: Axis.horizontal,
              fitMode: PdfFitMode.fit,
              margin: _preferences.pageFit == ReaderPageFit.bestFit ? 3 : 12,
            ),
      paging: vertical
          ? null
          : PdfPaging(
              duration: _appearance.animateTurns
                  ? const Duration(milliseconds: 140)
                  : Duration.zero,
            ),
      calculateCurrentPageNumber: vertical
          ? (visible, pages, _) {
              if (pages.isEmpty) return null;
              final first = (item?.page ?? 1).clamp(1, pages.length);
              return verticalPageAt(
                visible,
                pages,
                first: first,
                last: (item?.endPage ?? pages.length).clamp(
                  first,
                  pages.length,
                ),
              );
            }
          : _spreadStep == 0
          ? null
          : (visible, pages, controller) {
              for (final spread in controller.layout.spreads) {
                final first = pages[spread.firstPageNumber - 1];
                final last = pages[spread.lastPageNumber - 1];
                final bounds = first.expandToInclude(last);
                if (bounds.top <= visible.center.dy &&
                    bounds.bottom >= visible.center.dy) {
                  return spread.firstPageNumber;
                }
              }
              return _page;
            },
      pageAnchor: vertical || _readingAtWidth
          ? PdfPageAnchor.topCenter
          : PdfPageAnchor.center,
      pageAnchorEnd: vertical ? PdfPageAnchor.topCenter : PdfPageAnchor.bottom,
      pageDropShadow: const BoxShadow(
        color: Colors.black54,
        blurRadius: 14,
        offset: Offset(0, 6),
      ),
      panEnabled: !markupHandlesGestures && !_stylusDrawing && !_halfPageTurns,
      scaleEnabled:
          !markupHandlesGestures &&
          !_stylusDrawing &&
          !_performance &&
          !_halfPageTurns,
      scrollByMouseWheel: _halfPageTurns || (vertical && _inking) ? null : .2,
      enableKeyboardNavigation: false,
      horizontalCacheExtent: 1.5,
      maxImageBytesCachedOnMemory: 72 * 1024 * 1024,
      pagePaintCallbacks:
          _entry?.crops.isNotEmpty == true ||
              _preferences.sepia ||
              _preferences.pageDimming > 0
          ? [
              (canvas, rect, page) {
                if (_preferences.sepia) {
                  canvas.drawRect(
                    rect,
                    Paint()
                      ..color = _sepiaTint
                      ..blendMode = BlendMode.multiply,
                  );
                }
                if (_preferences.pageDimming > 0) {
                  canvas.drawRect(
                    rect,
                    Paint()
                      ..color = Colors.black.withValues(
                        alpha: _preferences.pageDimming,
                      ),
                  );
                }
                final crop = _cropFor(page.pageNumber);
                if (crop == null) return;
                final mask = Path()
                  ..fillType = PathFillType.evenOdd
                  ..addRect(rect)
                  ..addRect(crop.within(rect));
                canvas.drawPath(mask, Paint()..color = _stand);
              },
            ]
          : null,
      annotationRenderingMode: _embeddedAnnotationMode,
      linkHandlerParams: _inking || !_preferences.embeddedPdfLinks
          ? null
          : PdfLinkHandlerParams(
              enableAutoLinkDetection: false,
              linkColor: Colors.transparent,
              linkHoverColor: _brass.withValues(alpha: .22),
              onLinkTap: (link) {
                final destination = link.dest;
                if (destination == null ||
                    (_autoStylus && _lastReaderPointerStylus) ||
                    (_itemBookmark != null &&
                        (destination.pageNumber < _firstPage ||
                            destination.pageNumber > _lastPage)) ||
                    (_edgeTaps.handled && !_dispatchingEdgeLink) ||
                    revision != _revision ||
                    !_viewer.isReady) {
                  return;
                }
                _pdfLinkNavigations++;
                _viewer
                    .goToDest(destination, duration: Duration.zero)
                    .whenComplete(() {
                      _pdfLinkNavigations--;
                    });
              },
            ),
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _stopAutoScroll();
              _lastReaderPointerStylus = isPenPointer(event);
              if (_autoStylus && _lastReaderPointerStylus) return;
              _edgeTaps.down(
                event,
                size.width,
                canAdvance:
                    !vertical &&
                    !_inking &&
                    (_halfPageTurns ||
                        (_hasNextScore &&
                            _pages > 0 &&
                            _page == _lastPage &&
                            _viewer.isReady &&
                            _viewer.currentZoom <= _viewer.coverScale * 1.02)),
                allowBackward: _halfPageTurns && !_inking,
              );
            },
            onPointerMove: _edgeTaps.move,
            onPointerCancel: _edgeTaps.cancel,
            onPointerSignal: (event) {
              if (!_halfPageTurns || _inking || event is! PointerScrollEvent)
                return;
              final delta = event.scrollDelta.dy == 0
                  ? event.scrollDelta.dx
                  : event.scrollDelta.dy;
              final last = _lastHalfScroll;
              if (delta == 0 ||
                  (last != null &&
                      event.timeStamp - last <
                          const Duration(milliseconds: 180)))
                return;
              _lastHalfScroll = event.timeStamp;
              _turn(delta > 0 ? 1 : -1);
            },
            onPointerUp: (event) {
              final (step, swipe) = _edgeTaps.up(event);
              if (swipe != 0) {
                if (_halfPageTurns) {
                  _turn(swipe);
                } else {
                  _nextScore();
                }
                return;
              }
              if (step == 0 || _inking || !_viewer.isReady) return;
              _focus.requestFocus();
              // Route links before turning the page. Ignore the later tap
              // callback from the viewer's double-tap recognizer.
              _dispatchingEdgeLink = true;
              try {
                if (!_followJumpAt(event.localPosition) &&
                    !handleLinkTap(event.localPosition) &&
                    !_handleCornerShortcut(step, event.localPosition, size))
                  _performTap(step);
              } finally {
                _dispatchingEdgeLink = false;
              }
            },
          ),
        ),
        if (_previewBand() case final band?) band,
      ],
      onViewerReady: (document, controller) {
        if (!mounted || revision != _revision) return;
        final count = document.pages.length;
        if (count == 0) return;
        final first = (item?.page ?? 1).clamp(1, count);
        final last = (item?.endPage ?? count).clamp(first, count);
        final restored = _page.clamp(first, last);
        setState(() {
          _pages = count;
          _page = restored;
        });
        _remember(_entry?.id, restored);
        if (vertical || _cropFor(restored) != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && revision == _revision && _page == restored) {
              if (vertical) {
                _positionVerticalPage(controller, restored, resetZoom: true);
              } else {
                _fitCrop(restored, controller);
              }
            }
          });
        }
      },
      onViewSizeChanged: (size, previous, controller) {
        if (!mounted || previous == null || revision != _revision) {
          return;
        }
        if (vertical) {
          final anchor = _dockVerticalAnchor;
          _dockVerticalAnchor = null;
          if (anchor == null || anchor.revision != revision) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || revision != _revision || !controller.isReady)
              return;
            final layout = controller.layout;
            final page = layout.pageLayouts[anchor.page - 1];
            final zoom = controller.coverScale * anchor.scale;
            unawaited(
              controller.goToPosition(
                documentOffset: Offset(
                  (layout.documentSize.width -
                          controller.viewSize.width / zoom) /
                      2,
                  page.top +
                      page.height * anchor.center -
                      controller.viewSize.height / (2 * zoom),
                ),
                zoom: zoom,
              ),
            );
          });
          return;
        }
        // Keep the score on the same page when the controls resize the viewport.
        if (!_fitCrop(pageBeforeResize, controller)) {
          controller.goToPage(
            pageNumber: pageBeforeResize,
            duration: Duration.zero,
          );
        }
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
        setState(() {
          _page = page;
          _annotationPage = null;
          _pdfSelection = [];
          _pdfSelectionPage = null;
          _halfPreview = false;
        });
        _remember(_entry?.id, page);
        _recordAudioCue(page);
        if (!vertical && _pdfLinkNavigations == 0 && _cropFor(page) != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && revision == _revision && _page == page) {
              _fitCrop(page, _viewer);
            }
          });
        }
      },
      onGeneralTap: (context, controller, details) {
        if (_inking || _autoStylus && _lastReaderPointerStylus) return true;
        if (_performance && details.type == PdfViewerGeneralTapType.doubleTap) {
          return true;
        }
        if (details.type == PdfViewerGeneralTapType.longPress) {
          if (!_performance && _preferences.complexGestures) _toggleInk();
          return true;
        }
        final step = _EdgeTapTracker.direction(
          details.localPosition.dx,
          controller.viewSize.width,
        );
        if (step != 0) return true;
        if (details.type == PdfViewerGeneralTapType.doubleTap) {
          if (!_preferences.complexGestures) return true;
          if (controller.currentZoom > controller.coverScale * 1.02) {
            _fit();
          } else {
            _showDisplayPanel();
          }
          return true;
        }
        if (details.type != PdfViewerGeneralTapType.tap) return false;
        _focus.requestFocus();
        if (!_followJumpAt(details.localPosition)) _performTap(0);
        return true;
      },
      pageOverlaysBuilder: (context, rect, page) => [
        if (!_inking)
          for (final action in _entry?.actions ?? const <ScoreAction>[])
            if (action.page == page.pageNumber)
              Positioned(
                left: action.x * rect.width - _pageButtonSize / 2,
                top: action.y * rect.height - _pageButtonSize / 2,
                child: Semantics(
                  button: true,
                  label: action.title,
                  onTap: () => _runScoreAction(action),
                  child: IgnorePointer(
                    child: Container(
                      width: _pageButtonSize,
                      height: _pageButtonSize,
                      decoration: BoxDecoration(
                        color: Color(action.color),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Icon(
                        switch (action.kind) {
                          ScoreActionKind.note => Icons.sticky_note_2_outlined,
                          ScoreActionKind.score => Icons.open_in_new,
                          ScoreActionKind.nextSetlist => Icons.skip_next,
                          ScoreActionKind.previousSetlist =>
                            Icons.skip_previous,
                          ScoreActionKind.audio => Icons.play_arrow,
                          ScoreActionKind.tempo => Icons.speed,
                          ScoreActionKind.toggleMetronome =>
                            Icons.timer_outlined,
                          ScoreActionKind.pitch => Icons.music_note,
                          ScoreActionKind.website => Icons.language,
                          ScoreActionKind.externalApp => Icons.launch,
                          ScoreActionKind.externalFile => Icons.attach_file,
                          ScoreActionKind.midi =>
                            Icons.settings_input_component,
                        },
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
        if (!_inking)
          for (final action in _entry?.actions ?? const <ScoreAction>[])
            if (action.page == page.pageNumber && action.showLabel)
              Positioned.fromRect(
                rect: _actionLabelRect(action, rect.size),
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(action.color),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _actionLabelStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        Positioned.fill(
          child: ClipRect(
            clipper: _PageCropClipper(_cropFor(page.pageNumber)),
            child: InkSurface(
              key: ValueKey(page.pageNumber),
              ink: _ink.putIfAbsent(page.pageNumber, _newPageInk),
              enabled:
                  _inking && !(_selectingPdf && _tool == InkTool.selection),
              allowFinger: _allowFinger,
              tool: _tool,
              width: _tool == InkTool.pen || !_inking
                  ? _drawing.preset.width
                  : null,
              color: _tool == InkTool.pen || !_inking
                  ? _drawing.preset.argb
                  : null,
              onTextTap: (point, size) =>
                  _editText(page.pageNumber, point, size),
              shape: _shape,
              ruler:
                  _inking &&
                      _showRuler &&
                      page.pageNumber == (_annotationPage ?? _page)
                  ? _ruler
                  : null,
              freeformSelection: _freeformSelection,
              pressure: _drawing.pressure,
              tilt: _drawing.tilt,
              switchTools: _drawing.switchTools,
              autoStylus: _autoStylus,
              onEditStart: vertical
                  ? () {
                      if (_annotationPage != page.pageNumber) {
                        setState(() => _annotationPage = page.pageNumber);
                      }
                    }
                  : null,
              onStylusStart: _stylusStarted,
              onStylusEnd: _stylusFinished,
            ),
          ),
        ),
        if (_inking && _selectingPdf && _tool == InkTool.selection)
          Positioned.fill(
            child: ClipRect(
              clipper: _PageCropClipper(_cropFor(page.pageNumber)),
              child: _pdfSelectionSurface(page),
            ),
          ),
        if (_inking &&
            !(_selectingPdf && _tool == InkTool.selection) &&
            _showRuler &&
            page.pageNumber == (_annotationPage ?? _page))
          Positioned.fill(
            child: ClipRect(
              clipper: _PageCropClipper(_cropFor(page.pageNumber)),
              child: InkRulerOverlay(
                guide: _ruler,
                color: const Color(0xff1683cd),
                onChanged: (guide) => setState(() => _ruler = guide),
              ),
            ),
          ),
        if (!_inking &&
            !_performance &&
            _entry?.pageNotes.containsKey(page.pageNumber) == true)
          Positioned(
            top: (_cropFor(page.pageNumber)?.top ?? 0) * rect.height + 4,
            left: rect.width / 2 - 22,
            child: Material(
              color: _rail,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Page ${page.pageNumber} note',
                color: _brass,
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: _picking
                    ? null
                    : () => _editPageNote(page.pageNumber),
              ),
            ),
          ),
        if (!_inking)
          for (final (link, point, target, returning) in _jumpMarkers())
            if (point.page == page.pageNumber)
              Positioned(
                left: point.x * rect.width - _pageButtonSize / 2,
                top: point.y * rect.height - _pageButtonSize / 2,
                child: IgnorePointer(
                  child: Semantics(
                    label: returning ? 'Return from ${link.title}' : link.title,
                    button: true,
                    onTap: () => _followJump(target),
                    child: Container(
                      width: _pageButtonSize,
                      height: _pageButtonSize,
                      decoration: BoxDecoration(
                        color: returning ? _brass : const Color(0xff316989),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        returning
                            ? Icons.reply
                            : Icons.subdirectory_arrow_right,
                        size: 19,
                        color: returning ? _rail : Colors.white,
                      ),
                    ),
                  ),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final key = ValueKey(revision);
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
      canPop: !_performance && _readerDock == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_readerDock != null) {
          _backFromReaderDock();
        } else if (_performance) {
          _togglePerformance();
        }
      },
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: _wideReaderDock ? _dockWidth : 0,
              ),
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: Column(
                  children: [
                    if (_showControls && !_performance) _header(),
                    if (_showControls &&
                        !_performance &&
                        _appearance.showTabs &&
                        (_scoreTabIds.isNotEmpty || _appearance.alwaysShowTabs))
                      _scoreTabs(),
                    Expanded(
                      key: const ValueKey('score-viewport'),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _deskewedScore(),
                          if (!_showControls &&
                              !_performance &&
                              _preferences.cornerShortcuts)
                            PositionedDirectional(
                              top: 0,
                              end: 0,
                              child: _readerToolsMenu(corner: true),
                            ),
                          if (_inking) _markupOverlay(),
                          if (_autoScrollTicker.isActive && !_performance)
                            PositionedDirectional(
                              end: 8,
                              bottom: 8,
                              child: _activeScrollControls(),
                            ),
                          if (_missingFacingPage)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(
                                () => _showControls = !_showControls,
                              ),
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                child: const Center(
                                  child: Text('No facing page'),
                                ),
                              ),
                            ),
                          if (_performance)
                            PositionedDirectional(
                              top: 8,
                              end: 8,
                              child: IconButton(
                                tooltip: 'Exit performance mode',
                                style: IconButton.styleFrom(
                                  backgroundColor: _rail,
                                  foregroundColor: _paper,
                                ),
                                onPressed: _togglePerformance,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_metronome case final meter?)
                      MetronomeBeat(metronome: meter),
                    if (_playing case final setlist?
                        when !_performance && _showControls)
                      TextButton.icon(
                        onPressed: _picking ? null : _showNowPlaying,
                        icon: const Icon(Icons.queue_music),
                        label: Text(
                          [
                            setlist.name,
                            if (_nextTitle case final title?) 'Next: $title',
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_performance && _page == _lastPage)
                      if (_nextTitle case final title?)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Next: $title',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    if (_performance)
                      _performanceBar()
                    else if (_showControls)
                      _footer(),
                  ],
                ),
              ),
            ),
            if (_readerDock case final panel?) ...[
              if (!_wideReaderDock)
                ModalBarrier(
                  color: Colors.black38,
                  dismissible: true,
                  onDismiss: _backFromReaderDock,
                ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: math.min(_dockWidth, MediaQuery.sizeOf(context).width),
                child: Material(
                  elevation: _wideReaderDock ? 2 : 12,
                  clipBehavior: Clip.antiAlias,
                  child: panel,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _deskewedScore() {
    final angle = !_verticalScrolling && _spreadStep == 0
        ? _cropFor(_page)?.angle ?? 0
        : 0.0;
    return ClipRect(
      child: Transform.rotate(angle: angle * math.pi / 180, child: _score()),
    );
  }

  Widget _scoreTabs() => Material(
    color: _rail,
    child: SizedBox(
      height: 48,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _scoreTabIds.length,
        footer: IconButton(
          tooltip: 'Open in new tab',
          onPressed: _picking || _savingTabs ? null : _openNewScoreTab,
          icon: const Icon(Icons.add),
        ),
        onReorderItem: (from, to) {
          if (_picking || _savingTabs || from == to) return;
          final ids = [..._scoreTabIds];
          ids.insert(to, ids.removeAt(from));
          _updateScoreTabs(ids);
        },
        itemBuilder: (context, index) {
          final id = _scoreTabIds[index];
          final target = _lookupTab(id);
          final title = target?.$2?.title ?? target?.$1.title ?? 'Saved score';
          return ReorderableDelayedDragStartListener(
            key: ValueKey(id),
            index: index,
            enabled: !_picking && !_savingTabs,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: InputChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(title, overflow: TextOverflow.ellipsis),
                ),
                labelStyle: TextStyle(
                  color: id == _activeScoreTabId ? _brass : _paper,
                ),
                selected: id == _activeScoreTabId,
                onPressed: _picking ? null : () => _switchScoreTab(id),
                deleteButtonTooltipMessage: 'Close tab',
                onDeleted: () => _closeScoreTab(id),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _header() => Material(
    color: _rail,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final navigation = <Widget>[
          IconButton(
            tooltip: ReaderText.library.of(context),
            onPressed: _picking
                ? null
                : () => _openCornerMenu(_CornerMenu.scores),
            icon: const Icon(Icons.library_music_outlined),
          ),
          IconButton(
            tooltip: 'Bookmarks',
            onPressed: _picking || _entry == null || _pages == 0
                ? null
                : () => _openCornerMenu(_CornerMenu.bookmarks),
            icon: const Icon(Icons.bookmark_outline),
          ),
          IconButton(
            tooltip: ReaderText.setlists.of(context),
            onPressed: _picking
                ? null
                : () => _openCornerMenu(_CornerMenu.setlists),
            icon: const Icon(Icons.queue_music),
          ),
          if (_toolbarShortcutButton(left: true) case final shortcut?) shortcut,
        ];
        final utilities = [_audioUtilitiesButton(), _readerToolsMenu()];
        final title = _readerTitle();
        final display = _displayButton();
        final scoreActions = _scoreActionsMenu();
        final editing = [
          if (_toolbarShortcutButton(left: false) case final shortcut?)
            shortcut,
          IconButton(
            tooltip: ReaderText.search.of(context),
            onPressed: _picking
                ? null
                : () => _openCornerMenu(_CornerMenu.search),
            icon: const Icon(Icons.search),
          ),
        ];
        if (constraints.maxWidth < 720) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
                child: Row(
                  children: [
                    display,
                    Expanded(child: title),
                    scoreActions,
                  ],
                ),
              ),
              const Divider(height: 1, indent: 12, endIndent: 12),
              Row(
                children: [
                  for (final control in [
                    ...navigation,
                    ...editing,
                    ...utilities,
                  ])
                    Expanded(child: Center(child: control)),
                ],
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            children: [
              ...navigation,
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _displayButton(),
                      Flexible(child: title),
                      _scoreActionsMenu(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ...editing,
              ...utilities,
            ],
          ),
        );
      },
    ),
  );

  _ReaderDisplay? _toolbarDisplayAction(_ToolbarShortcut shortcut) =>
      switch (shortcut) {
        _ToolbarShortcut.services => _ReaderDisplay.cloudServices,
        _ToolbarShortcut.annotations => _ReaderDisplay.annotate,
        _ToolbarShortcut.find => _ReaderDisplay.findInScore,
        _ToolbarShortcut.metronome => _ReaderDisplay.metronome,
        _ToolbarShortcut.piano => _ReaderDisplay.piano,
        _ToolbarShortcut.note => _ReaderDisplay.pageNote,
        _ => null,
      };

  bool _toolbarShortcutAllowed(_ToolbarShortcut shortcut) =>
      _readerActionAllowed(_toolbarDisplayAction(shortcut)) &&
      (shortcut != _ToolbarShortcut.services ||
          (!_restricted(RestrictedTool.transfers) &&
              !_restricted(RestrictedTool.connections)));

  Widget? _toolbarShortcutButton({required bool left}) {
    final shortcut = left ? _leftToolbarShortcut : _rightToolbarShortcut;
    if (shortcut == _ToolbarShortcut.hidden ||
        !_toolbarShortcutAllowed(shortcut)) {
      return null;
    }
    final markingUp = shortcut == _ToolbarShortcut.annotations && _inking;
    final available = switch (shortcut) {
      _ToolbarShortcut.annotations || _ToolbarShortcut.find => _pages > 0,
      _ToolbarShortcut.note => _entry != null,
      _ToolbarShortcut.metronome ||
      _ToolbarShortcut.piano => ScoreAudioSession.supported,
      _ => true,
    };
    return Tooltip(
      message: markingUp
          ? 'Done marking up'
          : shortcut == _ToolbarShortcut.annotations
          ? ReaderText.markup.of(context)
          : shortcut.label,
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _picking
            ? null
            : () => _configureToolbarShortcuts(onlyLeft: left),
        child: IconButton(
          icon: Icon(markingUp ? Icons.check : shortcut.icon),
          color: markingUp ? _brass : null,
          onPressed: _picking || !available
              ? null
              : () {
                  if (_toolbarDisplayAction(shortcut) case final action?) {
                    unawaited(_runReaderDisplayAction(action));
                  } else if (shortcut == _ToolbarShortcut.display) {
                    unawaited(_showDisplayPanel());
                  }
                },
        ),
      ),
    );
  }

  Future<void> _configureToolbarShortcuts({bool? onlyLeft}) async {
    var left = _leftToolbarShortcut;
    var right = _rightToolbarShortcut;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          Widget picker({
            required String label,
            required _ToolbarShortcut value,
            required ValueChanged<_ToolbarShortcut> set,
          }) => DropdownButtonFormField<_ToolbarShortcut>(
            key: ValueKey((label, value)),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            onChanged: (shortcut) {
              if (shortcut != null) update(() => set(shortcut));
            },
            items: [
              for (final shortcut in _ToolbarShortcut.values)
                DropdownMenuItem(
                  value: shortcut,
                  enabled: _toolbarShortcutAllowed(shortcut),
                  child: Text(shortcut.label),
                ),
            ],
          );
          return AlertDialog(
            title: const Text('Toolbar shortcuts'),
            scrollable: true,
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onlyLeft != false)
                    picker(
                      label: 'Left shortcut',
                      value: left,
                      set: (value) => left = value,
                    ),
                  if (onlyLeft != true)
                    picker(
                      label: 'Right shortcut',
                      value: right,
                      set: (value) => right = value,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => update(() {
                  if (onlyLeft != false) left = _ToolbarShortcut.services;
                  if (onlyLeft != true) right = _ToolbarShortcut.annotations;
                }),
                child: const Text('Reset defaults'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await _library.updatePreferences({
        'leftToolbarShortcut': left.name,
        'rightToolbarShortcut': right.name,
      });
      if (mounted) {
        setState(() {
          _leftToolbarShortcut = left;
          _rightToolbarShortcut = right;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save toolbar shortcuts.')),
        );
      }
    }
  }

  Widget _readerTitle() {
    final composer = _entry?.metadata['composer'];
    return InkWell(
      key: const ValueKey('reader-title'),
      onTap: _entry == null || _picking ? null : () => _editScore(_entry!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                _title,
                style: TextStyle(
                  fontSize: 21,
                  fontFamily: 'serif',
                  color: _paper,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (_appearance.showMetadata &&
                composer != null &&
                composer.isNotEmpty)
              Text(
                composer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: _paper.withValues(alpha: .75),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _audioUtilitiesButton() => IconButton(
    tooltip: 'Audio utilities',
    icon: const Icon(Icons.timer_outlined),
    onPressed: _picking || !ScoreAudioSession.supported
        ? null
        : () => _openCornerMenu(_CornerMenu.audio),
  );

  static const _displayActions = {
    _ReaderDisplay.appearance,
    _ReaderDisplay.toolbarShortcuts,
    _ReaderDisplay.accessibility,
    _ReaderDisplay.reflow,
    _ReaderDisplay.panelOptions,
    _ReaderDisplay.embeddedPdf,
    _ReaderDisplay.fit,
    _ReaderDisplay.fittingMode,
    _ReaderDisplay.scrollMode,
    _ReaderDisplay.autoScroll,
    _ReaderDisplay.zoomIn,
    _ReaderDisplay.zoomOut,
    _ReaderDisplay.halfTurns,
    _ReaderDisplay.halfSplit,
    _ReaderDisplay.halfIndicator,
    _ReaderDisplay.landscapeWidth,
    _ReaderDisplay.spreads,
    _ReaderDisplay.performance,
    _ReaderDisplay.hideControls,
    _ReaderDisplay.cleanStartup,
    _ReaderDisplay.keepAwake,
    _ReaderDisplay.nextTitle,
    _ReaderDisplay.presentation,
    _ReaderDisplay.gestures,
    _ReaderDisplay.language,
    _ReaderDisplay.profiles,
    _ReaderDisplay.metadataSymbols,
    _ReaderDisplay.themeOptions,
    _ReaderDisplay.maintenance,
    _ReaderDisplay.appIcon,
    _ReaderDisplay.drawingSettings,
  };

  static const _scoreActions = {
    _ReaderDisplay.nowPlaying,
    _ReaderDisplay.findInScore,
    _ReaderDisplay.pageNote,
    _ReaderDisplay.pageActions,
    _ReaderDisplay.scoreAudio,
    _ReaderDisplay.practiceRecordings,
    _ReaderDisplay.copyMeasure,
    _ReaderDisplay.pasteMeasure,
    _ReaderDisplay.midiAutomation,
    _ReaderDisplay.scoreWindow,
    _ReaderDisplay.previousPage,
    _ReaderDisplay.previousScore,
    _ReaderDisplay.bookmarks,
    _ReaderDisplay.jumpLinks,
    _ReaderDisplay.scoreTabs,
    _ReaderDisplay.exportPdf,
    _ReaderDisplay.crop,
    _ReaderDisplay.shareScorePackage,
    _ReaderDisplay.shareScoreLink,
  };

  Future<void> _runReaderDisplayAction(_ReaderDisplay action) async {
    if (!_readerActionAllowed(action)) return;
    switch (action) {
      case _ReaderDisplay.annotate:
        _toggleInk();
      case _ReaderDisplay.rearrangeScore:
        if (_entry case final score?) {
          await _showLibrary(entryAction: 'rearrange:${score.id}');
        }
      case _ReaderDisplay.librarySync:
        await _showLibrary(entryAction: 'sync');
      case _ReaderDisplay.toolbarShortcuts:
        await _configureToolbarShortcuts();
      case _ReaderDisplay.readerSettings:
        await _showReaderSettings();
      case _ReaderDisplay.migrateLibrary:
        await _open(migration: true);
      case _ReaderDisplay.importScore:
        await _showLibrary(entryAction: 'import');
      case _ReaderDisplay.scanScore:
        await _showLibrary(entryAction: 'scan');
      case _ReaderDisplay.cloudServices:
        await _showLibrary(entryAction: 'cloud-files');
      case _ReaderDisplay.scoreTemplates:
        await _showLibrary(entryAction: 'create-template');
      case _ReaderDisplay.libraryBackup:
        await _showLibrary(entryAction: 'backup');
      case _ReaderDisplay.nowPlaying:
        _showNowPlaying();
      case _ReaderDisplay.findInScore:
        _findInScore();
      case _ReaderDisplay.pageNote:
        _editPageNote(_page);
      case _ReaderDisplay.pageActions:
        _editScoreActions();
      case _ReaderDisplay.scoreAudio:
        _showScoreAudio();
      case _ReaderDisplay.practiceRecordings:
        _showPracticeRecordings();
      case _ReaderDisplay.practiceActivity:
        _showPracticeActivity();
      case _ReaderDisplay.restrictions:
        _showRestrictions();
      case _ReaderDisplay.assistantConnections:
        await _openReaderPanel<void>(
          (_) => AssistantConnectionScreen(connection: _assistantConnection),
        );
      case _ReaderDisplay.support:
        _showSupport();
      case _ReaderDisplay.language:
        _chooseLanguage();
      case _ReaderDisplay.profiles:
        _showSettingsProfiles();
      case _ReaderDisplay.metadataSymbols:
        _editMetadataSymbols();
      case _ReaderDisplay.themeOptions:
        _changeThemeOptions();
      case _ReaderDisplay.maintenance:
        _showMaintenance();
      case _ReaderDisplay.appIcon:
        chooseLauncherIcon(context);
      case _ReaderDisplay.metronome:
        _showMetronome();
      case _ReaderDisplay.tuner:
        _showTuner();
      case _ReaderDisplay.piano:
        _showPiano();
      case _ReaderDisplay.inputShortcuts:
        _showInputShortcuts();
      case _ReaderDisplay.faceTurns:
        _configureFaceTurns();
      case _ReaderDisplay.copyMeasure:
        _selectPdf();
      case _ReaderDisplay.pasteMeasure:
        _selectPdf(paste: true);
      case _ReaderDisplay.midiDevices:
        _showMidiDevices();
      case _ReaderDisplay.midiAutomation:
        _showMidiAutomation();
      case _ReaderDisplay.ensemble:
        _showEnsemble();
      case _ReaderDisplay.scoreWindow:
        _openScoreWindow();
      case _ReaderDisplay.presentation:
        _togglePresentation();
      case _ReaderDisplay.appearance:
        _showAppearance();
      case _ReaderDisplay.accessibility:
        _showAccessibility();
      case _ReaderDisplay.reflow:
        _showReflow();
      case _ReaderDisplay.panelOptions:
        _showPanelOptions();
      case _ReaderDisplay.embeddedPdf:
        _showEmbeddedPdfSettings();
      case _ReaderDisplay.fit:
        _fit();
      case _ReaderDisplay.fittingMode:
        _choosePageFit();
      case _ReaderDisplay.scrollMode:
        await _chooseScrollMode();
      case _ReaderDisplay.autoScroll:
        await _showAutoScroll();
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
      case _ReaderDisplay.jumpLinks:
        _showJumpLinks();
      case _ReaderDisplay.halfTurns:
        _savePreferences(
          _preferences.copyWith(halfPageTurns: !_preferences.halfPageTurns),
        );
      case _ReaderDisplay.halfSplit:
        _setHalfSplit();
      case _ReaderDisplay.halfIndicator:
        _savePreferences(
          _preferences.copyWith(
            halfPageIndicator: !_preferences.halfPageIndicator,
          ),
        );
      case _ReaderDisplay.landscapeWidth:
        _savePreferences(
          _preferences.copyWith(landscapeWidth: !_preferences.landscapeWidth),
        );
      case _ReaderDisplay.spreads:
        final step = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Page layout'),
            children: [
              for (final (step, label) in [
                (0, 'Single page'),
                (1, 'Two pages · advance one'),
                (2, 'Two pages · advance two'),
                if (_canThreeUp) (3, 'Three pages · advance three'),
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, step),
                  child: Text(label),
                ),
            ],
          ),
        );
        if (step != null && mounted) {
          _savePreferences(
            _preferences.copyWith(
              spreadStep: step,
              halfPageTurns: step == 0 && _preferences.halfPageTurns,
            ),
          );
        }
      case _ReaderDisplay.performance:
        _togglePerformance();
      case _ReaderDisplay.exportPdf:
        _showPdfExport();
      case _ReaderDisplay.crop:
        _showCrop();
      case _ReaderDisplay.drawingSettings:
        _configureDrawing();
      case _ReaderDisplay.shareScorePackage:
        _shareEditableScore();
      case _ReaderDisplay.shareScoreLink:
        if (_entry case final score?) {
          final bookmark = _itemBookmark;
          await copyReaderLink(
            context,
            bookmark == null
                ? ReaderLinkTarget.score
                : ReaderLinkTarget.bookmark,
            bookmark?.selectionId(score.id) ?? score.id,
          );
        }
      case _ReaderDisplay.scoreTabs:
        if (_activeScoreTabId case final id? when !_scoreTabIds.contains(id)) {
          await _updateScoreTabs([..._scoreTabIds, id]);
        } else {
          await _openNewScoreTab();
        }
      case _ReaderDisplay.hideControls:
        setState(() => _showControls = false);
      case _ReaderDisplay.cleanStartup:
        await _savePreferences(
          _preferences.copyWith(
            startWithControlsHidden: !_preferences.startWithControlsHidden,
          ),
        );
      case _ReaderDisplay.gestures:
        _configureGestures();
      case _ReaderDisplay.keepAwake:
        _savePreferences(
          _preferences.copyWith(
            left: _preferences.left,
            center: _preferences.center,
            right: _preferences.right,
            keepAwake: !_preferences.keepAwake,
            showNextTitle: _preferences.showNextTitle,
          ),
        );
      case _ReaderDisplay.nextTitle:
        _savePreferences(
          _preferences.copyWith(
            left: _preferences.left,
            center: _preferences.center,
            right: _preferences.right,
            keepAwake: _preferences.keepAwake,
            showNextTitle: !_preferences.showNextTitle,
          ),
        );
    }
  }

  Widget _displayButton() => IconButton(
    tooltip: 'Display',
    onPressed: _pages > 0 && !_picking ? _showDisplayPanel : null,
    icon: const Icon(Icons.view_quilt_outlined),
  );

  Future<void> _showDisplayPanel() async {
    if (_picking || _pages == 0 || _performance) return;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final canSpread = landscape && size.width >= 600 && _itemBookmark == null;
    final canDock = size.width >= _dockMinimumWidth;
    final scoreId = _entry?.id;
    final connection = _ensemble;
    final action = await showDialog<FutureOr<void> Function()>(
      context: context,
      builder: (dialog) {
        final theme = Theme.of(dialog);
        Widget control(
          String label,
          IconData icon,
          FutureOr<void> Function()? run, {
          bool active = false,
          String? settingsLabel,
          FutureOr<void> Function()? settings,
        }) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                selected: active,
                child: OutlinedButton.icon(
                  onPressed: run == null
                      ? null
                      : () => Navigator.pop(dialog, run),
                  onLongPress: settings == null
                      ? null
                      : () => Navigator.pop(dialog, settings),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: active
                        ? theme.colorScheme.primary.withValues(alpha: .18)
                        : null,
                    foregroundColor: theme.colorScheme.primary,
                    side: active
                        ? BorderSide(color: theme.colorScheme.primary)
                        : null,
                  ),
                  icon: Icon(icon, size: 19),
                  label: Text(label),
                ),
              ),
              if (settings != null)
                IconButton(
                  tooltip: settingsLabel,
                  onPressed: () => Navigator.pop(dialog, settings),
                  icon: const Icon(Icons.tune, size: 18),
                ),
            ],
          );
        }

        Widget section(String title, List<Widget> buttons) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: buttons),
            ],
          ),
        );

        return AlertDialog(
          title: const Text('Display options'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('Display mode', [
                  for (final fit
                      in landscape
                          ? [ReaderPageFit.bestFit, ReaderPageFit.zoomed]
                          : ReaderPageFit.values)
                    control(
                      landscape && fit == ReaderPageFit.zoomed
                          ? 'Scroll'
                          : fit.label,
                      fit == ReaderPageFit.zoomed
                          ? Icons.swap_vert
                          : Icons.aspect_ratio,
                      () => _applyDisplayFit(fit),
                      active:
                          !_verticalScrolling &&
                          (_preferences.pageFit == fit ||
                              (landscape &&
                                  _preferences.pageFit ==
                                      ReaderPageFit.standard &&
                                  fit ==
                                      (_preferences.landscapeWidth
                                          ? ReaderPageFit.zoomed
                                          : ReaderPageFit.bestFit))),
                    ),
                  control(
                    'Continuous scrolling',
                    Icons.view_day_outlined,
                    () => _setScrollMode(
                      _verticalScrolling
                          ? ReaderScrollMode.paged
                          : ReaderScrollMode.fitWidth,
                      scoreId: scoreId,
                    ),
                    active: _verticalScrolling,
                    settingsLabel: 'Scrolling settings',
                    settings: _chooseScrollMode,
                  ),
                ]),
                section('Page options', [
                  if (canSpread && _canThreeUp)
                    control(
                      'Three-up',
                      Icons.view_column_outlined,
                      _verticalScrolling
                          ? null
                          : () => _savePreferences(
                              _preferences.copyWith(
                                spreadStep: _spreadStep == 3 ? 0 : 3,
                                halfPageTurns: false,
                              ),
                            ),
                      active: _spreadStep == 3,
                    ),
                  if (canSpread)
                    control(
                      'Two-up',
                      Icons.view_week_outlined,
                      _verticalScrolling
                          ? null
                          : () => _savePreferences(
                              _preferences.copyWith(
                                spreadStep: _spreadStep == 1 || _spreadStep == 2
                                    ? 0
                                    : 2,
                                halfPageTurns: false,
                              ),
                            ),
                      active: _spreadStep == 1 || _spreadStep == 2,
                      settingsLabel: 'Two-up settings',
                      settings: _verticalScrolling
                          ? null
                          : () =>
                                _runReaderDisplayAction(_ReaderDisplay.spreads),
                    )
                  else
                    control(
                      'Partial turns',
                      Icons.chrome_reader_mode_outlined,
                      _verticalScrolling
                          ? null
                          : () => _savePreferences(
                              _preferences.copyWith(
                                halfPageTurns: !_preferences.halfPageTurns,
                                spreadStep: 0,
                              ),
                            ),
                      active: _halfPageTurns,
                      settingsLabel: 'Partial turn settings',
                      settings: _showPartialTurnSettings,
                    ),
                  control(
                    'Sepia',
                    Icons.wb_sunny_outlined,
                    () => _savePreferences(
                      _preferences.copyWith(sepia: !_preferences.sepia),
                    ),
                    active: _preferences.sepia,
                    settingsLabel: 'Reading appearance settings',
                    settings: _showAppearance,
                  ),
                  if (canDock)
                    control(
                      'Sidebar',
                      Icons.vertical_split_outlined,
                      () => _savePreferences(
                        _preferences.copyWith(
                          dockPanels:
                              !_preferences.dockPanels ||
                              _preferences.fullScreenPanels,
                          fullScreenPanels: false,
                        ),
                      ),
                      active:
                          _preferences.dockPanels &&
                          !_preferences.fullScreenPanels,
                      settingsLabel: 'Sidebar settings',
                      settings: _showPanelOptions,
                    ),
                ]),
                section('Playing', [
                  control(
                    'Perform',
                    Icons.fullscreen,
                    _togglePerformance,
                    active: _performance,
                  ),
                  if (!kIsWeb && _readerActionAllowed(_ReaderDisplay.ensemble))
                    control(
                      'Ensemble sync',
                      Icons.devices_outlined,
                      _showEnsemble,
                      active:
                          connection?.leading == true ||
                          connection?.following == true,
                    ),
                  control('Reflow', Icons.wrap_text, _showReflow),
                  if (_supportsSharedImport &&
                      _readerActionAllowed(_ReaderDisplay.faceTurns))
                    control(
                      'Face Gestures',
                      Icons.face_outlined,
                      _configureFaceTurns,
                      active: _faceTurns != null,
                      settingsLabel: 'Face gesture settings',
                      settings: () => _configureFaceTurns(configure: true),
                    ),
                  if (_verticalScrolling)
                    control(
                      'Automatic scrolling',
                      Icons.play_circle_outline,
                      _canAutoScroll ? _showAutoScroll : null,
                      active: _autoScrollTicker.isActive,
                    ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
    if (mounted && action != null) await action();
  }

  Future<void> _applyDisplayFit(ReaderPageFit fit) async {
    if (_verticalScrolling) {
      await _setScrollMode(ReaderScrollMode.paged, scoreId: _entry?.id);
    }
    if (!mounted) return;
    if (fit == _preferences.pageFit) {
      _fit();
    } else {
      await _savePreferences(_preferences.copyWith(pageFit: fit));
    }
  }

  Future<void> _showPartialTurnSettings() async {
    final action = await showDialog<_ReaderDisplay>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Partial turn settings'),
        children: [
          ListTile(
            title: const Text('Adjust current page split'),
            enabled: _halfPageTurns && _page < _lastPage,
            onTap: _halfPageTurns && _page < _lastPage
                ? () => Navigator.pop(dialog, _ReaderDisplay.halfSplit)
                : null,
          ),
          SwitchListTile(
            title: const Text('Show page split indicator'),
            value: _preferences.halfPageIndicator,
            onChanged: (_) =>
                Navigator.pop(dialog, _ReaderDisplay.halfIndicator),
          ),
        ],
      ),
    );
    if (mounted && action != null) await _runReaderDisplayAction(action);
  }

  Future<void> _showReaderSettings() async {
    final result = await showDialog<_ReaderDisplay>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reader settings'),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _readerMenuItems(_ReaderMenu.display))
                ListTile(
                  title: item.child,
                  enabled: item.enabled,
                  trailing: item is CheckedPopupMenuItem<_ReaderDisplay>
                      ? Icon(
                          item.checked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: item.enabled
                      ? () => Navigator.pop(dialog, item.value)
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted && result != null) await _runReaderDisplayAction(result);
  }

  Widget _scoreActionsMenu() {
    final score = _entry;
    final bookmark = _itemBookmark;
    final selection = _currentScoreSelection;
    final flags = score == null
        ? const <int>[]
        : _library.lookup(score.id)?.flags ?? const <int>[];
    final facingPage = _spreadStep > 0 && _page < _lastPage ? _page + 1 : null;
    final thirdPage = _spreadStep == 3 && _page + 2 <= _lastPage
        ? _page + 2
        : null;
    String flagLabel(int page) =>
        flags.contains(page) ? 'Unflag page' : 'Flag page';
    MenuItemButton flagButton(int page, {String? side}) => MenuItemButton(
      leadingIcon: Icon(
        flags.contains(page) ? Icons.flag : Icons.outlined_flag,
      ),
      onPressed: score == null
          ? null
          : () => _toggleScorePageFlag(score.id, page),
      child: Text(
        side == null ? flagLabel(page) : '${flagLabel(page)} ($side)',
      ),
    );
    final canShare = const [
      _ReaderDisplay.exportPdf,
      _ReaderDisplay.shareScorePackage,
      _ReaderDisplay.shareScoreLink,
    ].any(_readerActionAllowed);
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        tooltip: 'Score actions',
        icon: const Icon(Icons.expand_more),
        onPressed: score == null || _pages == 0 || _picking
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        if (score != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.info_outline),
            onPressed: () => _editScore(score),
            child: const Text('Score info'),
          ),
        if (facingPage == null)
          flagButton(_page)
        else
          SubmenuButton(
            leadingIcon: const Icon(Icons.outlined_flag),
            menuChildren: [
              flagButton(_page, side: 'left'),
              flagButton(
                facingPage,
                side: thirdPage == null ? 'right' : 'center',
              ),
              if (thirdPage != null) flagButton(thirdPage, side: 'right'),
            ],
            child: const Text('Page flags'),
          ),
        if (canShare)
          SubmenuButton(
            leadingIcon: const Icon(Icons.share_outlined),
            menuChildren: [
              for (final (label, action) in [
                ('Share PDF', _ReaderDisplay.exportPdf),
                ('Share editable score', _ReaderDisplay.shareScorePackage),
                ('Copy score link', _ReaderDisplay.shareScoreLink),
              ])
                if (_readerActionAllowed(action))
                  MenuItemButton(
                    onPressed: () => _runReaderDisplayAction(action),
                    child: Text(label),
                  ),
            ],
            child: const Text('Share'),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.library_music_outlined),
          onPressed: score == null
              ? null
              : () => _showLibrary(revealScoreId: score.id),
          child: const Text('Show in library'),
        ),
        if (_appearance.showTabs)
          MenuItemButton(
            leadingIcon: const Icon(Icons.tab),
            onPressed: selection == null || _savingTabs
                ? null
                : () => _duplicateCurrentTab(selection),
            child: const Text('New tab'),
          ),
        if (_supportsScoreWindows &&
            _readerActionAllowed(_ReaderDisplay.scoreWindow))
          MenuItemButton(
            leadingIcon: const Icon(Icons.open_in_new),
            onPressed: _openScoreWindow,
            child: const Text('New window'),
          ),
        if (_lastOpenedScoreTab case final id? when _scoreTabIds.contains(id))
          MenuItemButton(
            leadingIcon: const Icon(Icons.undo),
            onPressed: _savingTabs ? null : () => _closeScoreTab(id),
            child: const Text('Undo open tab'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.playlist_add),
          onPressed: selection == null
              ? null
              : () => _addToSetlist(context, _library, selection),
          child: const Text('Add to setlist'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: score == null
              ? null
              : () => _deleteCurrentScoreItem(score, bookmark),
          child: Text(bookmark == null ? 'Delete score…' : 'Delete bookmark…'),
        ),
      ],
    );
  }

  Future<void> _openScoreInAnotherTab(ScoreEntry score) async {
    final current = _currentScoreSelection == score.id
        ? _activeScoreTabId
        : null;
    final page = current == null ? score.page : _page;
    final id = '${score.id}|${ScoreLibrary.newRecordId()}';
    if (current != null) _scoreTabPages[current] = page;
    _scoreTabPages[id] = page;
    await _updateScoreTabs([
      ..._scoreTabIds,
      if (current != null && !_scoreTabIds.contains(current)) current,
      id,
    ]);
    if (!mounted || !_scoreTabIds.contains(id)) {
      _scoreTabPages.remove(id);
      return;
    }
    await _openLibraryScore(score, startPage: page, tabInstance: id);
    if (mounted) setState(() => _lastOpenedScoreTab = id);
  }

  Future<void> _duplicateCurrentTab(String selection) async {
    final current = _activeScoreTabId ?? selection;
    final page = _page;
    final id = '$selection|${ScoreLibrary.newRecordId()}';
    _scoreTabPages[current] = page;
    _scoreTabPages[id] = page;
    await _updateScoreTabs([
      ..._scoreTabIds,
      if (!_scoreTabIds.contains(current)) current,
      id,
    ]);
    if (!mounted || !_scoreTabIds.contains(id)) {
      _scoreTabPages.remove(id);
      return;
    }
    setState(() => _lastOpenedScoreTab = id);
    await _switchScoreTab(id);
  }

  Future<void> _toggleScorePageFlag(String id, int page) async {
    try {
      await _library.togglePageFlag(id, page);
      if (mounted && _entry?.id == id) {
        setState(() => _entry = _library.lookup(id));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update page flags.')),
        );
      }
    }
  }

  Future<void> _deleteCurrentScoreItem(
    ScoreEntry score,
    ScoreBookmark? bookmark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${bookmark?.title ?? score.title}?'),
        content: bookmark == null
            ? const Text('You can recover this score from Backup & restore.')
            : const Text('This removes the bookmark from the score.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _picking) return;
    setState(() => _picking = true);
    try {
      if (bookmark == null) {
        await _library.trashScores([score.id]);
      } else {
        await _library.updateScore(
          score.id,
          (entry) => entry.copyWith(
            bookmarks: entry.bookmarks
                .where((item) => item.id != bookmark.id)
                .toList(),
          ),
        );
      }
      if (!mounted) return;
      await _updateScoreTabs(
        _scoreTabIds.where((id) => _lookupTab(id) != null).toList(),
      );
      if (!mounted || _entry?.id != score.id) return;
      if (_library.lookup(score.id) case final remaining?) {
        await _openLibraryScore(remaining, startPage: _page);
      } else {
        _playing = null;
        _load(null, null, null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this item.')),
        );
      }
    } finally {
      _finishPicking();
    }
  }

  Widget _readerToolsMenu({bool corner = false}) {
    final items = {
      for (final group in [_ReaderMenu.tools, _ReaderMenu.score])
        for (final item in _readerMenuItems(group)) item.value!: item,
    };
    const sections = [
      (
        'Edit this score',
        [
          (_ReaderDisplay.annotate, Icons.draw_outlined, 'Annotate'),
          (_ReaderDisplay.jumpLinks, Icons.link, 'Links'),
          (_ReaderDisplay.pageActions, Icons.touch_app_outlined, 'Buttons'),
          (_ReaderDisplay.rearrangeScore, Icons.grid_view, 'Rearrange'),
          (_ReaderDisplay.crop, Icons.crop, 'Crop'),
          (_ReaderDisplay.exportPdf, Icons.share_outlined, 'Share'),
        ],
      ),
      (
        'Add scores',
        [
          (_ReaderDisplay.importScore, Icons.file_open_outlined, 'Import PDF'),
          (
            _ReaderDisplay.migrateLibrary,
            Icons.drive_folder_upload_outlined,
            'Import from another app',
          ),
          (_ReaderDisplay.cloudServices, Icons.cloud_outlined, 'Services'),
          (_ReaderDisplay.scanScore, Icons.document_scanner_outlined, 'Scan'),
          (_ReaderDisplay.scoreTemplates, Icons.note_add_outlined, 'Templates'),
        ],
      ),
      (
        'More',
        [
          (_ReaderDisplay.piano, Icons.piano_outlined, 'Piano'),
          (_ReaderDisplay.practiceRecordings, Icons.mic_none, 'Record'),
          (_ReaderDisplay.ensemble, Icons.devices_outlined, 'Ensemble'),
          (
            _ReaderDisplay.practiceActivity,
            Icons.insights,
            'Practice activity',
          ),
          (_ReaderDisplay.librarySync, Icons.sync, 'Device sync'),
          (_ReaderDisplay.libraryBackup, Icons.history, 'Backup & restore'),
          (_ReaderDisplay.support, Icons.help_outline, null),
          (_ReaderDisplay.readerSettings, Icons.settings_outlined, 'Settings'),
        ],
      ),
    ];
    final menu = <Widget>[];
    for (final (heading, actions) in sections) {
      final rows = <Widget>[];
      for (final (action, icon, label) in actions) {
        final existing = items.remove(action);
        final available = switch (action) {
          _ReaderDisplay.annotate => _pages > 0,
          _ReaderDisplay.rearrangeScore => _entry != null && _viewer.isReady,
          _ReaderDisplay.librarySync =>
            _library.storage.persistent &&
                !_restricted(RestrictedTool.connections),
          _ => existing != null,
        };
        if (!available || !_readerActionAllowed(action)) continue;
        final needsScore =
            heading == 'Edit this score' &&
            action != _ReaderDisplay.annotate &&
            action != _ReaderDisplay.exportPdf;
        final enabled =
            (!needsScore || _entry != null) && (existing?.enabled ?? true);
        rows.add(
          MenuItemButton(
            leadingIcon: Icon(icon, size: 20),
            onPressed: enabled ? () => _runReaderDisplayAction(action) : null,
            child: label == null ? existing!.child! : Text(label),
          ),
        );
      }
      if (rows.isEmpty) continue;
      if (menu.isNotEmpty) menu.add(const Divider(height: 8));
      menu.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(heading, style: Theme.of(context).textTheme.labelMedium),
        ),
      );
      menu.addAll(rows);
    }
    if (items.isNotEmpty) {
      menu.add(
        SubmenuButton(
          leadingIcon: const Icon(Icons.more_horiz),
          menuChildren: [
            for (final entry in items.entries)
              MenuItemButton(
                onPressed: entry.value.enabled
                    ? () => _runReaderDisplayAction(entry.key)
                    : null,
                child: entry.value.child!,
              ),
          ],
          child: const Text('Other tools'),
        ),
      );
    }
    return MenuAnchor(
      controller: corner ? _cornerToolsMenuController : null,
      onOpen: () => _lastRightMenu = _CornerMenu.tools,
      style: const MenuStyle(visualDensity: VisualDensity.compact),
      menuChildren: menu,
      child: corner ? const SizedBox(width: 1, height: 1) : null,
      builder: (context, controller, child) =>
          child ??
          IconButton(
            tooltip: ReaderText.tools.of(context),
            icon: const Icon(Icons.work_outline),
            onPressed: _picking
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
          ),
    );
  }

  List<PopupMenuItem<_ReaderDisplay>> _readerMenuItems(_ReaderMenu group) =>
      <PopupMenuItem<_ReaderDisplay>>[
            const PopupMenuItem(
              value: _ReaderDisplay.toolbarShortcuts,
              child: Text('Toolbar shortcuts'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.readerSettings,
              child: Text('Reader settings'),
            ),
            if (!_restricted(RestrictedTool.transfers)) ...[
              const PopupMenuItem(
                value: _ReaderDisplay.migrateLibrary,
                child: Text('Import from another app'),
              ),
              const PopupMenuItem(
                value: _ReaderDisplay.importScore,
                child: Text('Import PDF'),
              ),
              if (!_restricted(RestrictedTool.connections))
                const PopupMenuItem(
                  value: _ReaderDisplay.cloudServices,
                  child: Text('Cloud services'),
                ),
              if (_supportsSharedImport)
                const PopupMenuItem(
                  value: _ReaderDisplay.scanScore,
                  child: Text('Scan sheet music'),
                ),
              const PopupMenuItem(
                value: _ReaderDisplay.scoreTemplates,
                child: Text('Create from template'),
              ),
              if (_library.storage.persistent)
                const PopupMenuItem(
                  value: _ReaderDisplay.libraryBackup,
                  child: Text('Backup & restore'),
                ),
            ],
            PopupMenuItem(
              value: _ReaderDisplay.nowPlaying,
              enabled: _entry != null,
              child: const Text('Now playing'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.findInScore,
              child: Text('Find in score'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.pageNote,
              enabled: _entry != null,
              child: Text(
                _entry?.pageNotes.containsKey(_page) == true
                    ? 'Open page note'
                    : 'Add page note',
              ),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.pageActions,
              enabled: _entry != null,
              child: const Text('On-page actions'),
            ),
            if (ScoreAudioSession.supported)
              PopupMenuItem(
                value: _ReaderDisplay.scoreAudio,
                enabled: _entry != null,
                child: const Text('Linked audio'),
              ),
            if (_supportsSharedImport)
              PopupMenuItem(
                value: _ReaderDisplay.practiceRecordings,
                enabled: _entry != null,
                child: const Text('Practice recordings'),
              ),
            const PopupMenuItem(
              value: _ReaderDisplay.practiceActivity,
              child: Text('Practice activity'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.restrictions,
              child: Text('Shared-device restrictions'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.support,
              child: Text(ReaderText.help.of(context)),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.language,
              child: Text('App language'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.profiles,
              child: Text('Settings profiles'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.assistantConnections,
              child: Text('AI Connections'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.metadataSymbols,
              child: Text('Metadata symbols'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.themeOptions,
              child: Text('Theme and menus'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.maintenance,
              child: Text('Maintenance and reset'),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              const PopupMenuItem(
                value: _ReaderDisplay.appIcon,
                child: Text('Home screen icon'),
              ),
            if (ScoreAudioSession.supported)
              const PopupMenuItem(
                value: _ReaderDisplay.metronome,
                child: Text('Metronome'),
              ),
            if (ScoreAudioSession.supported)
              const PopupMenuItem(
                value: _ReaderDisplay.tuner,
                child: Text('Pitch pipe & tuner'),
              ),
            if (ScoreAudioSession.supported)
              const PopupMenuItem(
                value: _ReaderDisplay.piano,
                child: Text('Piano and MIDI synthesizer'),
              ),
            const PopupMenuItem(
              value: _ReaderDisplay.inputShortcuts,
              child: Text('Input shortcuts'),
            ),
            if (_supportsSharedImport)
              PopupMenuItem(
                value: _ReaderDisplay.faceTurns,
                child: Text(
                  _faceTurns == null ? 'Face gestures' : 'Stop face gestures',
                ),
              ),
            const PopupMenuItem(
              value: _ReaderDisplay.copyMeasure,
              child: Text('Copy measure from PDF'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.pasteMeasure,
              enabled: _measureClipboard != null && _activeInkLayer != null,
              child: const Text('Paste measure'),
            ),
            if (_supportsSharedImport)
              const PopupMenuItem(
                value: _ReaderDisplay.midiDevices,
                child: Text('Pedals and MIDI devices'),
              ),
            if (ScoreAudioSession.supported)
              PopupMenuItem(
                value: _ReaderDisplay.midiAutomation,
                enabled: _entry != null,
                child: const Text('MIDI score automation'),
              ),
            if (!kIsWeb)
              const PopupMenuItem(
                value: _ReaderDisplay.ensemble,
                child: Text('Ensemble sync'),
              ),
            if (_supportsScoreWindows)
              PopupMenuItem(
                value: _ReaderDisplay.scoreWindow,
                enabled: _file != null,
                child: const Text('Open score in another window'),
              ),
            if (_supportsSharedImport)
              PopupMenuItem(
                value: _ReaderDisplay.presentation,
                enabled: _file != null || _presenting,
                child: Text(
                  _presenting
                      ? 'Stop external display'
                      : 'Present on external display',
                ),
              ),
            const PopupMenuItem(
              value: _ReaderDisplay.appearance,
              child: Text('Reading appearance'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.accessibility,
              child: Text('Accessible reader controls'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.reflow,
              child: Text('Score reflow'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.panelOptions,
              child: Text('Sidebar and lists'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.embeddedPdf,
              child: Text('Embedded PDF content'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.fit,
              child: Text('Fit page'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.fittingMode,
              enabled: !_verticalScrolling,
              child: Text('Page fitting · ${_preferences.pageFit.label}'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.scrollMode,
              child: Text('Scrolling display · ${_scrollMode.label}'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.autoScroll,
              enabled: _canAutoScroll,
              child: const Text('Automatic scrolling'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.zoomIn,
              enabled: !_halfPageTurns,
              child: const Text('Zoom in'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.zoomOut,
              enabled: !_halfPageTurns,
              child: const Text('Zoom out'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.previousPage,
              enabled: _previousPage != null,
              child: const Text('Jump back to previous page'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.previousScore,
              enabled:
                  _previousItem != null &&
                  _library.lookup(_previousItem!.id) != null,
              child: const Text('Return to previous score'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.bookmarks,
              enabled: _entry != null,
              child: const Text('Bookmarks'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.jumpLinks,
              enabled: _entry != null,
              child: const Text('Repeat & coda links'),
            ),
            CheckedPopupMenuItem(
              value: _ReaderDisplay.halfTurns,
              enabled: !_verticalScrolling,
              checked: _preferences.halfPageTurns,
              child: const Text('Half-page turns'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.halfSplit,
              enabled: _halfPageTurns && _page < _lastPage,
              child: const Text('Adjust current page split'),
            ),
            CheckedPopupMenuItem(
              value: _ReaderDisplay.halfIndicator,
              enabled: !_verticalScrolling,
              checked: _preferences.halfPageIndicator,
              child: const Text('Show half-page indicator'),
            ),
            if (_preferences.pageFit == ReaderPageFit.standard)
              CheckedPopupMenuItem(
                value: _ReaderDisplay.landscapeWidth,
                enabled: !_verticalScrolling,
                checked: _preferences.landscapeWidth,
                child: const Text('Fit width in landscape'),
              ),
            CheckedPopupMenuItem(
              value: _ReaderDisplay.spreads,
              enabled: !_verticalScrolling,
              checked: _preferences.spreadStep > 0,
              child: const Text('Two-page layout'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.performance,
              child: Text('Performance mode'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.scoreTabs,
              enabled:
                  _appearance.showTabs &&
                  !_savingTabs &&
                  (_entry != null || _library.recent.isNotEmpty),
              child: const Text('Open in new tab'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.exportPdf,
              enabled: _file != null,
              child: const Text('Share or print PDF'),
            ),
            PopupMenuItem(
              value: _ReaderDisplay.crop,
              enabled: _entry != null,
              child: const Text('Crop and straighten'),
            ),
            const PopupMenuItem(
              value: _ReaderDisplay.drawingSettings,
              child: Text('Drawing presets and stylus'),
            ),
            if (_library.storage.persistent)
              PopupMenuItem(
                value: _ReaderDisplay.shareScorePackage,
                enabled: _entry != null,
                child: Text(
                  _itemBookmark == null
                      ? 'Share editable score'
                      : 'Share editable excerpt',
                ),
              ),
            PopupMenuItem(
              value: _ReaderDisplay.shareScoreLink,
              enabled: _entry != null,
              child: Text(
                _itemBookmark == null
                    ? 'Copy score link'
                    : 'Copy bookmark link',
              ),
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
            CheckedPopupMenuItem(
              value: _ReaderDisplay.cleanStartup,
              checked: _preferences.startWithControlsHidden,
              child: const Text('Start with controls hidden'),
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
          ]
          .where(
            (item) =>
                _readerActionAllowed(item.value) &&
                switch (group) {
                  _ReaderMenu.display => _displayActions.contains(item.value),
                  _ReaderMenu.score => _scoreActions.contains(item.value),
                  _ReaderMenu.tools =>
                    !_displayActions.contains(item.value) &&
                        !_scoreActions.contains(item.value),
                },
          )
          .map(
            (item) => group == _ReaderMenu.score && !item.enabled
                ? _explainDisabledScoreAction(item)
                : item,
          )
          .toList();

  PopupMenuItem<_ReaderDisplay> _explainDisabledScoreAction(
    PopupMenuItem<_ReaderDisplay> item,
  ) {
    final reason = switch (item.value) {
      _ReaderDisplay.pasteMeasure =>
        _measureClipboard == null
            ? 'Copy a measure first.'
            : 'Select a visible annotation layer first.',
      _ReaderDisplay.previousPage => 'Turn or jump to another page first.',
      _ReaderDisplay.previousScore => 'Open another score first.',
      _ReaderDisplay.scoreTabs =>
        !_appearance.showTabs
            ? 'Enable the score tab bar in Theme and menus.'
            : _savingTabs
            ? 'Wait for the tab changes to finish saving.'
            : 'Import a score first.',
      _ => 'Open a score from your library first.',
    };
    return PopupMenuItem<_ReaderDisplay>(
      value: item.value,
      enabled: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item.child!,
          Text(
            reason,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

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
        if (_autoScrollTicker.isActive)
          _activeScrollControls()
        else if (_canAutoScroll)
          IconButton(
            tooltip: 'Start automatic scrolling',
            onPressed: _picking ? null : _toggleAutoScroll,
            icon: const Icon(Icons.play_arrow),
          ),
        if (_entry != null)
          IconButton(
            tooltip: 'Now playing',
            onPressed: _picking ? null : _showNowPlaying,
            icon: const Icon(Icons.queue_music),
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
          body: LayoutBuilder(
            builder: (context, space) => GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (space.maxWidth / 175).floor().clamp(1, 5),
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
                          maximumDpi: 90,
                        ),
                      ),
                      Text('Page $page'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    } finally {
      _finishPicking();
    }
    if (mounted && destination != null) _go(destination);
  }

  void _moveMarkupPalette() {
    setState(() => _markupPaletteAtTop = !_markupPaletteAtTop);
    unawaited(
      _library
          .updatePreferences({'markupPaletteAtTop': _markupPaletteAtTop})
          .catchError((Object _) {}),
    );
  }

  Future<void> _clearMarkupPage() async {
    final page = _annotationPage ?? _page;
    final layer = _activeInkLayer;
    final ink = _ink[page];
    if (ink == null || !ink.hasActiveLayerInk) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clear annotations on this page?'),
        content: const Text(
          'This clears the active layer on this page. You can undo it from Markup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (mounted &&
        clear == true &&
        _inking &&
        _activeInkLayer == layer &&
        _ink[page] == ink) {
      ink.clearActiveLayer();
    }
  }

  void _selectMarkupPreset(int index) {
    setState(() {
      _tool = InkTool.pen;
      _stamp = null;
      _shape = null;
    });
    unawaited(_saveDrawing(_drawing.copyWith(selected: index)));
  }

  Widget _markupPalette({required bool wide, bool canMove = false}) => Material(
    color: _rail,
    elevation: 3,
    borderRadius: BorderRadius.circular(12),
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message:
              _inkLayers
                  .where((layer) => layer.id == _activeInkLayer)
                  .firstOrNull
                  ?.name ??
              'No active layer',
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(
              'Page ${_annotationPage ?? _page}',
              style: TextStyle(color: _paper),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous markup page',
          onPressed: (_annotationPage ?? _page) > _firstPage
              ? () => _jumpToPage((_annotationPage ?? _page) - 1)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next markup page',
          onPressed: (_annotationPage ?? _page) < _lastPage
              ? () => _jumpToPage((_annotationPage ?? _page) + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            _stamp ??
                _shape?.label ??
                switch (_tool) {
                  InkTool.pen => 'Pen',
                  InkTool.highlighter => 'Highlighter',
                  InkTool.eraser => 'Eraser',
                  InkTool.text => 'Text',
                  InkTool.selection =>
                    _selectingPdf ? 'PDF selection' : 'Selection',
                },
            style: TextStyle(color: _brass, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: _toggleInk, child: const Text('Done')),
        if (canMove)
          IconButton(
            tooltip: _markupPaletteAtTop
                ? 'Move markup tools to bottom'
                : 'Move markup tools to top',
            onPressed: _moveMarkupPalette,
            icon: Icon(
              _markupPaletteAtTop
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_top,
            ),
          ),
        _toolButton(InkTool.pen, Icons.edit_outlined, 'Pen'),
        if (wide)
          for (final (index, preset) in _drawing.presets.take(3).indexed)
            IconButton(
              tooltip: 'Pen preset: ${preset.name}',
              isSelected:
                  _tool == InkTool.pen &&
                  _stamp == null &&
                  _shape == null &&
                  _drawing.selected == index,
              style:
                  _tool == InkTool.pen &&
                      _stamp == null &&
                      _shape == null &&
                      _drawing.selected == index
                  ? IconButton.styleFrom(
                      backgroundColor: _brass.withValues(alpha: .18),
                    )
                  : null,
              onPressed: () => _selectMarkupPreset(index),
              icon: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(preset.argb),
                  border: Border.all(color: _paper, width: 1),
                ),
              ),
            ),
        if (_tool == InkTool.pen)
          PopupMenuButton<int>(
            tooltip: 'Pen style',
            icon: const Icon(Icons.color_lens_outlined),
            onSelected: (index) {
              if (index < 0) {
                _configureDrawing();
              } else {
                _saveDrawing(_drawing.copyWith(selected: index));
              }
            },
            itemBuilder: (_) => [
              for (final (index, preset) in _drawing.presets.indexed)
                CheckedPopupMenuItem(
                  value: index,
                  checked: _drawing.selected == index,
                  child: Text(preset.name),
                ),
              const PopupMenuItem(
                value: -1,
                child: Text('Edit presets and stylus'),
              ),
            ],
          ),
        _toolButton(InkTool.highlighter, Icons.highlight, 'Highlighter'),
        _toolButton(InkTool.eraser, Icons.backspace_outlined, 'Erase strokes'),
        _toolButton(InkTool.text, Icons.text_fields, 'Text annotation'),
        for (final stamp in _favoriteStamps)
          InputChip(
            label: Text(stamp),
            selected: _stamp == stamp,
            onPressed: () => _selectStamp(stamp),
            deleteButtonTooltipMessage: 'Remove favorite stamp',
            onDeleted: () => _saveFavoriteStamps(
              _favoriteStamps.where((item) => item != stamp).toList(),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Notation stamps',
          icon: Icon(Icons.music_note, color: _stamp == null ? null : _brass),
          onSelected: _selectStamp,
          itemBuilder: (_) => [
            if (_stamp case final stamp?
                when !_favoriteStamps.contains(stamp) &&
                    _favoriteStamps.length < 4)
              PopupMenuItem(
                onTap: () => _saveFavoriteStamps([..._favoriteStamps, stamp]),
                child: Text('Favorite $stamp'),
              ),
            const PopupMenuItem(
              value: '',
              child: Text('Create personal stamp'),
            ),
            for (final stamp in _personalStamps)
              PopupMenuItem(value: stamp, child: Text(stamp)),
            for (final entry in const {
              '𝄐': 'Fermata',
              '♯': 'Sharp',
              '♭': 'Flat',
              '♮': 'Natural',
              'pp': 'Pianissimo',
              'p': 'Piano',
              'mf': 'Mezzo-forte',
              'f': 'Forte',
              'ff': 'Fortissimo',
              '>': 'Accent',
              '𝄋': 'Segno',
              '𝄌': 'Coda',
            }.entries)
              PopupMenuItem(
                value: entry.key,
                child: Text('${entry.key}   ${entry.value}'),
              ),
            for (final entry in additionalMusicStamps.entries)
              PopupMenuItem(
                value: entry.key,
                child: Text('${entry.key}   ${entry.value}'),
              ),
          ],
        ),
        if (_favoriteShape case final favorite?)
          TextButton.icon(
            onPressed: () => _selectMarkupShape(favorite),
            icon: const Icon(Icons.star_outline),
            label: Text(favorite.label),
          ),
        PopupMenuButton<InkShape>(
          tooltip: 'Draw shape',
          icon: Icon(
            Icons.interests_outlined,
            color: _shape == null ? null : _brass,
          ),
          onSelected: _selectMarkupShape,
          itemBuilder: (_) => [
            for (final shape in InkShape.values)
              PopupMenuItem(
                value: shape,
                child: Text(
                  shape == InkShape.ruler ? 'Ruler · 15° steps' : shape.label,
                ),
              ),
            if (_shape case final shape? when shape != _favoriteShape)
              PopupMenuItem(
                onTap: () => _setFavoriteShape(shape),
                child: Text('Favorite ${shape.label}'),
              ),
            if (_favoriteShape != null)
              PopupMenuItem(
                onTap: () => _setFavoriteShape(null),
                child: const Text('Remove favorite'),
              ),
          ],
        ),
        PopupMenuButton<bool>(
          tooltip: 'Selection tool',
          icon: Icon(
            Icons.select_all,
            color: _tool == InkTool.selection ? _brass : null,
          ),
          onSelected: (freeform) => setState(() {
            _tool = InkTool.selection;
            _stamp = null;
            _shape = null;
            _freeformSelection = freeform;
            _pdfSelection = [];
            _pdfSelectionPage = null;
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('Rectangle selection')),
            PopupMenuItem(value: true, child: Text('Freeform selection')),
          ],
        ),
        IconButton(
          tooltip: _showRuler ? 'Hide ruler guide' : 'Show ruler guide',
          isSelected: _showRuler,
          icon: const Icon(Icons.straighten),
          onPressed: () => setState(() => _showRuler = !_showRuler),
        ),
        IconButton(
          tooltip: 'Select PDF passage',
          icon: const Icon(Icons.document_scanner_outlined),
          isSelected: _selectingPdf && !_placingMeasure,
          onPressed: _pdfSelectionAvailable && !_copyingMeasure
              ? () => _selectPdf()
              : null,
        ),
        if (_tool == InkTool.selection && _selectingPdf) ...[
          if (_placingMeasure)
            const Text('Tap the score to place')
          else ...[
            IconButton(
              tooltip: 'Copy selected music',
              icon: const Icon(Icons.content_copy),
              onPressed: _pdfSelectionBounds != null && !_copyingMeasure
                  ? () => _copyPdfSelection(cut: false)
                  : null,
            ),
            IconButton(
              tooltip: 'Cut selected music',
              icon: const Icon(Icons.content_cut),
              onPressed:
                  _pdfSelectionBounds != null &&
                      !_copyingMeasure &&
                      _activeInkLayer != null
                  ? () => _copyPdfSelection(cut: true)
                  : null,
            ),
          ],
        ],
        if (_ink[_annotationPage ?? _page] case final ink?
            when _tool == InkTool.selection && !_selectingPdf)
          _selectionActions(ink),
        if ((_measureClipboard != null || _selectingPdf) && !_placingMeasure)
          IconButton(
            tooltip: 'Place copied music',
            icon: const Icon(Icons.content_paste),
            onPressed:
                _measureClipboard != null &&
                    _activeInkLayer != null &&
                    !_copyingMeasure
                ? () => _selectPdf(paste: true)
                : null,
          ),
        IconButton(
          tooltip: 'Annotation layers',
          onPressed: _showInkLayers,
          icon: const Icon(Icons.layers_outlined),
        ),
        IconButton(
          tooltip: 'Clear active layer on this page',
          onPressed: _activeInkLayer == null ? null : _clearMarkupPage,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        Semantics(
          label: 'Allow finger drawing',
          child: ChoiceChip(
            label: const Text('Finger'),
            selected: _allowFinger,
            onSelected: (enabled) =>
                setState(() => _fingerDrawingOverride = enabled),
          ),
        ),
        IconButton(
          tooltip: 'Undo stroke',
          onPressed: () => _ink[_annotationPage ?? _page]?.undo(),
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo stroke',
          onPressed: () => _ink[_annotationPage ?? _page]?.redo(),
          icon: const Icon(Icons.redo),
        ),
      ],
    ),
  );

  void _selectMarkupShape(InkShape shape) => setState(() {
    _shape = shape;
    _stamp = null;
    _tool = InkTool.pen;
  });

  Future<void> _saveFavoriteStamps(List<String> stamps) async {
    try {
      await _library.updatePreferences({'favoriteStamps': stamps});
      if (mounted) setState(() => _favoriteStamps = stamps);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save favorite stamps.')),
        );
      }
    }
  }

  Future<void> _setFavoriteShape(InkShape? shape) async {
    try {
      await _library.updatePreferences({'favoriteInkShape': shape?.name});
      if (mounted) setState(() => _favoriteShape = shape);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the favorite shape.')),
        );
      }
    }
  }

  Widget _markupOverlay() => LayoutBuilder(
    builder: (context, space) {
      final viewport = Size(space.maxWidth, space.maxHeight);
      var leftGutter = 0.0;
      var rightGutter = 0.0;
      if (_viewer.isReady && !_verticalScrolling && _spreadStep == 0) {
        final page = _viewer.layout.pageLayouts[_page - 1];
        leftGutter = _viewer.documentToLocal(page.topLeft).dx;
        rightGutter =
            viewport.width - _viewer.documentToLocal(page.bottomRight).dx;
      }
      final gutter = math.max(leftGutter, rightGutter);
      if (viewport.width >= 720 && gutter >= 152) {
        return Align(
          alignment: rightGutter >= leftGutter
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(220, gutter - 16),
                maxHeight: math.max(0, viewport.height - 16),
              ),
              child: SingleChildScrollView(child: _markupPalette(wide: true)),
            ),
          ),
        );
      }
      return Align(
        alignment: _markupPaletteAtTop
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: viewport.height * .45),
            child: SingleChildScrollView(
              child: _markupPalette(wide: viewport.width >= 720, canMove: true),
            ),
          ),
        ),
      );
    },
  );

  String _scrubLabel(int page) {
    ScoreBookmark? section;
    for (final bookmark in _entry?.bookmarks ?? const <ScoreBookmark>[]) {
      final end = bookmark.endPage;
      if (bookmark.page < _firstPage ||
          bookmark.page > page ||
          end != null && page > end)
        continue;
      if (section == null || bookmark.page > section.page) section = bookmark;
    }
    return section == null ? 'Page $page' : 'Page $page · ${section.title}';
  }

  Widget _footer() {
    final fitWidth = _verticalScrolling
        ? _scrollMode == ReaderScrollMode.fitWidth
        : _readingAtWidth;
    final canScrub = _pages > 0 && _lastPage - _firstPage >= 6;
    final turns = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _verticalScrolling && !_inking
              ? 'Scroll up'
              : _page == _firstPage && _hasPreviousScore && !_halfPreview
              ? 'Previous score'
              : ReaderText.previous.of(context),
          onPressed:
              _pages == 0 ||
                  ((!_verticalScrolling || _inking) &&
                      _page <= _firstPage &&
                      !_halfPreview &&
                      !_hasPreviousScore)
              ? null
              : () => _turn(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Tooltip(
          message: 'Page thumbnails',
          child: TextButton.icon(
            onPressed: _pages == 0 ? null : _showThumbnails,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.grid_view_outlined),
            label: Text(
              _pages == 0 ? '–' : '${(_seek ?? _page).round()} / $_pages',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          tooltip: _verticalScrolling && !_inking
              ? 'Scroll down'
              : _page == _lastPage && _hasNextScore
              ? 'Next score'
              : ReaderText.next.of(context),
          onPressed:
              _pages == 0 ||
                  ((!_verticalScrolling || _inking) &&
                      _page >= _lastPage &&
                      !_hasNextScore)
              ? null
              : () => _turn(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<bool>(
          tooltip: 'Fit mode: ${fitWidth ? 'Fit width' : 'Fit page'}',
          enabled:
              _pages > 0 && !_picking && !_halfPageTurns && _spreadStep == 0,
          icon: const Icon(Icons.aspect_ratio),
          onSelected: _quickFit,
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: false,
              checked: !fitWidth,
              child: const Text('Fit page'),
            ),
            CheckedPopupMenuItem(
              value: true,
              checked: fitWidth,
              child: const Text('Fit width'),
            ),
          ],
        ),
      ],
    );
    final slider = canScrub
        ? Slider(
            value: (_seek ?? _page.toDouble()).clamp(
              _firstPage.toDouble(),
              _lastPage.toDouble(),
            ),
            min: _firstPage.toDouble(),
            max: _lastPage.toDouble(),
            divisions: _lastPage - _firstPage,
            label: _scrubLabel((_seek ?? _page).round()),
            semanticFormatterCallback: (value) => _scrubLabel(value.round()),
            onChanged: (value) => setState(() => _seek = value),
            onChangeEnd: (value) {
              setState(() => _seek = null);
              _go(value.round());
              _focus.requestFocus();
            },
          )
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Material(
        color: _rail,
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, space) {
            final separateSlider = slider != null && space.maxWidth < 420;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    turns,
                    if (slider != null && !separateSlider)
                      Expanded(child: slider),
                    tools,
                  ],
                ),
                if (separateSlider) slider,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _selectionActions(PageInk ink) => ListenableBuilder(
    listenable: ink,
    builder: (context, _) => PopupMenuButton<String>(
      tooltip: 'Selection actions',
      icon: const Icon(Icons.content_paste),
      onSelected: (action) {
        if (action == 'paste') {
          ink.pasteSelection(_inkClipboard);
          return;
        }
        if (action == 'copy' || action == 'cut') {
          setState(() => _inkClipboard = ink.copySelection());
        }
        if (action == 'cut' || action == 'delete') ink.deleteSelection();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'copy',
          enabled: ink.hasSelection,
          child: const Text('Copy'),
        ),
        PopupMenuItem(
          value: 'cut',
          enabled: ink.hasSelection,
          child: const Text('Cut'),
        ),
        PopupMenuItem(
          value: 'paste',
          enabled: _inkClipboard.isNotEmpty,
          child: const Text('Paste'),
        ),
        PopupMenuItem(
          value: 'delete',
          enabled: ink.hasSelection,
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  Widget _toolButton(InkTool tool, IconData icon, String label) => IconButton(
    tooltip: label,
    isSelected: _tool == tool && _stamp == null && _shape == null,
    style: _tool == tool && _stamp == null && _shape == null
        ? IconButton.styleFrom(backgroundColor: _brass.withValues(alpha: .18))
        : null,
    color: _tool == tool && _stamp == null && _shape == null ? _brass : null,
    onPressed: () => setState(() {
      _tool = tool;
      _stamp = null;
      _shape = null;
    }),
    icon: Icon(icon),
  );
}

class _PageCropClipper extends CustomClipper<Rect> {
  _PageCropClipper(this.crop);
  final PageCrop? crop;

  @override
  Rect getClip(Size size) =>
      crop?.within(Offset.zero & size) ?? (Offset.zero & size);

  @override
  bool shouldReclip(_PageCropClipper oldClipper) => crop != oldClipper.crop;
}

class _EdgeTapTracker {
  static const _slop = 12.0;
  static const _maximumDuration = Duration(milliseconds: 300);
  final _pointers = <int>{};
  PointerDownEvent? _start;
  int _step = 0;
  bool _moved = false;
  bool _canAdvance = false;
  bool _allowBackward = false;
  bool handled = false;

  static int direction(double x, double width) {
    if (x < width * .24) return -1;
    if (x > width * .76) return 1;
    return 0;
  }

  void down(
    PointerDownEvent event,
    double width, {
    required bool canAdvance,
    required bool allowBackward,
  }) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1) {
      _start = null;
      return;
    }
    handled = false;
    _moved = false;
    _canAdvance = canAdvance;
    _allowBackward = allowBackward;
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

  (int, int) up(PointerUpEvent event) {
    final start = _start;
    cancel(event);
    if (start == null || start.pointer != event.pointer) return (0, 0);
    final delta = event.position - start.position;
    if (_canAdvance && delta.dx < -45 && -delta.dx > delta.dy.abs() * 1.5) {
      return (0, 1);
    }
    if (_allowBackward && delta.dx > 45 && delta.dx > delta.dy.abs() * 1.5) {
      return (0, -1);
    }
    if (_step == 0 ||
        _moved ||
        event.timeStamp - start.timeStamp > _maximumDuration ||
        delta.distance > _slop)
      return (0, 0);
    handled = true;
    return (_step, 0);
  }

  void cancel(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_start?.pointer == event.pointer) _start = null;
  }
}

Future<void> _addToSetlist(
  BuildContext context,
  ScoreLibrary library,
  String scoreId,
) async {
  final setlists = library.setlists;
  final create = setlists.isEmpty;
  var name = '';
  final destination = await showDialog<String>(
    context: context,
    builder: (dialog) {
      if (create) {
        return StatefulBuilder(
          builder: (_, update) => AlertDialog(
            title: const Text('Create a setlist'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Setlist name'),
              onChanged: (value) => update(() => name = value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: name.isEmpty
                    ? null
                    : () => Navigator.pop(dialog, name),
                child: const Text('Create and add score'),
              ),
            ],
          ),
        );
      }
      return SimpleDialog(
        title: const Text('Add score to setlist'),
        children: [
          for (final list in setlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, list.id),
              child: Text(list.name),
            ),
        ],
      );
    },
  );
  if (destination == null || !context.mounted) return;
  try {
    if (create) {
      await library.saveSetlist(
        Setlist(ScoreLibrary.newRecordId(), destination, [scoreId]),
      );
    } else {
      await library.appendToSetlist(destination, scoreId);
    }
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Score added to setlist.')));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add the score to the setlist.'),
        ),
      );
  }
}

class _LibraryScreen extends StatefulWidget {
  const _LibraryScreen({
    required this.library,
    required this.scores,
    required this.setlists,
    required this.persistent,
    required this.canScan,
    required this.canSync,
    required this.transferRestricted,
    required this.connectionsRestricted,
    required this.onScoreQueue,
    required this.onPinScore,
    required this.canOpenTabs,
    required this.compact,
    required this.metadataIconKeys,
    required this.focusSearch,
    this.revealScoreId,
    required this.canSearchScore,
    required this.browseState,
    required this.onBrowseState,
  });

  final List<ScoreEntry> scores;
  final ScoreLibrary library;
  final List<Setlist> setlists;
  final bool persistent;
  final bool canScan;
  final bool canSync;
  final bool transferRestricted;
  final bool connectionsRestricted;
  final ValueChanged<List<String>> onScoreQueue;
  final Future<void> Function(String) onPinScore;
  final bool canOpenTabs;
  final bool compact;
  final Map<String, String> metadataIconKeys;
  final bool focusSearch;
  final String? revealScoreId;
  final bool canSearchScore;
  final Map<String, dynamic> browseState;
  final ValueChanged<Map<String, dynamic>> onBrowseState;

  @override
  State<_LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<_LibraryScreen> {
  Future<void> _openBookmarkRange(ScoreEntry score) async {
    final ranges = score.bookmarks.where((bookmark) => bookmark.isItem).toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    final selected = await showDialog<ScoreBookmark>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(score.title),
        children: [
          for (final range in ranges)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, range),
              child: Text(
                '${range.title} · Pages ${range.page}–${range.endPage}',
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    widget.onScoreQueue([
      for (final range in ranges) range.selectionId(score.id),
    ]);
    Navigator.pop(context, 'bookmark:${score.id}:${selected.id}');
  }

  LibrarySearchOptions _searchOptions = const LibrarySearchOptions();
  late final ScrollController _libraryScroll;

  @override
  void initState() {
    super.initState();
    final saved = widget.focusSearch || widget.revealScoreId != null
        ? const <String, dynamic>{}
        : widget.browseState;
    _gridView = saved['gridView'] == true;
    if (saved['browseCategory'] case final String field
        when _browseSections.containsKey(field)) {
      _browseCategory = field;
      if (saved['browseCategoryValue'] case final String value) {
        _browseCategoryValue = value;
      }
    }
    if (saved['sort'] case final String sort
        when _sortLabels.containsKey(sort)) {
      _browseBy = sort;
    }
    if (saved['collection'] case final String name
        when widget.library.collections.contains(name)) {
      _collection = name;
      _excludeCollection = saved['exclude'] == true;
    }
    _unassigned = saved['unassigned'] == true;
    _filters.addAll(_readFilters(saved['filters']));
    if (saved['filterField'] case final String field
        when _filters.isEmpty && _fields.containsKey(field)) {
      if (saved['category'] case final String value when value.isNotEmpty) {
        _filters[field] = value;
      }
    }
    if (saved['filterPresets'] case final Map presets) {
      for (final entry in presets.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final filters = _readFilters(value['filters']);
        final sort = value['sort'];
        if (entry.key is String && filters.isNotEmpty) {
          _filterPresets[entry.key as String] = (
            filters: filters,
            sort: sort is String && _sortLabels.containsKey(sort)
                ? sort
                : 'Recent',
          );
        }
      }
    }
    final offset = saved['offset'];
    _browseOffset = offset is num && offset.isFinite
        ? math.max(0, offset.toDouble())
        : 0;
    _libraryScroll = ScrollController(
      keepScrollOffset: false,
      initialScrollOffset: widget.focusSearch ? 0 : _browseOffset,
    );
    unawaited(_restoreSearchOptions());
  }

  @override
  void dispose() {
    if (!widget.focusSearch) _saveBrowseState();
    _libraryScroll.dispose();
    super.dispose();
  }

  void _saveBrowseState() {
    if (widget.revealScoreId != null) return;
    widget.onBrowseState({
      'sort': _browseBy,
      'gridView': _gridView,
      'browseCategory': _browseCategory,
      'browseCategoryValue': _browseCategoryValue,
      'collection': _collection,
      'exclude': _excludeCollection,
      'unassigned': _unassigned,
      'filters': Map.of(_filters),
      'filterPresets': {
        for (final entry in _filterPresets.entries)
          entry.key: {'filters': entry.value.filters, 'sort': entry.value.sort},
      },
      'offset': _browseOffset,
    });
  }

  double _browseOffset = 0;

  Future<void> _restoreSearchOptions() async {
    try {
      final prefs = await widget.library.storage.readPreferences();
      if (mounted)
        setState(
          () => _searchOptions = LibrarySearchOptions.fromJson(
            prefs['searchOptions'],
          ),
        );
    } catch (_) {
      // Default sorting remains available if the preference file is unavailable.
    }
  }

  Future<void> _configureSearchOptions() async {
    final result = await chooseSearchOptions(context, _searchOptions);
    if (!mounted || result == null) return;
    try {
      await widget.library.updatePreferences({
        'searchOptions': result.toJson(),
      });
      if (mounted) setState(() => _searchOptions = result);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save search preferences.')),
        );
    }
  }

  String _query = '';
  String? _browseLetter;
  String _browseBy = 'Recent';
  bool _gridView = false;
  String? _browseCategory;
  String? _browseCategoryValue;
  final Map<String, Future<Uint8List?>> _scorePreviews = {};
  String? _filterField;
  final Map<String, String> _filters = {};
  final Map<String, ({Map<String, String> filters, String sort})>
  _filterPresets = {};
  String? _collection;
  bool _excludeCollection = false;
  bool _unassigned = false;
  bool _draggingScore = false;

  void _showDragTargets(bool visible) {
    if (mounted && _draggingScore != visible) {
      setState(() => _draggingScore = visible);
    }
  }

  Widget _scoreDrop(String label, IconData icon, ValueChanged<String> drop) =>
      Expanded(
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              widget.library.lookup(details.data) != null,
          onAcceptWithDetails: (details) => drop(details.data),
          builder: (context, hovering, _) => Container(
            margin: const EdgeInsetsDirectional.only(end: 6),
            height: 44,
            decoration: BoxDecoration(
              color: hovering.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _dropIntoSetlist(String scoreId) =>
      _addToSetlist(context, widget.library, scoreId);

  Future<void> _copyLibraryScore(ScoreEntry score) async {
    try {
      await writeScoreClipboard((
        scope: 'library',
        id: score.id,
        name: score.title,
        move: false,
      ));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Score copied. Paste it in a setlist.')),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy this score.')),
        );
    }
  }

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
      _filterField = null;
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

  Future<void> _trashScore(ScoreEntry score) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${score.title}?'),
        content: const Text(
          'You can recover this score from Backup & restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Move to Recently deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.library.trashScores([score.id]);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete the score.')),
        );
      }
    }
  }

  static const _fields = {
    'Composer': 'composer',
    'Genre': 'genre',
    'Label': 'label',
    'Tag': 'tags',
    'Key': 'key',
    'Rating': 'rating',
    'Difficulty': 'difficulty',
  };

  static const _sortLabels = {
    'Recent': 'Recently opened',
    'Title': 'Title',
    'Newest': 'Newest added',
    'Composer': 'Composer',
    'Genre': 'Genre',
    'Rating': 'Rating (highest first)',
    'Key': 'Key',
    'Tempo': 'Tempo',
    'Duration': 'Duration',
  };

  Future<Uint8List?> _preview(ScoreEntry score) {
    if (_scorePreviews.length >= 64 && !_scorePreviews.containsKey(score.id)) {
      _scorePreviews.remove(_scorePreviews.keys.first);
    }
    return _scorePreviews.putIfAbsent(
      score.id,
      () => renderLibraryScorePreview(
        widget.library,
        score,
      ).then((preview) => preview?.image).catchError((Object _) => null),
    );
  }

  static const _browseSections = {
    'Composer': 'Composers',
    'Genre': 'Genres',
    'Label': 'Labels',
    'Tag': 'Tags',
  };

  void _showCategory(String? field, [String? value]) {
    if (_libraryScroll.hasClients) _libraryScroll.jumpTo(0);
    setState(() {
      _browseCategory = field;
      _browseCategoryValue = value;
      _browseOffset = 0;
    });
  }

  Widget _categoryNavigation() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (field, label) in [
          (null, 'All scores'),
          ..._browseSections.entries.map((entry) => (entry.key, entry.value)),
        ])
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              selected: _browseCategory == field,
              label: Text(label),
              onSelected: (_) => _showCategory(field),
            ),
          ),
      ],
    ),
  );

  Widget _scoreOptions(ScoreEntry score) => PopupMenuButton<String>(
    tooltip: 'Options for ${score.title}',
    onSelected: (action) {
      if (action == 'setlist') {
        _dropIntoSetlist(score.id);
      } else if (action == 'libraries') {
        _assignCollections(score);
      } else if (action == 'ranges') {
        _openBookmarkRange(score);
      } else if (action == 'tab-copy') {
        Navigator.pop(context, 'tab-copy:${score.id}');
      } else if (action == 'tab') {
        Navigator.pop(context, 'tab:${score.id}');
      } else if (action == 'copy') {
        _copyLibraryScore(score);
      } else if (action == 'trash') {
        _trashScore(score);
      } else if (action == 'extract') {
        Navigator.pop(context, 'extract:${score.id}');
      } else if (action == 'rearrange') {
        Navigator.pop(context, 'rearrange:${score.id}');
      } else if (action == 'clone') {
        Navigator.pop(context, 'clone:${score.id}');
      } else {
        Navigator.pop(context, 'edit:${score.id}');
      }
    },
    itemBuilder: (_) => [
      if (widget.canOpenTabs)
        const PopupMenuItem(value: 'tab', child: Text('Open in new tab')),
      if (widget.canOpenTabs)
        const PopupMenuItem(
          value: 'tab-copy',
          child: Text('Open in another tab'),
        ),
      if (score.bookmarks.any((bookmark) => bookmark.isItem))
        const PopupMenuItem(
          value: 'ranges',
          child: Text('Open bookmarked range'),
        ),
      const PopupMenuItem(value: 'setlist', child: Text('Add to setlist')),
      const PopupMenuItem(value: 'copy', child: Text('Copy to clipboard')),
      const PopupMenuItem(
        value: 'details',
        child: Text('Rename or edit details'),
      ),
      const PopupMenuItem(
        value: 'libraries',
        child: Text('Assign to libraries'),
      ),
      const PopupMenuItem(value: 'trash', child: Text('Delete score')),
      if (!widget.transferRestricted)
        const PopupMenuItem(value: 'extract', child: Text('Extract pages')),
      const PopupMenuItem(value: 'rearrange', child: Text('Rearrange pages')),
      const PopupMenuItem(value: 'clone', child: Text('Duplicate score')),
    ],
  );

  void _openListedScore(ScoreEntry score, List<ScoreEntry> visible) {
    widget.onScoreQueue([for (final item in visible) item.id]);
    Navigator.pop(context, score.id);
  }

  String _scoreByline(ScoreEntry score) => [
    if (score.metadata['composer'] case final value? when value.isNotEmpty)
      value,
    if (score.metadata['tempo'] case final value? when value.isNotEmpty)
      '$value BPM',
  ].join(' · ');

  static Map<String, String> _readFilters(Object? source) => {
    if (source is Map)
      for (final field in _fields.keys)
        if (source[field] case final String value when value.isNotEmpty)
          field: value,
  };

  Future<void> _saveFilterPreset() async {
    String name = '';
    final saved = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save metadata filter'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Filter name'),
          onChanged: (value) => name = value,
          onSubmitted: (value) => Navigator.pop(dialog, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, name.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || saved == null || saved.isEmpty) return;
    setState(
      () =>
          _filterPresets[saved] = (filters: Map.of(_filters), sort: _browseBy),
    );
    _saveBrowseState();
  }

  Future<void> _chooseFilterPreset() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Saved metadata filters'),
        children: [
          for (final name in _filterPresets.keys)
            ListTile(
              title: Text(name),
              onTap: () => Navigator.pop(dialog, name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete saved filter $name',
                onPressed: () {
                  setState(() => _filterPresets.remove(name));
                  _saveBrowseState();
                  Navigator.pop(dialog);
                },
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    final preset = _filterPresets[selected];
    if (preset == null) return;
    setState(() {
      _filters
        ..clear()
        ..addAll(preset.filters);
      _browseBy = preset.sort;
      _filterField = null;
    });
    _saveBrowseState();
  }

  Iterable<String> _categories(ScoreEntry score, String? field) =>
      (score.metadata[_fields[field]] ?? '')
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
    final reveal = widget.revealScoreId;
    if (reveal != null) {
      final index = inCollection.indexWhere((score) => score.id == reveal);
      if (index > 0) inCollection.insert(0, inCollection.removeAt(index));
    }
    final categories =
        inCollection
            .expand((score) => _categories(score, _filterField))
            .toSet()
            .toList()
          ..sort();
    final categoryCounts = <String, int>{};
    if (_browseCategory != null) {
      for (final score in inCollection) {
        for (final category in _categories(score, _browseCategory).toSet()) {
          categoryCounts.update(
            category,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    final categoryValue = categoryCounts.containsKey(_browseCategoryValue)
        ? _browseCategoryValue
        : null;
    final browsingCategories = _browseCategory != null && categoryValue == null;
    final categoryNames = [
      for (final name in categoryCounts.keys)
        if (name.toLowerCase().contains(_query)) name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selected = _filters[_filterField];
    final selectedCategory = categories.contains(selected) ? selected : null;
    var visible = inCollection
        .where(
          (score) => [
            score.title,
            ...score.metadata.values,
          ].any((value) => value.toLowerCase().contains(_query)),
        )
        .where(
          (score) => _filters.entries.every(
            (filter) => _categories(score, filter.key).contains(filter.value),
          ),
        )
        .where(
          (score) =>
              categoryValue == null ||
              _categories(score, _browseCategory).contains(categoryValue),
        )
        .toList();
    if (_browseBy != 'Recent') {
      visible.sort((a, b) {
        final field = _fields[_browseBy] ?? _browseBy.toLowerCase();
        final av = a.metadata[field] ?? '';
        final bv = b.metadata[field] ?? '';
        final order = switch (_browseBy) {
          'Newest' => (b.addedAt?.millisecondsSinceEpoch ?? -1).compareTo(
            a.addedAt?.millisecondsSinceEpoch ?? -1,
          ),
          'Rating' => (double.tryParse(bv) ?? 0).compareTo(
            double.tryParse(av) ?? 0,
          ),
          'Tempo' => (double.tryParse(av) ?? double.infinity).compareTo(
            double.tryParse(bv) ?? double.infinity,
          ),
          'Duration' =>
            (parseScoreDuration(av)?.inSeconds ?? double.infinity).compareTo(
              parseScoreDuration(bv)?.inSeconds ?? double.infinity,
            ),
          'Title' => 0,
          _ => av.toLowerCase().compareTo(bv.toLowerCase()),
        };
        return order != 0
            ? order
            : _searchOptions
                  .titleKey(a.title)
                  .compareTo(_searchOptions.titleKey(b.title));
      });
    } else if (_query.isEmpty &&
        categoryValue == null &&
        _filters.isEmpty &&
        _searchOptions.recentLimit > 0 &&
        visible.length > _searchOptions.recentLimit) {
      visible.removeRange(_searchOptions.recentLimit, visible.length);
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
              'import': ReaderText.importPdf.of(context),
              'create-template': 'Create from template',
              'import-text': 'Import text or Word document',
              'setlists': ReaderText.setlists.of(context),
              'support': ReaderText.help.of(context),
              if (widget.persistent) 'backup': 'Backup & restore',
            }.entries
            .where(
              (entry) =>
                  _query.isNotEmpty &&
                  (!widget.transferRestricted ||
                      !const {
                        'import',
                        'create-template',
                        'import-text',
                        'backup',
                      }.contains(entry.key)) &&
                  entry.value.toLowerCase().contains(_query),
            )
            .toList();
    String initial(ScoreEntry score) {
      final title = score.title.trimLeft();
      if (title.isEmpty) return '#';
      final letter = String.fromCharCode(title.runes.first).toUpperCase();
      return RegExp(r'^\p{L}$', unicode: true).hasMatch(letter) ? letter : '#';
    }

    final letters =
        _browseBy == 'Title' &&
            _query.isEmpty &&
            !browsingCategories &&
            visible.length >= 40
        ? (visible.map(initial).toSet().toList()..sort())
        : const <String>[];
    if (letters.contains(_browseLetter)) {
      visible = visible
          .where((score) => initial(score) == _browseLetter)
          .toList();
    }
    final matchingBookmarks = [
      if (_query.isNotEmpty ||
          !_searchOptions.hidden.contains(LibraryResultGroup.bookmarks))
        for (final score in inCollection)
          if (categoryValue == null ||
              _categories(score, _browseCategory).contains(categoryValue))
            for (final bookmark in score.bookmarks)
              if ((bookmark.isItem || _query.isNotEmpty) &&
                  bookmark.title.toLowerCase().contains(_query))
                (score, bookmark),
    ];
    final groups = {
      LibraryResultGroup.scores: visible.length,
      LibraryResultGroup.bookmarks: matchingBookmarks.length,
      LibraryResultGroup.setlists: matchingSets.length,
      LibraryResultGroup.actions: actions.length,
    };
    final indices =
        (_query.isEmpty ? const LibrarySearchOptions() : _searchOptions)
            .orderedResults(groups);
    final showGrid =
        _gridView &&
        !widget.focusSearch &&
        (_query.isEmpty ||
            (matchingBookmarks.isEmpty &&
                matchingSets.isEmpty &&
                actions.isEmpty));
    final grid = showGrid && visible.isNotEmpty
        ? GridView.builder(
            controller: _libraryScroll,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 210,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final score = visible[index];
              return LibraryScorePreview(
                key: ValueKey(score.id),
                title: score.title,
                subtitle: _scoreByline(score),
                preview: _preview(score),
                onOpen: () => _openListedScore(score, visible),
                onEdit: () => Navigator.pop(context, 'edit:${score.id}'),
                options: _scoreOptions(score),
              );
            },
          )
        : null;
    final categoryList = browsingCategories
        ? ListView.builder(
            controller: _libraryScroll,
            itemCount: categoryNames.isEmpty ? 1 : categoryNames.length,
            itemBuilder: (context, index) {
              if (categoryNames.isEmpty) {
                return const ListTile(title: Text('No matching categories.'));
              }
              final name = categoryNames[index];
              return ListTile(
                title: Text(name),
                subtitle: Text('${categoryCounts[name]} scores'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCategory(_browseCategory, name),
              );
            },
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        title: _draggingScore
            ? Row(
                children: [
                  if (widget.canOpenTabs)
                    _scoreDrop('Pin tab', Icons.tab, widget.onPinScore),
                  if (widget.setlists.isNotEmpty)
                    _scoreDrop('Setlist', Icons.queue_music, _dropIntoSetlist),
                ],
              )
            : Text(
                widget.focusSearch
                    ? 'Search all scores'
                    : _unassigned
                    ? 'Unassigned scores'
                    : _collection == null
                    ? ReaderText.library.of(context)
                    : _excludeCollection
                    ? 'Outside $_collection'
                    : _collection!,
              ),
        actions: [
          IconButton(
            tooltip: ReaderText.help.of(context),
            onPressed: () => Navigator.pop(context, 'support'),
            icon: const Icon(Icons.help_outline),
          ),
          if (!widget.focusSearch)
            IconButton(
              tooltip: 'Libraries',
              onPressed: _chooseCollection,
              icon: const Icon(Icons.folder_copy_outlined),
            ),
          IconButton(
            tooltip: 'Select scores',
            onPressed: widget.scores.isEmpty
                ? null
                : () => Navigator.pop(context, 'batch'),
            icon: const Icon(Icons.checklist),
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
                    autofocus: widget.focusSearch,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: ReaderText.search.of(context),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  if (!widget.focusSearch) _categoryNavigation(),
                  if (categoryValue != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => _showCategory(_browseCategory),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(categoryValue),
                      ),
                    ),
                  if (widget.focusSearch)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: widget.canSearchScore
                            ? () => Navigator.pop(
                                context,
                                'find-in-current-score',
                              )
                            : null,
                        icon: const Icon(Icons.find_in_page_outlined),
                        label: const Text('In this score'),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Sort library',
                        initialValue: _browseBy,
                        onSelected: (value) => setState(() {
                          if (value == 'list' || value == 'grid') {
                            _gridView = value == 'grid';
                            _browseOffset = 0;
                            if (_libraryScroll.hasClients)
                              _libraryScroll.jumpTo(0);
                          } else {
                            _browseBy = value;
                          }
                        }),
                        itemBuilder: (_) => [
                          for (final option in _sortLabels.entries)
                            PopupMenuItem(
                              value: option.key,
                              child: Text(option.value),
                            ),
                          if (!widget.focusSearch) ...[
                            const PopupMenuDivider(),
                            CheckedPopupMenuItem(
                              value: 'list',
                              checked: !_gridView,
                              child: const Text('List view'),
                            ),
                            CheckedPopupMenuItem(
                              value: 'grid',
                              checked: _gridView,
                              child: const Text('Grid view'),
                            ),
                          ],
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Sort by ${_browseBy.toLowerCase()}'),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                      if (!widget.focusSearch)
                        PopupMenuButton<String>(
                          tooltip: 'Filter by metadata',
                          onSelected: (value) {
                            if (value == 'save') {
                              _saveFilterPreset();
                            } else if (value == 'saved') {
                              _chooseFilterPreset();
                            } else {
                              setState(() {
                                _filterField = value.isEmpty ? null : value;
                                if (value.isEmpty) _filters.clear();
                              });
                            }
                          },
                          itemBuilder: (_) => [
                            for (final field in _fields.keys)
                              PopupMenuItem(value: field, child: Text(field)),
                            if (_filters.isNotEmpty) ...[
                              const PopupMenuItem(
                                value: 'save',
                                child: Text('Save metadata filter…'),
                              ),
                              const PopupMenuItem(
                                value: '',
                                child: Text('Clear metadata filters'),
                              ),
                            ],
                            if (_filterPresets.isNotEmpty)
                              const PopupMenuItem(
                                value: 'saved',
                                child: Text('Saved metadata filters…'),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _filters.isEmpty
                                      ? 'Filter'
                                      : 'Filter (${_filters.length})',
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (categories.isNotEmpty)
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedCategory,
                      hint: Text('Choose a ${_filterField!.toLowerCase()}'),
                      items: [
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              category,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        final field = _filterField;
                        if (field == null || value == null) return;
                        setState(() {
                          _filters[field] = value;
                          _filterField = null;
                        });
                      },
                    ),
                  if (_filterField != null && categories.isEmpty)
                    const Text(
                      'No values for this filter in the current library.',
                    ),
                  if (_filters.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final filter in _filters.entries)
                          InputChip(
                            avatar: switch (metadataSymbols[widget
                                .metadataIconKeys[_fields[filter.key]]]) {
                              final IconData icon => Icon(icon, size: 16),
                              null => null,
                            },
                            label: Text(
                              '${filter.key}: ${filter.value}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: () =>
                                setState(() => _filters.remove(filter.key)),
                          ),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!widget.transferRestricted)
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context, 'import'),
                          icon: const Icon(Icons.add),
                          label: Text(ReaderText.importPdf.of(context)),
                        ),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, 'setlists'),
                        icon: const Icon(Icons.queue_music),
                        label: Text(ReaderText.setlists.of(context)),
                      ),
                      PopupMenuButton<String>(
                        tooltip: ReaderText.tools.of(context),
                        onSelected: (value) {
                          if (value == 'search-options') {
                            _configureSearchOptions();
                          } else {
                            Navigator.pop(context, value);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'search-options',
                            child: Text('Search and sorting'),
                          ),
                          if (!widget.transferRestricted) ...[
                            const PopupMenuItem(
                              value: 'create-template',
                              child: Text('Create from template'),
                            ),
                            const PopupMenuItem(
                              value: 'import-text',
                              child: Text('Import text or Word'),
                            ),
                            const PopupMenuItem(
                              value: 'import-images',
                              child: Text('Import images'),
                            ),
                            if (widget.canScan)
                              const PopupMenuItem(
                                value: 'scan',
                                child: Text('Scan sheet music'),
                              ),
                            const PopupMenuItem(
                              value: 'metadata-csv',
                              child: Text('CSV metadata'),
                            ),
                            if (!widget.connectionsRestricted)
                              const PopupMenuItem(
                                value: 'cloud-files',
                                child: Text('Cloud files'),
                              ),
                            if (widget.scores.length > 1)
                              const PopupMenuItem(
                                value: 'combine',
                                child: Text('Combine PDFs'),
                              ),
                            if (widget.persistent ||
                                widget.library.recentlyDeleted.isNotEmpty)
                              const PopupMenuItem(
                                value: 'backup',
                                child: Text('Backup & restore'),
                              ),
                            if (widget.persistent)
                              const PopupMenuItem(
                                value: 'import-package',
                                child: Text('Import score package'),
                              ),
                          ],
                          if (widget.canSync && !widget.connectionsRestricted)
                            const PopupMenuItem(
                              value: 'sync',
                              child: Text('Device sync'),
                            ),
                          if (widget.persistent &&
                              !widget.connectionsRestricted)
                            const PopupMenuItem(
                              value: 'ai-connections',
                              child: Text('AI Connections'),
                            ),
                          PopupMenuItem(
                            value: 'support',
                            child: Text(ReaderText.help.of(context)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (letters.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final letter in <String?>[null, ...letters])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ChoiceChip(
                                label: Text(letter ?? 'All'),
                                selected: letter == null
                                    ? !letters.contains(_browseLetter)
                                    : _browseLetter == letter,
                                onSelected: (_) {
                                  setState(() => _browseLetter = letter);
                                  if (_libraryScroll.hasClients)
                                    _libraryScroll.jumpTo(0);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (!widget.persistent)
                    const Text(
                      'Browser preview keeps scores for this session.',
                    ),
                  Expanded(
                    child: indices.isEmpty && !browsingCategories
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'No imported scores yet.'
                                  : 'No matching scores.',
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              if (_query.isEmpty && _libraryScroll.hasClients) {
                                _browseOffset = _libraryScroll.offset;
                              }
                              return false;
                            },
                            child:
                                categoryList ??
                                grid ??
                                ListView.builder(
                                  controller: _libraryScroll,
                                  itemCount: indices.length,
                                  itemBuilder: (context, selectionIndex) {
                                    var index = indices[selectionIndex];
                                    if (index >= visible.length &&
                                        index <
                                            visible.length +
                                                matchingBookmarks.length) {
                                      final (score, bookmark) =
                                          matchingBookmarks[index -
                                              visible.length];
                                      return ListTile(
                                        leading: const Icon(
                                          Icons.bookmark_outline,
                                        ),
                                        title: Text(bookmark.title),
                                        subtitle: Text(
                                          '${score.title} · Page ${bookmark.page}',
                                        ),
                                        onTap: () {
                                          widget.onScoreQueue([
                                            for (final (parent, item)
                                                in matchingBookmarks)
                                              if (item.isItem)
                                                item.selectionId(parent.id),
                                          ]);
                                          Navigator.pop(
                                            context,
                                            'bookmark:${score.id}:${bookmark.id}',
                                          );
                                        },
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
                                        leading: const Icon(
                                          Icons.arrow_outward,
                                        ),
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
                                      selected:
                                          score.id == widget.revealScoreId,
                                      leading: LongPressDraggable<String>(
                                        data: score.id,
                                        onDragStarted: () =>
                                            _showDragTargets(true),
                                        onDragEnd: (_) =>
                                            _showDragTargets(false),
                                        feedback: Material(
                                          elevation: 5,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 220,
                                              ),
                                              child: Text(
                                                score.title,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: IconButton(
                                          tooltip: 'Add to setlist',
                                          onPressed: () =>
                                              _dropIntoSetlist(score.id),
                                          icon: const Icon(Icons.playlist_add),
                                        ),
                                      ),
                                      title: Text(score.title),
                                      dense: widget.compact,
                                      subtitle: widget.compact
                                          ? (score.isSample
                                                ? const Text('Sample score')
                                                : null)
                                          : Text(
                                              [
                                                if (score.isSample)
                                                  'Sample score',
                                                if (score.metadata['composer']
                                                    case final composer?)
                                                  composer,
                                                if (score.metadata['tempo']
                                                    case final tempo?
                                                    when tempo.isNotEmpty)
                                                  '$tempo BPM',
                                                'Resume at page ${score.page}',
                                              ].join(' · '),
                                            ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip:
                                                'Properties for ${score.title}',
                                            onPressed: () => Navigator.pop(
                                              context,
                                              'edit:${score.id}',
                                            ),
                                            icon: const Icon(
                                              Icons.info_outline,
                                            ),
                                          ),
                                          _scoreOptions(score),
                                        ],
                                      ),
                                      onTap: () =>
                                          _openListedScore(score, visible),
                                    );
                                  },
                                ),
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
