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
    );
  }

  final ReaderTapAction left;
  final ReaderTapAction center;
  final ReaderTapAction right;

  Map<String, dynamic> toJson() => {
    'left': left.name,
    'center': center.name,
    'right': right.name,
  };
}
