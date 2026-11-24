import 'dart:convert';
import 'dart:typed_data';

/// Supported symmetric block-cipher algorithms for [JsCryptoHelpers].
enum SymmetricAlgorithm { aes, des }

/// Supported symmetric block-cipher chaining modes.
enum SymmetricMode { ecb, cbc }

/// Supported block-cipher padding schemes.
enum SymmetricPadding { pkcs5, pkcs7, zero, none }

/// Parsed symmetric cipher transformation (`ALGORITHM/MODE/PADDING`).
class SymmetricTransformation {
  final SymmetricAlgorithm algorithm;
  final SymmetricMode mode;
  final SymmetricPadding padding;

  const SymmetricTransformation({
    required this.algorithm,
    required this.mode,
    required this.padding,
  });

  int get blockSize => algorithm == SymmetricAlgorithm.aes ? 16 : 8;

  /// Canonical transformation string (`"AES/CBC/PKCS5Padding"`).
  String get canonical {
    final algo = algorithm == SymmetricAlgorithm.aes ? 'AES' : 'DES';
    final modeName = mode == SymmetricMode.cbc ? 'CBC' : 'ECB';
    final padName = switch (padding) {
      SymmetricPadding.pkcs5 => 'PKCS5Padding',
      SymmetricPadding.pkcs7 => 'PKCS7Padding',
      SymmetricPadding.zero => 'ZeroPadding',
      SymmetricPadding.none => 'NoPadding',
    };
    return '$algo/$modeName/$padName';
  }

  /// Parses transformations such as `"AES/CBC/PKCS5Padding"`, `"AES"`, or
  /// `"DES/ECB/ZeroPadding"` with explicit [ArgumentError] on unsupported
  /// values.
  factory SymmetricTransformation.parse(
    String? transformation, {
    SymmetricAlgorithm defaultAlgorithm = SymmetricAlgorithm.aes,
    bool hasNonEmptyIv = false,
  }) {
    final raw = (transformation ?? '').trim();
    if (raw.isEmpty) {
      return SymmetricTransformation(
        algorithm: defaultAlgorithm,
        mode: hasNonEmptyIv ? SymmetricMode.cbc : SymmetricMode.ecb,
        padding: SymmetricPadding.pkcs5,
      );
    }

    final parts = raw.split('/').map((p) => p.trim()).toList(growable: false);
    if (parts.length > 3 || parts.any((p) => p.isEmpty)) {
      throw ArgumentError.value(
        transformation,
        'transformation',
        'Expected ALGORITHM or ALGORITHM/MODE/PADDING (e.g. AES/CBC/PKCS5Padding).',
      );
    }

    final algoToken = parts[0].toUpperCase();
    final SymmetricAlgorithm algorithm;
    switch (algoToken) {
      case 'AES':
        algorithm = SymmetricAlgorithm.aes;
      case 'DES':
        algorithm = SymmetricAlgorithm.des;
      default:
        throw ArgumentError.value(
          transformation,
          'transformation',
          'Unsupported symmetric algorithm "${parts[0]}". Expected AES or DES.',
        );
    }

    final modeToken = parts.length >= 2 ? parts[1].toUpperCase() : '';
    final SymmetricMode mode;
    if (modeToken.isEmpty) {
      mode = hasNonEmptyIv ? SymmetricMode.cbc : SymmetricMode.ecb;
    } else {
      switch (modeToken) {
        case 'ECB':
          mode = SymmetricMode.ecb;
        case 'CBC':
          mode = SymmetricMode.cbc;
        default:
          throw ArgumentError.value(
            transformation,
            'transformation',
            'Unsupported block mode "${parts[1]}". Expected ECB or CBC.',
          );
      }
    }

    final padToken = parts.length == 3
        ? parts[2].toUpperCase()
        : 'PKCS5PADDING';
    final SymmetricPadding padding;
    switch (padToken) {
      case 'PKCS5':
      case 'PKCS5PADDING':
        padding = SymmetricPadding.pkcs5;
      case 'PKCS7':
      case 'PKCS7PADDING':
        padding = SymmetricPadding.pkcs7;
      case 'ZERO':
      case 'ZEROS':
      case 'ZEROPADDING':
      case 'ZEROSPADDING':
        padding = SymmetricPadding.zero;
      case 'NO':
      case 'NONE':
      case 'NOPADDING':
        padding = SymmetricPadding.none;
      default:
        throw ArgumentError.value(
          transformation,
          'transformation',
          'Unsupported padding "${parts[2]}". Expected PKCS5Padding, PKCS7Padding, ZeroPadding, or NoPadding.',
        );
    }

    return SymmetricTransformation(
      algorithm: algorithm,
      mode: mode,
      padding: padding,
    );
  }
}

/// Pure-Dart RFC 1321 MD5, Base64, Hex, FIPS-197 AES (128/192/256), and
/// FIPS-46 DES utilities for sandboxed JS runtimes and source parsing without
/// external crypto dependencies.
class JsCryptoHelpers {
  const JsCryptoHelpers._();

  static const List<int> _shifts = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  static const List<int> _aesSBox = <int>[
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _aesInvSBox = <int>[
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
  ];

  static const List<int> _aesRcon = <int>[
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  ];

  static const List<int> _desIp = <int>[
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
  ];

  static const List<int> _desFp = <int>[
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
  ];

  static const List<int> _desE = <int>[
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
  ];

  static const List<int> _desP = <int>[
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
  ];

  static const List<int> _desPc1 = <int>[
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
  ];

  static const List<int> _desPc2 = <int>[
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
  ];

  static const List<int> _desKeyShifts = <int>[
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
  ];

  static const List<List<int>> _desSBoxes = <List<int>>[
    <int>[
      14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
      0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
      4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
      15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13,
    ],
    <int>[
      15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
      3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
      0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
      13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9,
    ],
    <int>[
      10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
      13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
      13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
      1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12,
    ],
    <int>[
      7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
      13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
      10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
      3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14,
    ],
    <int>[
      2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
      14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
      4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
      11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3,
    ],
    <int>[
      12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
      10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
      9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
      4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13,
    ],
    <int>[
      4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
      13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
      1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
      6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12,
    ],
    <int>[
      13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
      1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
      7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
      2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11,
    ],
  ];

  /// Computes the 16-byte RFC 1321 MD5 digest of [bytes].
  static Uint8List md5Bytes(List<int> bytes) {
    final msgLen = bytes.length;
    final bitLen = msgLen * 8;
    final rem = (msgLen + 9) % 64;
    final padLen = rem == 0 ? 0 : 64 - rem;
    final totalLen = msgLen + 9 + padLen;

    final padded = Uint8List(totalLen);
    padded.setRange(0, msgLen, bytes);
    padded[msgLen] = 0x80;

    // Append 64-bit little-endian bit length.
    for (var i = 0; i < 8; i++) {
      padded[totalLen - 8 + i] = (bitLen >>> (8 * i)) & 0xFF;
    }

    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;

    final words = Uint32List(16);
    for (var offset = 0; offset < totalLen; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        words[i] =
            padded[j] |
            (padded[j + 1] << 8) |
            (padded[j + 2] << 16) |
            (padded[j + 3] << 24);
      }

      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;

      for (var i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) & 15;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) & 15;
        } else {
          f = c ^ (b | (~d));
          g = (7 * i) & 15;
        }

        f &= 0xFFFFFFFF;
        final temp = (a + f + _k[i] + words[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl32(temp, _shifts[i])) & 0xFFFFFFFF;
      }

      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }

    final digest = Uint8List(16);
    _writeUint32Le(digest, 0, a0);
    _writeUint32Le(digest, 4, b0);
    _writeUint32Le(digest, 8, c0);
    _writeUint32Le(digest, 12, d0);
    return digest;
  }

  /// Computes the 32-character lowercase hexadecimal RFC 1321 MD5 digest of
  /// UTF-8 encoded [input].
  static String md5Hex(String input) => hexEncode(md5Bytes(utf8.encode(input)));

  /// Computes the 16-character middle slice (`[8, 24)`) of the MD5 hex digest,
  /// matching Legado's `java.md5Encode16`.
  static String md5Hex16(String input) => md5Hex(input).substring(8, 24);

  /// Encodes [bytes] into lowercase hexadecimal.
  static String hexEncode(List<int> bytes) {
    final buf = StringBuffer();
    for (final byte in bytes) {
      buf.write((byte & 0xFF).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Decodes a hexadecimal string (ignoring whitespace) into raw bytes.
  static Uint8List hexDecodeBytes(String input) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return Uint8List(0);
    if (cleaned.length.isOdd) {
      throw FormatException(
        'Hex string must have an even length (got ${cleaned.length} chars).',
      );
    }
    final out = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < cleaned.length; i += 2) {
      final pair = cleaned.substring(i, i + 2);
      final byte = int.tryParse(pair, radix: 16);
      if (byte == null) {
        throw FormatException('Invalid hex byte "$pair" at offset $i.');
      }
      out[i ~/ 2] = byte;
    }
    return out;
  }

  /// Encodes UTF-8 [input] to Base64.
  static String base64EncodeString(String input) =>
      base64Encode(utf8.encode(input));

  /// Decodes a Base64 string (normalizing whitespace/padding) into bytes.
  static Uint8List base64DecodeBytes(String input) {
    var normalized = input.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return Uint8List(0);
    // Support URL-safe Base64 variants transparently.
    normalized = normalized.replaceAll('-', '+').replaceAll('_', '/');
    final mod = normalized.length % 4;
    if (mod == 1) {
      throw const FormatException('Invalid Base64 length.');
    }
    if (mod != 0) {
      normalized = normalized.padRight(normalized.length + (4 - mod), '=');
    }
    return base64Decode(normalized);
  }

  /// Decodes a Base64 string into a UTF-8 string.
  static String base64DecodeString(String input) {
    final bytes = base64DecodeBytes(input);
    if (bytes.isEmpty) return '';
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Validates [key] and [transformation] upfront and returns the parsed spec.
  static SymmetricTransformation validateSymmetricConfig({
    required List<int> key,
    required String transformation,
    List<int>? iv,
  }) {
    final spec = SymmetricTransformation.parse(
      transformation,
      hasNonEmptyIv: iv != null && iv.isNotEmpty,
    );
    _validateKeyLength(spec.algorithm, key.length);
    return spec;
  }

  /// Encrypts [data] using FIPS-197 AES (128/192/256) or FIPS-46 DES according
  /// to [transformation] (`ECB`/`CBC`, `PKCS5Padding`/`PKCS7Padding`/
  /// `ZeroPadding`/`NoPadding`).
  static Uint8List encryptSymmetric({
    required List<int> data,
    required List<int> key,
    String transformation = 'AES/ECB/PKCS5Padding',
    List<int>? iv,
  }) {
    final spec = validateSymmetricConfig(
      key: key,
      transformation: transformation,
      iv: iv,
    );
    final keyBytes = _toUint8List(key);
    final blockSize = spec.blockSize;
    final padded = _padInput(_toUint8List(data), blockSize, spec.padding);
    if (padded.isEmpty) return Uint8List(0);

    final out = Uint8List(padded.length);
    final encryptBlock = _buildBlockCipher(
      spec.algorithm,
      keyBytes,
      encrypt: true,
    );

    if (spec.mode == SymmetricMode.ecb) {
      for (var offset = 0; offset < padded.length; offset += blockSize) {
        final block = Uint8List.sublistView(padded, offset, offset + blockSize);
        out.setRange(offset, offset + blockSize, encryptBlock(block));
      }
      return out;
    }

    var chain = _normalizeIv(iv, blockSize);
    final xored = Uint8List(blockSize);
    for (var offset = 0; offset < padded.length; offset += blockSize) {
      for (var i = 0; i < blockSize; i++) {
        xored[i] = padded[offset + i] ^ chain[i];
      }
      final cipherBlock = encryptBlock(xored);
      out.setRange(offset, offset + blockSize, cipherBlock);
      chain = cipherBlock;
    }
    return out;
  }

  /// Decrypts [data] using FIPS-197 AES (128/192/256) or FIPS-46 DES according
  /// to [transformation] (`ECB`/`CBC`, `PKCS5Padding`/`PKCS7Padding`/
  /// `ZeroPadding`/`NoPadding`).
  static Uint8List decryptSymmetric({
    required List<int> data,
    required List<int> key,
    String transformation = 'AES/ECB/PKCS5Padding',
    List<int>? iv,
  }) {
    final spec = validateSymmetricConfig(
      key: key,
      transformation: transformation,
      iv: iv,
    );
    final cipherBytes = _toUint8List(data);
    final blockSize = spec.blockSize;

    if (cipherBytes.isEmpty) {
      if (spec.padding == SymmetricPadding.zero ||
          spec.padding == SymmetricPadding.none) {
        return Uint8List(0);
      }
      throw const FormatException(
        'Ciphertext must not be empty for PKCS5/PKCS7 padding.',
      );
    }
    if (cipherBytes.length % blockSize != 0) {
      throw FormatException(
        'Ciphertext length (${cipherBytes.length}) must be a multiple of block size ($blockSize).',
      );
    }

    final keyBytes = _toUint8List(key);
    final decryptBlock = _buildBlockCipher(
      spec.algorithm,
      keyBytes,
      encrypt: false,
    );
    final decrypted = Uint8List(cipherBytes.length);

    if (spec.mode == SymmetricMode.ecb) {
      for (var offset = 0; offset < cipherBytes.length; offset += blockSize) {
        final block = Uint8List.sublistView(
          cipherBytes,
          offset,
          offset + blockSize,
        );
        decrypted.setRange(offset, offset + blockSize, decryptBlock(block));
      }
    } else {
      var prev = _normalizeIv(iv, blockSize);
      for (var offset = 0; offset < cipherBytes.length; offset += blockSize) {
        final block = Uint8List.sublistView(
          cipherBytes,
          offset,
          offset + blockSize,
        );
        final plainBlock = decryptBlock(block);
        for (var i = 0; i < blockSize; i++) {
          decrypted[offset + i] = plainBlock[i] ^ prev[i];
        }
        prev = block;
      }
    }

    return _unpadOutput(decrypted, blockSize, spec.padding);
  }

  /// Encrypts UTF-8 [plainText] with AES and returns a Base64 string.
  static String aesEncryptBase64(
    String plainText,
    String key, {
    String? transformation,
    String? iv,
  }) {
    final spec = SymmetricTransformation.parse(
      transformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: iv != null && iv.isNotEmpty,
    );
    if (spec.algorithm != SymmetricAlgorithm.aes) {
      throw ArgumentError.value(
        transformation,
        'transformation',
        'aesEncryptBase64 requires an AES transformation.',
      );
    }
    final cipher = encryptSymmetric(
      data: utf8.encode(plainText),
      key: utf8.encode(key),
      transformation: spec.canonical,
      iv: iv == null ? null : utf8.encode(iv),
    );
    return base64Encode(cipher);
  }

  /// Decrypts Base64 [base64CipherText] with AES and returns a UTF-8 string.
  static String aesDecryptBase64(
    String base64CipherText,
    String key, {
    String? transformation,
    String? iv,
  }) {
    final spec = SymmetricTransformation.parse(
      transformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: iv != null && iv.isNotEmpty,
    );
    if (spec.algorithm != SymmetricAlgorithm.aes) {
      throw ArgumentError.value(
        transformation,
        'transformation',
        'aesDecryptBase64 requires an AES transformation.',
      );
    }
    final plain = decryptSymmetric(
      data: base64DecodeBytes(base64CipherText),
      key: utf8.encode(key),
      transformation: spec.canonical,
      iv: iv == null ? null : utf8.encode(iv),
    );
    return utf8.decode(plain, allowMalformed: true);
  }

  /// Encrypts UTF-8 [plainText] with AES and returns a lowercase hex string.
  static String aesEncryptHex(
    String plainText,
    String key, {
    String? transformation,
    String? iv,
  }) {
    final spec = SymmetricTransformation.parse(
      transformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: iv != null && iv.isNotEmpty,
    );
    if (spec.algorithm != SymmetricAlgorithm.aes) {
      throw ArgumentError.value(
        transformation,
        'transformation',
        'aesEncryptHex requires an AES transformation.',
      );
    }
    final cipher = encryptSymmetric(
      data: utf8.encode(plainText),
      key: utf8.encode(key),
      transformation: spec.canonical,
      iv: iv == null ? null : utf8.encode(iv),
    );
    return hexEncode(cipher);
  }

  /// Decrypts hexadecimal [hexCipherText] with AES and returns a UTF-8 string.
  static String aesDecryptHex(
    String hexCipherText,
    String key, {
    String? transformation,
    String? iv,
  }) {
    final spec = SymmetricTransformation.parse(
      transformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: iv != null && iv.isNotEmpty,
    );
    if (spec.algorithm != SymmetricAlgorithm.aes) {
      throw ArgumentError.value(
        transformation,
        'transformation',
        'aesDecryptHex requires an AES transformation.',
      );
    }
    final plain = decryptSymmetric(
      data: hexDecodeBytes(hexCipherText),
      key: utf8.encode(key),
      transformation: spec.canonical,
      iv: iv == null ? null : utf8.encode(iv),
    );
    return utf8.decode(plain, allowMalformed: true);
  }

  /// Coerces JS/Dart dynamic values (`String`, `List<int>`, or indexed byte
  /// `Map<String, dynamic>` from `Uint8Array` JSONification) into bytes.
  static Uint8List coerceBytes(Object? value, {String name = 'value'}) {
    if (value == null) return Uint8List(0);
    if (value is Uint8List) return value;
    if (value is String) return Uint8List.fromList(utf8.encode(value));
    if (value is List) {
      final out = Uint8List(value.length);
      for (var i = 0; i < value.length; i++) {
        out[i] = _coerceSingleByte(value[i], index: i, name: name);
      }
      return out;
    }
    if (value is Map) {
      final out = Uint8List(value.length);
      for (var i = 0; i < value.length; i++) {
        final k = i.toString();
        if (!value.containsKey(k)) {
          throw ArgumentError.value(
            value,
            name,
            'Expected String or byte array for $name.',
          );
        }
        out[i] = _coerceSingleByte(value[k], index: i, name: name);
      }
      return out;
    }
    throw ArgumentError.value(
      value,
      name,
      'Expected String or byte array for $name, got ${value.runtimeType}.',
    );
  }

  /// Decodes ciphertext passed as raw bytes (`List<int>`), hexadecimal
  /// `String`, or Base64 `String`.
  static Uint8List decodeCiphertextInput(
    Object? data, {
    required int blockSize,
  }) {
    if (data == null) return Uint8List(0);
    if (data is List || data is Map || data is Uint8List) {
      return coerceBytes(data, name: 'data');
    }
    final raw = data.toString().trim();
    if (raw.isEmpty) return Uint8List(0);
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= blockSize * 2 &&
        compact.length.isEven &&
        (compact.length ~/ 2) % blockSize == 0 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
      return hexDecodeBytes(compact);
    }
    return base64DecodeBytes(compact);
  }

  static int _coerceSingleByte(
    Object? raw, {
    required int index,
    required String name,
  }) {
    if (raw is int && raw >= -128 && raw <= 255) {
      return raw & 0xFF;
    }
    if (raw is num &&
        raw.isFinite &&
        raw == raw.truncateToDouble() &&
        raw >= -128 &&
        raw <= 255) {
      return raw.toInt() & 0xFF;
    }
    throw ArgumentError(
      'Invalid byte value "$raw" at index $index in $name (expected -128..255).',
    );
  }

  static void _validateKeyLength(SymmetricAlgorithm algorithm, int length) {
    if (algorithm == SymmetricAlgorithm.aes) {
      if (length != 16 && length != 24 && length != 32) {
        throw ArgumentError(
          'Invalid AES key length: expected 16, 24, or 32 bytes, got $length bytes.',
        );
      }
    } else {
      if (length != 8) {
        throw ArgumentError(
          'Invalid DES key length: expected 8 bytes, got $length bytes.',
        );
      }
    }
  }

  static Uint8List _normalizeIv(List<int>? iv, int blockSize) {
    final out = Uint8List(blockSize);
    if (iv == null || iv.isEmpty) return out;
    final count = iv.length < blockSize ? iv.length : blockSize;
    for (var i = 0; i < count; i++) {
      out[i] = iv[i] & 0xFF;
    }
    return out;
  }

  static Uint8List _toUint8List(List<int> input) {
    if (input is Uint8List) return input;
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[i] & 0xFF;
    }
    return out;
  }

  static Uint8List _padInput(
    Uint8List data,
    int blockSize,
    SymmetricPadding padding,
  ) {
    switch (padding) {
      case SymmetricPadding.pkcs5:
      case SymmetricPadding.pkcs7:
        final padLen = blockSize - (data.length % blockSize);
        final out = Uint8List(data.length + padLen);
        out.setRange(0, data.length, data);
        out.fillRange(data.length, out.length, padLen);
        return out;
      case SymmetricPadding.zero:
        if (data.isEmpty) return Uint8List(0);
        final rem = data.length % blockSize;
        if (rem == 0) return data;
        final padLen = blockSize - rem;
        final out = Uint8List(data.length + padLen);
        out.setRange(0, data.length, data);
        return out;
      case SymmetricPadding.none:
        if (data.length % blockSize != 0) {
          throw ArgumentError(
            'NoPadding requires input length (${data.length}) to be a multiple of block size ($blockSize).',
          );
        }
        return data;
    }
  }

  static Uint8List _unpadOutput(
    Uint8List decrypted,
    int blockSize,
    SymmetricPadding padding,
  ) {
    switch (padding) {
      case SymmetricPadding.pkcs5:
      case SymmetricPadding.pkcs7:
        final padLen = decrypted.last;
        if (padLen < 1 || padLen > blockSize || padLen > decrypted.length) {
          throw FormatException(
            'Invalid PKCS5/PKCS7 padding byte: $padLen (blockSize=$blockSize).',
          );
        }
        for (var i = decrypted.length - padLen; i < decrypted.length; i++) {
          if (decrypted[i] != padLen) {
            throw const FormatException(
              'Corrupted PKCS5/PKCS7 padding bytes.',
            );
          }
        }
        return Uint8List.sublistView(decrypted, 0, decrypted.length - padLen);
      case SymmetricPadding.zero:
        var end = decrypted.length;
        while (end > 0 && decrypted[end - 1] == 0) {
          end--;
        }
        return Uint8List.sublistView(decrypted, 0, end);
      case SymmetricPadding.none:
        return decrypted;
    }
  }

  static Uint8List Function(Uint8List block) _buildBlockCipher(
    SymmetricAlgorithm algorithm,
    Uint8List key, {
    required bool encrypt,
  }) {
    if (algorithm == SymmetricAlgorithm.aes) {
      final nk = key.length ~/ 4;
      final nr = nk + 6;
      final roundKeys = _aesKeyExpansion(key, nk, nr);
      return encrypt
          ? (block) => _aesEncryptBlock(block, roundKeys, nr)
          : (block) => _aesDecryptBlock(block, roundKeys, nr);
    }
    final subkeys = _desGenerateSubkeys(key);
    return encrypt
        ? (block) => _desProcessBlock(block, subkeys, encrypt: true)
        : (block) => _desProcessBlock(block, subkeys, encrypt: false);
  }

  // ---------------------------------------------------------------------------
  // FIPS-197 AES (128 / 192 / 256)
  // ---------------------------------------------------------------------------

  static Uint32List _aesKeyExpansion(Uint8List key, int nk, int nr) {
    final totalWords = 4 * (nr + 1);
    final w = Uint32List(totalWords);
    for (var i = 0; i < nk; i++) {
      w[i] =
          ((key[4 * i] & 0xFF) << 24) |
          ((key[4 * i + 1] & 0xFF) << 16) |
          ((key[4 * i + 2] & 0xFF) << 8) |
          (key[4 * i + 3] & 0xFF);
    }

    for (var i = nk; i < totalWords; i++) {
      var temp = w[i - 1];
      if (i % nk == 0) {
        temp = _aesSubWord(_aesRotWord(temp)) ^ (_aesRcon[i ~/ nk] << 24);
      } else if (nk > 6 && i % nk == 4) {
        temp = _aesSubWord(temp);
      }
      w[i] = (w[i - nk] ^ temp) & 0xFFFFFFFF;
    }
    return w;
  }

  static int _aesRotWord(int word) =>
      ((word << 8) | (word >>> 24)) & 0xFFFFFFFF;

  static int _aesSubWord(int word) {
    return (_aesSBox[(word >>> 24) & 0xFF] << 24) |
        (_aesSBox[(word >>> 16) & 0xFF] << 16) |
        (_aesSBox[(word >>> 8) & 0xFF] << 8) |
        _aesSBox[word & 0xFF];
  }

  static Uint8List _aesEncryptBlock(
    Uint8List input,
    Uint32List roundKeys,
    int nr,
  ) {
    final s = Uint8List.fromList(input);
    _aesAddRoundKey(s, roundKeys, 0);

    for (var round = 1; round < nr; round++) {
      for (var i = 0; i < 16; i++) {
        s[i] = _aesSBox[s[i]];
      }
      _aesShiftRows(s);
      _aesMixColumns(s);
      _aesAddRoundKey(s, roundKeys, round);
    }

    for (var i = 0; i < 16; i++) {
      s[i] = _aesSBox[s[i]];
    }
    _aesShiftRows(s);
    _aesAddRoundKey(s, roundKeys, nr);
    return s;
  }

  static Uint8List _aesDecryptBlock(
    Uint8List input,
    Uint32List roundKeys,
    int nr,
  ) {
    final s = Uint8List.fromList(input);
    _aesAddRoundKey(s, roundKeys, nr);

    for (var round = nr - 1; round >= 1; round--) {
      _aesInvShiftRows(s);
      for (var i = 0; i < 16; i++) {
        s[i] = _aesInvSBox[s[i]];
      }
      _aesAddRoundKey(s, roundKeys, round);
      _aesInvMixColumns(s);
    }

    _aesInvShiftRows(s);
    for (var i = 0; i < 16; i++) {
      s[i] = _aesInvSBox[s[i]];
    }
    _aesAddRoundKey(s, roundKeys, 0);
    return s;
  }

  static void _aesAddRoundKey(Uint8List state, Uint32List w, int round) {
    final base = round * 4;
    for (var col = 0; col < 4; col++) {
      final word = w[base + col];
      final off = col * 4;
      state[off] ^= (word >>> 24) & 0xFF;
      state[off + 1] ^= (word >>> 16) & 0xFF;
      state[off + 2] ^= (word >>> 8) & 0xFF;
      state[off + 3] ^= word & 0xFF;
    }
  }

  static void _aesShiftRows(Uint8List s) {
    var t = s[1];
    s[1] = s[5];
    s[5] = s[9];
    s[9] = s[13];
    s[13] = t;

    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;

    t = s[15];
    s[15] = s[11];
    s[11] = s[7];
    s[7] = s[3];
    s[3] = t;
  }

  static void _aesInvShiftRows(Uint8List s) {
    var t = s[13];
    s[13] = s[9];
    s[9] = s[5];
    s[5] = s[1];
    s[1] = t;

    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;

    t = s[3];
    s[3] = s[7];
    s[7] = s[11];
    s[11] = s[15];
    s[15] = t;
  }

  static int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xFF;

  static int _mul2(int x) => _xtime(x);
  static int _mul3(int x) => _xtime(x) ^ x;
  static int _mul4(int x) => _xtime(_xtime(x));
  static int _mul8(int x) => _xtime(_mul4(x));
  static int _mul9(int x) => _mul8(x) ^ x;
  static int _mul11(int x) => _mul8(x) ^ _mul2(x) ^ x;
  static int _mul13(int x) => _mul8(x) ^ _mul4(x) ^ x;
  static int _mul14(int x) => _mul8(x) ^ _mul4(x) ^ _mul2(x);

  static void _aesMixColumns(Uint8List s) {
    for (var col = 0; col < 4; col++) {
      final i = col * 4;
      final a0 = s[i];
      final a1 = s[i + 1];
      final a2 = s[i + 2];
      final a3 = s[i + 3];
      s[i] = _mul2(a0) ^ _mul3(a1) ^ a2 ^ a3;
      s[i + 1] = a0 ^ _mul2(a1) ^ _mul3(a2) ^ a3;
      s[i + 2] = a0 ^ a1 ^ _mul2(a2) ^ _mul3(a3);
      s[i + 3] = _mul3(a0) ^ a1 ^ a2 ^ _mul2(a3);
    }
  }

  static void _aesInvMixColumns(Uint8List s) {
    for (var col = 0; col < 4; col++) {
      final i = col * 4;
      final a0 = s[i];
      final a1 = s[i + 1];
      final a2 = s[i + 2];
      final a3 = s[i + 3];
      s[i] = _mul14(a0) ^ _mul11(a1) ^ _mul13(a2) ^ _mul9(a3);
      s[i + 1] = _mul9(a0) ^ _mul14(a1) ^ _mul11(a2) ^ _mul13(a3);
      s[i + 2] = _mul13(a0) ^ _mul9(a1) ^ _mul14(a2) ^ _mul11(a3);
      s[i + 3] = _mul11(a0) ^ _mul13(a1) ^ _mul9(a2) ^ _mul14(a3);
    }
  }

  // ---------------------------------------------------------------------------
  // FIPS-46 DES (64-bit block, 64-bit key)
  // ---------------------------------------------------------------------------

  static int _getByteBit1Based(Uint8List bytes, int bit1Based) {
    final idx = bit1Based - 1;
    return (bytes[idx >> 3] >>> (7 - (idx & 7))) & 1;
  }

  static int _getIntBit1Based(int value, int bit1Based, int totalBits) {
    return (value >>> (totalBits - bit1Based)) & 1;
  }

  static List<int> _desGenerateSubkeys(Uint8List key) {
    var c = 0;
    var d = 0;
    for (var i = 0; i < 28; i++) {
      c = (c << 1) | _getByteBit1Based(key, _desPc1[i]);
      d = (d << 1) | _getByteBit1Based(key, _desPc1[28 + i]);
    }

    final subkeys = List<int>.filled(16, 0);
    for (var round = 0; round < 16; round++) {
      final shift = _desKeyShifts[round];
      c = ((c << shift) | (c >>> (28 - shift))) & 0x0FFFFFFF;
      d = ((d << shift) | (d >>> (28 - shift))) & 0x0FFFFFFF;

      var subkey = 0;
      for (var i = 0; i < 48; i++) {
        final pos = _desPc2[i];
        final bit = pos <= 28
            ? _getIntBit1Based(c, pos, 28)
            : _getIntBit1Based(d, pos - 28, 28);
        subkey = (subkey << 1) | bit;
      }
      subkeys[round] = subkey;
    }
    return subkeys;
  }

  static Uint8List _desProcessBlock(
    Uint8List block,
    List<int> subkeys, {
    required bool encrypt,
  }) {
    var l = 0;
    var r = 0;
    for (var i = 0; i < 32; i++) {
      l = (l << 1) | _getByteBit1Based(block, _desIp[i]);
      r = (r << 1) | _getByteBit1Based(block, _desIp[32 + i]);
    }

    for (var round = 0; round < 16; round++) {
      final subkey = encrypt ? subkeys[round] : subkeys[15 - round];
      final nextL = r;
      final nextR = (l ^ _desFeistel(r, subkey)) & 0xFFFFFFFF;
      l = nextL;
      r = nextR;
    }

    // Final swap: (R16 || L16) before inverse initial permutation FP.
    final out = Uint8List(8);
    for (var i = 0; i < 64; i++) {
      final pos = _desFp[i];
      final bit = pos <= 32
          ? _getIntBit1Based(r, pos, 32)
          : _getIntBit1Based(l, pos - 32, 32);
      if (bit != 0) {
        out[i >> 3] |= 1 << (7 - (i & 7));
      }
    }
    return out;
  }

  static int _desFeistel(int r, int subkey48) {
    var expanded = 0;
    for (var i = 0; i < 48; i++) {
      expanded = (expanded << 1) | _getIntBit1Based(r, _desE[i], 32);
    }
    final xored = expanded ^ subkey48;

    var sOut = 0;
    for (var box = 0; box < 8; box++) {
      final chunk = (xored >>> (42 - box * 6)) & 0x3F;
      final row = ((chunk & 0x20) >>> 4) | (chunk & 0x01);
      final col = (chunk >>> 1) & 0x0F;
      sOut = (sOut << 4) | _desSBoxes[box][row * 16 + col];
    }

    var pOut = 0;
    for (var i = 0; i < 32; i++) {
      pOut = (pOut << 1) | _getIntBit1Based(sOut, _desP[i], 32);
    }
    return pOut & 0xFFFFFFFF;
  }

  static int _rotl32(int value, int shift) {
    final v = value & 0xFFFFFFFF;
    return ((v << shift) | (v >>> (32 - shift))) & 0xFFFFFFFF;
  }

  static void _writeUint32Le(Uint8List out, int offset, int value) {
    out[offset] = value & 0xFF;
    out[offset + 1] = (value >>> 8) & 0xFF;
    out[offset + 2] = (value >>> 16) & 0xFF;
    out[offset + 3] = (value >>> 24) & 0xFF;
  }
}
