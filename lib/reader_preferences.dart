enum ReaderTapAction {
  previous('Previous page'),
  next('Next page'),
  controls('Show or hide controls'),
  markup('Mark up score'),
  none('No action');

  const ReaderTapAction(this.label);
  final String label;
}

enum EmbeddedPdfContent {
  all('Annotations and form fields'),
  annotations('Annotations'),
  hidden('Hide annotations and form fields');

  const EmbeddedPdfContent(this.label);
  final String label;
}

enum ReaderPageFit {
  standard('Standard', 'Use the current orientation and layout settings.'),
  bestFit('Best Fit', 'Show the entire page with a narrow margin.'),
  zoomed('Zoomed', 'Fill the width and turn through tall pages in sections.');

  const ReaderPageFit(this.label, this.explanation);
  final String label;
  final String explanation;
}

class ReaderPreferences {
  const ReaderPreferences({
    this.left = ReaderTapAction.previous,
    this.center = ReaderTapAction.controls,
    this.right = ReaderTapAction.next,
    this.keepAwake = false,
    this.showNextTitle = true,
    this.halfPageTurns = false,
    this.halfPageIndicator = true,
    this.landscapeWidth = false,
    this.spreadStep = 0,
    this.sepia = false,
    this.pageDimming = 0,
    this.fullScreenPanels = false,
    this.largePageButtons = false,
    this.complexGestures = true,
    this.softMetronome = false,
    this.dockPanels = false,
    this.compactLibrary = false,
    this.embeddedPdfContent = EmbeddedPdfContent.all,
    this.embeddedPdfLinks = true,
    this.pageFit = ReaderPageFit.standard,
  });

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    ReaderTapAction read(String key, ReaderTapAction fallback) =>
        ReaderTapAction.values
            .where((action) => action.name == json[key])
            .firstOrNull ??
        fallback;
    return ReaderPreferences(
      left: read('left', ReaderTapAction.previous),
      center: read('center', ReaderTapAction.controls),
      right: read('right', ReaderTapAction.next),
      keepAwake: json['keepAwake'] == true,
      showNextTitle: json['showNextTitle'] != false,
      halfPageTurns: json['halfPageTurns'] == true,
      halfPageIndicator: json['halfPageIndicator'] != false,
      landscapeWidth: json['landscapeWidth'] == true,
      spreadStep: switch (json['spreadStep']) {
        1 => 1,
        2 => 2,
        _ => 0,
      },
      sepia: json['sepia'] == true,
      fullScreenPanels: json['fullScreenPanels'] == true,
      largePageButtons: json['largePageButtons'] == true,
      complexGestures: json['complexGestures'] != false,
      softMetronome: json['softMetronome'] == true,
      dockPanels: json['dockPanels'] == true,
      compactLibrary: json['compactLibrary'] == true,
      embeddedPdfContent:
          EmbeddedPdfContent.values
              .where((mode) => mode.name == json['embeddedPdfContent'])
              .firstOrNull ??
          EmbeddedPdfContent.all,
      embeddedPdfLinks: json['embeddedPdfLinks'] != false,
      pageFit:
          ReaderPageFit.values
              .where((mode) => mode.name == json['pageFit'])
              .firstOrNull ??
          ReaderPageFit.standard,
      pageDimming: switch (json['pageDimming']) {
        final num value when value.isFinite => value.toDouble().clamp(0.0, .75),
        _ => 0,
      },
    );
  }

  final ReaderTapAction left;
  final ReaderTapAction center;
  final ReaderTapAction right;
  final bool keepAwake;
  final bool showNextTitle;
  final bool halfPageTurns;
  final bool halfPageIndicator;
  final bool landscapeWidth;
  final int spreadStep;
  final bool sepia;
  final double pageDimming;
  final bool fullScreenPanels, largePageButtons, complexGestures, softMetronome;
  final bool dockPanels, compactLibrary;
  final EmbeddedPdfContent embeddedPdfContent;
  final bool embeddedPdfLinks;
  final ReaderPageFit pageFit;

  ReaderPreferences copyWith({
    ReaderTapAction? left,
    ReaderTapAction? center,
    ReaderTapAction? right,
    bool? keepAwake,
    bool? showNextTitle,
    bool? halfPageTurns,
    bool? halfPageIndicator,
    bool? landscapeWidth,
    int? spreadStep,
    bool? sepia,
    double? pageDimming,
    bool? fullScreenPanels,
    bool? largePageButtons,
    bool? complexGestures,
    bool? softMetronome,
    bool? dockPanels,
    bool? compactLibrary,
    EmbeddedPdfContent? embeddedPdfContent,
    bool? embeddedPdfLinks,
    ReaderPageFit? pageFit,
  }) => ReaderPreferences(
    left: left ?? this.left,
    center: center ?? this.center,
    right: right ?? this.right,
    keepAwake: keepAwake ?? this.keepAwake,
    showNextTitle: showNextTitle ?? this.showNextTitle,
    halfPageTurns: halfPageTurns ?? this.halfPageTurns,
    halfPageIndicator: halfPageIndicator ?? this.halfPageIndicator,
    landscapeWidth: landscapeWidth ?? this.landscapeWidth,
    spreadStep: spreadStep ?? this.spreadStep,
    sepia: sepia ?? this.sepia,
    pageDimming: pageDimming ?? this.pageDimming,
    fullScreenPanels: fullScreenPanels ?? this.fullScreenPanels,
    largePageButtons: largePageButtons ?? this.largePageButtons,
    complexGestures: complexGestures ?? this.complexGestures,
    softMetronome: softMetronome ?? this.softMetronome,
    dockPanels: dockPanels ?? this.dockPanels,
    compactLibrary: compactLibrary ?? this.compactLibrary,
    embeddedPdfContent: embeddedPdfContent ?? this.embeddedPdfContent,
    embeddedPdfLinks: embeddedPdfLinks ?? this.embeddedPdfLinks,
    pageFit: pageFit ?? this.pageFit,
  );

  Map<String, dynamic> toJson() => {
    'left': left.name,
    'center': center.name,
    'right': right.name,
    'keepAwake': keepAwake,
    'showNextTitle': showNextTitle,
    'halfPageTurns': halfPageTurns,
    'halfPageIndicator': halfPageIndicator,
    'landscapeWidth': landscapeWidth,
    'spreadStep': spreadStep,
    'sepia': sepia,
    'pageDimming': pageDimming,
    'fullScreenPanels': fullScreenPanels,
    'largePageButtons': largePageButtons,
    'complexGestures': complexGestures,
    'softMetronome': softMetronome,
    'dockPanels': dockPanels,
    'compactLibrary': compactLibrary,
    'embeddedPdfContent': embeddedPdfContent.name,
    'embeddedPdfLinks': embeddedPdfLinks,
    'pageFit': pageFit.name,
  };
}
