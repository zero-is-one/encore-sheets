import 'dart:typed_data';

int _u16(ByteData bytes, int offset) => bytes.getUint16(offset, Endian.little);
int _u32(ByteData bytes, int offset) => bytes.getUint32(offset, Endian.little);
const _endOfChain = 0xfffffffe;

typedef _CompoundEntry = ({int firstSector, int length});

class _CompoundDocument {
  _CompoundDocument(this.data) : header = ByteData.sublistView(data) {
    if (data.length < 512 ||
        _u32(header, 0) != 0xe011cfd0 ||
        _u32(header, 4) != 0xe11ab1a1) {
      throw const FormatException('This file is not a Word binary document.');
    }
    final shift = _u16(header, 30);
    if ((shift != 9 && shift != 12) || _u16(header, 32) != 6) {
      throw const FormatException('Unsupported Word file storage format.');
    }
    sectorSize = 1 << shift;
    final fatCount = _u32(header, 44);
    if (fatCount > data.length ~/ sectorSize) {
      throw const FormatException('Invalid Word file allocation table.');
    }
    final fatSectors = <int>[
      for (var i = 0; i < 109 && i < fatCount; i++) _u32(header, 76 + i * 4),
    ];
    var extension = _u32(header, 68);
    final difatCount = _u32(header, 72);
    for (var i = 0; i < difatCount && fatSectors.length < fatCount; i++) {
      final sector = ByteData.sublistView(_sector(extension));
      for (
        var j = 0;
        j < sectorSize - 4 && fatSectors.length < fatCount;
        j += 4
      ) {
        fatSectors.add(_u32(sector, j));
      }
      extension = _u32(sector, sectorSize - 4);
    }
    for (final sector in fatSectors) {
      final entries = ByteData.sublistView(_sector(sector));
      for (var i = 0; i < sectorSize; i += 4) {
        fat.add(_u32(entries, i));
      }
    }
    final directory = _chain(_u32(header, 48), fat, _sector, data.length);
    final entries = ByteData.sublistView(directory);
    for (var i = 0; i + 128 <= directory.length; i += 128) {
      final length = _u16(entries, i + 64);
      final type = entries.getUint8(i + 66);
      if (length < 2 || length > 64 || length.isOdd || (type != 2 && type != 5))
        continue;
      final name = String.fromCharCodes([
        for (var j = 0; j < length - 2; j += 2) _u16(entries, i + j),
      ]);
      final entry = (
        firstSector: _u32(entries, i + 116),
        length: _u32(entries, i + 120),
      );
      if (type == 5) {
        root = entry;
      } else {
        streams[name] = entry;
      }
    }
  }

  final Uint8List data;
  final ByteData header;
  late final int sectorSize;
  final fat = <int>[];
  final streams = <String, _CompoundEntry>{};
  _CompoundEntry? root;

  Uint8List _sector(int index) {
    final start = (index + 1) * sectorSize;
    if (index < 0 || start + sectorSize > data.length) {
      throw const FormatException('Invalid Word file sector.');
    }
    return Uint8List.sublistView(data, start, start + sectorSize);
  }

  Uint8List _chain(
    int first,
    List<int> table,
    Uint8List Function(int) sector,
    int limit,
  ) {
    final output = BytesBuilder(copy: false);
    final visited = <int>{};
    var index = first;
    while (index != _endOfChain && output.length < limit) {
      if (index < 0 || index >= table.length || !visited.add(index)) {
        throw const FormatException('Invalid Word file stream.');
      }
      final bytes = sector(index);
      output.add(
        bytes.length <= limit - output.length
            ? bytes
            : Uint8List.sublistView(bytes, 0, limit - output.length),
      );
      index = table[index];
    }
    return output.takeBytes();
  }

  Uint8List stream(String name) {
    final entry = streams[name];
    if (entry == null || entry.length > data.length) {
      throw const FormatException('A required Word file stream is missing.');
    }
    if (entry.length >= _u32(header, 56)) {
      return _chain(entry.firstSector, fat, _sector, entry.length);
    }
    final storage = root;
    if (storage == null || storage.length > data.length) {
      throw const FormatException('Invalid Word file directory.');
    }
    final miniBytes = _chain(_u32(header, 60), fat, _sector, data.length);
    final mini = ByteData.sublistView(miniBytes);
    final allocation = [
      for (var i = 0; i + 4 <= mini.lengthInBytes; i += 4) _u32(mini, i),
    ];
    final shared = _chain(storage.firstSector, fat, _sector, storage.length);
    return _chain(entry.firstSector, allocation, (sector) {
      final start = sector * 64;
      if (start + 64 > shared.length) {
        throw const FormatException('Invalid Word file mini-sector.');
      }
      return Uint8List.sublistView(shared, start, start + 64);
    }, entry.length);
  }
}

String extractWordBinaryText(Uint8List bytes) {
  try {
    final compound = _CompoundDocument(bytes);
    final word = ByteData.sublistView(compound.stream('WordDocument'));
    if (_u16(word, 0) != 0xa5ec || _u16(word, 2) < 0x00c1) {
      throw const FormatException('This Word version is unsupported.');
    }
    final flags = _u16(word, 10);
    if (flags & 0x8100 != 0) {
      throw const FormatException('Unlock the Word document before importing.');
    }
    final table = ByteData.sublistView(
      compound.stream(flags & 0x0200 == 0 ? '0Table' : '1Table'),
    );
    final longs = 32 + 2 + _u16(word, 32) * 2;
    final pairs = longs + 2 + _u16(word, longs) * 4;
    if (_u16(word, pairs) <= 33) {
      throw const FormatException('The Word document has no text index.');
    }
    final characters = _u32(word, longs + 2 + 3 * 4);
    final entry = pairs + 2 + 33 * 8;
    var cursor = _u32(word, entry);
    final end = cursor + _u32(word, entry + 4);
    if (end > table.lengthInBytes) {
      throw const FormatException('Invalid Word text index.');
    }
    while (cursor < end && table.getUint8(cursor) == 1) {
      cursor += 3 + _u16(table, cursor + 1);
    }
    if (cursor + 5 > end || table.getUint8(cursor) != 2) {
      throw const FormatException('The Word text index is missing.');
    }
    final length = _u32(table, cursor + 1);
    if (length < 4 || (length - 4) % 12 != 0 || cursor + 5 + length > end) {
      throw const FormatException('Invalid Word text index.');
    }
    final pieces = (length - 4) ~/ 12;
    final base = cursor + 5;
    final descriptors = base + 4 * (pieces + 1);
    final text = StringBuffer();
    for (var i = 0; i < pieces; i++) {
      final start = _u32(table, base + 4 * i);
      if (start >= characters) break;
      final stop = _u32(table, base + 4 * (i + 1)).clamp(start, characters);
      final field = _u32(table, descriptors + i * 8 + 2);
      final compressed = field & 0x40000000 != 0;
      final offset = field & 0x3fffffff;
      final first = compressed ? offset ~/ 2 : offset;
      for (var j = 0; j < stop - start; j++) {
        final code = compressed
            ? word.getUint8(first + j)
            : _u16(word, first + 2 * j);
        text.writeCharCode(compressed ? windowsTextCode(code) : code);
      }
    }
    return text.toString().replaceAll('\u0007', '\t').replaceAll('\r', '\n');
  } on RangeError {
    throw const FormatException('The Word document is truncated.');
  }
}

int windowsTextCode(int code) {
  const map = {
    0x80: 0x20ac,
    0x82: 0x201a,
    0x83: 0x0192,
    0x84: 0x201e,
    0x85: 0x2026,
    0x86: 0x2020,
    0x87: 0x2021,
    0x88: 0x02c6,
    0x89: 0x2030,
    0x8a: 0x0160,
    0x8b: 0x2039,
    0x8c: 0x0152,
    0x8e: 0x017d,
    0x91: 0x2018,
    0x92: 0x2019,
    0x93: 0x201c,
    0x94: 0x201d,
    0x95: 0x2022,
    0x96: 0x2013,
    0x97: 0x2014,
    0x98: 0x02dc,
    0x99: 0x2122,
    0x9a: 0x0161,
    0x9b: 0x203a,
    0x9c: 0x0153,
    0x9e: 0x017e,
    0x9f: 0x0178,
  };
  return map[code] ?? code;
}
