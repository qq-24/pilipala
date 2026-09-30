import 'dart:convert';
import 'dart:typed_data';

// InfocProto field numbers and RDIO framing verified against Android 9.13.0.
class _Proto {
  final bytes = BytesBuilder(copy: false);
  void integer(int field, int value) {
    if (value == 0) return;
    bytes.add(_varint(field << 3));
    bytes.add(_varint(value));
  }

  void text(int field, String value) {
    if (value.isNotEmpty) message(field, utf8.encode(value));
  }

  void message(int field, List<int> value) {
    bytes.add(_varint((field << 3) | 2));
    bytes.add(_varint(value.length));
    bytes.add(value);
  }

  void map(int field, Map<String, String> values) {
    for (final entry in values.entries) {
      final item = _Proto()
        ..text(1, entry.key)
        ..text(2, entry.value);
      message(field, item.bytes.takeBytes());
    }
  }

  static List<int> _varint(int value) {
    final out = <int>[];
    while (value > 127) {
      out.add((value & 127) | 128);
      value >>= 7;
    }
    out.add(value);
    return out;
  }
}

class RecommendationCodec {
  static const crc = [
    234,
    212,
    150,
    168,
    18,
    44,
    110,
    80,
    127,
    65,
    3,
    61,
    135,
    185,
    251,
    197,
    165,
    155,
    217,
    231,
    93,
    99,
    33,
    31,
    48,
    14,
    76,
    114,
    200,
    246,
    180,
    138,
    116,
    74,
    8,
    54,
    140,
    178,
    240,
    206,
    225,
    223,
    157,
    163,
    25,
    39,
    101,
    91,
    59,
    5,
    71,
    121,
    195,
    253,
    191,
    129,
    174,
    144,
    210,
    236,
    86,
    104,
    42,
    20,
    179,
    141,
    207,
    241,
    75,
    117,
    55,
    9,
    38,
    24,
    90,
    100,
    222,
    224,
    162,
    156,
    252,
    194,
    128,
    190,
    4,
    58,
    120,
    70,
    105,
    87,
    21,
    43,
    145,
    175,
    237,
    211,
    45,
    19,
    81,
    111,
    213,
    235,
    169,
    151,
    184,
    134,
    196,
    250,
    64,
    126,
    60,
    2,
    98,
    92,
    30,
    32,
    154,
    164,
    230,
    216,
    247,
    201,
    139,
    181,
    15,
    49,
    115,
    77,
    88,
    102,
    36,
    26,
    160,
    158,
    220,
    226,
    205,
    243,
    177,
    143,
    53,
    11,
    73,
    119,
    23,
    41,
    107,
    85,
    239,
    209,
    147,
    173,
    130,
    188,
    254,
    192,
    122,
    68,
    6,
    56,
    198,
    248,
    186,
    132,
    62,
    0,
    66,
    124,
    83,
    109,
    47,
    17,
    171,
    149,
    215,
    233,
    137,
    183,
    245,
    203,
    113,
    79,
    13,
    51,
    28,
    34,
    96,
    94,
    228,
    218,
    152,
    166,
    1,
    63,
    125,
    67,
    249,
    199,
    133,
    187,
    148,
    170,
    232,
    214,
    108,
    82,
    16,
    46,
    78,
    112,
    50,
    12,
    182,
    136,
    202,
    244,
    219,
    229,
    167,
    153,
    35,
    29,
    95,
    97,
    159,
    161,
    227,
    221,
    103,
    89,
    27,
    37,
    10,
    52,
    118,
    72,
    242,
    204,
    142,
    176,
    208,
    238,
    172,
    146,
    40,
    22,
    84,
    106,
    69,
    123,
    57,
    7,
    189,
    131,
    193,
    255
  ];
  static Uint8List frame(List<int> protobuf, Map<String, String> headers) {
    final payload = BytesBuilder(copy: false);
    final entries = headers.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final key = utf8.encode(entries[i].key),
          value = utf8.encode(entries[i].value);
      if (key.length > 255) throw ArgumentError('Frame header too long');
      payload.add([key.length]);
      payload.add(key);
      final length = ByteData(4)
        ..setUint32(
            0, value.length | (i < entries.length - 1 ? 0x80000000 : 0));
      payload.add(length.buffer.asUint8List());
      payload.add(value);
    }
    payload.add(protobuf);
    final data = payload.takeBytes();
    final length = data.length | (headers.isNotEmpty ? 0x80000000 : 0);
    var checksum = crc[length & 255];
    checksum = crc[checksum ^ ((length >> 8) & 255)];
    checksum = crc[checksum ^ ((length >> 16) & 255)];
    checksum = crc[checksum ^ ((length >> 24) & 255)];
    final header = ByteData(4)..setUint32(0, length);
    return Uint8List.fromList([
      ...ascii.encode('RDIO'),
      ...header.buffer.asUint8List(),
      checksum,
      ...data
    ]);
  }

  static Uint8List event(
      {required String name,
      required Map<String, String> fields,
      required String mid,
      required String buvid,
      required int time,
      required int sequence,
      required String session,
      bool click = false,
      String model = 'android',
      String brand = '',
      String os = '',
      int api = 0,
      String abi = '',
      int network = 0}) {
    final logId = click ? '002312' : '001538';
    final info = _Proto()
      ..integer(1, 1)
      ..integer(2, 3)
      ..text(3, buvid)
      ..text(4, 'master')
      ..text(5, brand)
      ..text(7, model)
      ..text(8, os)
      ..integer(12, api)
      ..text(13, abi)
      ..text(15, session);
    // Report this client's actual version, not a fabricated official installation.
    final runtime = _Proto()
      ..integer(1, network)
      ..text(5, '1.0.29')
      ..text(6, '10282')
      ..text(7, '1.0.0');
    final event = _Proto()
      ..text(1, name)
      ..message(2, info.bytes.takeBytes())
      ..message(3, runtime.bytes.takeBytes())
      ..text(4, mid)
      ..integer(5, time)
      ..text(6, logId)
      ..integer(8, sequence)
      ..integer(9, click ? 2 : 3);
    event.message(click ? 11 : 12, const []);
    event.map(13, fields);
    event.integer(15, time);
    event.integer(16, time);
    return frame(event.bytes.takeBytes(), {
      'logId': logId,
      'eventId': name,
      'appId': '1',
      'appVersionCode': '10282',
      'platform': '3'
    });
  }
}
