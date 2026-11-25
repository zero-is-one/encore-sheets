enum ReaderLinkTarget { score, bookmark, setlist, library, cloud }

typedef ReaderDeepLink = ({
  ReaderLinkTarget target,
  String? id,
  String? name,
  int? page,
});

ReaderDeepLink? parseReaderLink(String value) {
  if (value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'encoresheets' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment)
    return null;
  final target = ReaderLinkTarget.values
      .where((item) => item.name == uri.host)
      .firstOrNull;
  if (target == null) return null;
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final name = uri.queryParameters['name']?.trim();
  final page = int.tryParse(uri.queryParameters['page'] ?? '');
  if (page != null && page < 1) return null;
  if (target == ReaderLinkTarget.library || target == ReaderLinkTarget.cloud) {
    return parts.isEmpty
        ? (target: target, id: null, name: null, page: null)
        : null;
  }
  if (name != null && name.isNotEmpty && parts.isEmpty) {
    return (target: target, id: null, name: name, page: page);
  }
  if (parts.length != 1 ||
      parts.single.length > 160 ||
      parts.single.contains('/') ||
      name != null)
    return null;
  return (target: target, id: parts.single, name: null, page: page);
}
