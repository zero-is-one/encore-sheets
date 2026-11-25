enum ReaderTapAction {
  previous('Previous page'),
  next('Next page'),
  controls('Show or hide controls'),
  markup('Mark up score'),
  none('No action');

  const ReaderTapAction(this.label);
  final String label;
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
    );
  }

  final ReaderTapAction left;
  final ReaderTapAction center;
  final ReaderTapAction right;
  final bool keepAwake;
  final bool showNextTitle;
  final bool halfPageTurns;
  final bool halfPageIndicator;

  ReaderPreferences copyWith({
    ReaderTapAction? left,
    ReaderTapAction? center,
    ReaderTapAction? right,
    bool? keepAwake,
    bool? showNextTitle,
    bool? halfPageTurns,
    bool? halfPageIndicator,
  }) => ReaderPreferences(
    left: left ?? this.left,
    center: center ?? this.center,
    right: right ?? this.right,
    keepAwake: keepAwake ?? this.keepAwake,
    showNextTitle: showNextTitle ?? this.showNextTitle,
    halfPageTurns: halfPageTurns ?? this.halfPageTurns,
    halfPageIndicator: halfPageIndicator ?? this.halfPageIndicator,
  );

  Map<String, dynamic> toJson() => {
    'left': left.name,
    'center': center.name,
    'right': right.name,
    'keepAwake': keepAwake,
    'showNextTitle': showNextTitle,
    'halfPageTurns': halfPageTurns,
    'halfPageIndicator': halfPageIndicator,
  };
}
