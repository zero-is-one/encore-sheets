typedef AudioPageCue = ({int milliseconds, int page});

enum AudioPageCueMode { record, replay, off }

List<AudioPageCue> readAudioPageCues(Object? data) {
  if (data is! List) return [];
  return [
    for (final cue in data)
      if (cue case {'ms': final int ms, 'page': final int page}
          when ms >= 0 && page > 0)
        (milliseconds: ms, page: page),
  ]..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
}

AudioPageCue? audioCueAt(List<AudioPageCue> cues, Duration position) {
  var low = 0;
  var high = cues.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (cues[middle].milliseconds <= position.inMilliseconds) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low == 0 ? null : cues[low - 1];
}
