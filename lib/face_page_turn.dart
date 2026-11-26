/// Converts a centered head position and a deliberate turn into one page turn.
/// Missing detections clear pending gestures and require a return to center.
class FacePageTurn {
  FacePageTurn({this.threshold = 23});

  final double threshold;
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

  int update(double? yaw) {
    if (yaw == null || !yaw.isFinite) {
      _candidate = _frames = 0;
      _armed = false;
      if (!calibrated) reset();
      return 0;
    }
    if (!calibrated) {
      if (yaw.abs() > 15) {
        reset();
      } else {
        _baseline += (yaw - _baseline) / ++_calibrationFrames;
        _armed = calibrated;
      }
      return 0;
    }
    final offset = yaw - _baseline;
    if (offset.abs() <= threshold * .4) _armed = true;
    if (!_armed || offset.abs() < threshold) {
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
