import 'dart:js_interop';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

const _key = 'encoresheets.firstLight.dismissed';

bool sampleDismissed() {
  try {
    return _storage.getItem(_key.toJS)?.toDart == 'true';
  } catch (_) {
    return false;
  }
}

void setSampleDismissed(bool dismissed) {
  try {
    _storage.setItem(_key.toJS, dismissed.toString().toJS);
  } catch (_) {
    // Browsers can deny storage access. The current session still remembers.
  }
}
