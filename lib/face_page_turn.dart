enum FaceGestureMode {
  headTurn('Head turn', 'Face the camera, then turn your head left or right.'),
  wink(
    'Wink',
    'Face the camera with both eyes open, then wink. Each eye turns in a different direction.',
  ),
  mouth(
    'Mouth opening',
    'Calibrate with a relaxed, closed mouth, then open it to turn a page.',
  );

  const FaceGestureMode(this.label, this.instructions);
  final String label;
  final String instructions;

  double? readSample(Object? sample) {
    if (sample is! Map) return null;
    final yaw = sample['yaw'];
    if (yaw is! num || !yaw.isFinite) return null;
    if (this == headTurn) return yaw.toDouble();
    if (yaw.abs() > 18) return null;
    final value = sample[name];
    return value is num ? value.toDouble() : null;
  }
}

/// Converts a calibrated facial motion into one page turn.
/// Missing detections clear pending gestures and require a return to center.
class FacePageTurn {
  FacePageTurn({this.threshold = 23, this.mode = FaceGestureMode.headTurn});

  final double threshold;
  final FaceGestureMode mode;
  double _baseline = 0;
  int _calibrationFrames = 0;
  int _candidate = 0;
  int _frames = 0;
  bool _armed = false;

  bool get calibrated => _calibrationFrames == 8;

  void reset() {
    _baseline = 0;
    _calibrationFrames = 0;
    _candidate = _frames = 0;
    _armed = false;
  }

  int update(double? sample) {
    if (sample == null || !sample.isFinite) {
      _candidate = _frames = 0;
      _armed = false;
      if (!calibrated) reset();
      return 0;
    }
    if (!calibrated) {
      final neutralLimit = switch (mode) {
        FaceGestureMode.headTurn => 15.0,
        FaceGestureMode.wink => .22,
        FaceGestureMode.mouth => .35,
      };
      if (sample.abs() > neutralLimit) {
        reset();
      } else {
        _baseline += (sample - _baseline) / ++_calibrationFrames;
        _armed = calibrated;
      }
      return 0;
    }
    final offset = sample - _baseline;
    if (offset.abs() <= threshold * .4) _armed = true;
    if (!_armed ||
        offset.abs() < threshold ||
        (mode == FaceGestureMode.mouth && offset < 0)) {
      _candidate = _frames = 0;
      return 0;
    }
    final direction = offset > 0 ? 1 : -1;
    if (_candidate != direction) {
      _candidate = direction;
      _frames = 0;
    }
    if (++_frames < 3) return 0;
    _armed = false;
    _candidate = _frames = 0;
    return direction;
  }
}
