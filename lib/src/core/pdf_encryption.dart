import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
// `pdf` publishes `PdfEncryption` as the extension point for this, but does not
// re-export the value types an encryption dictionary is built from. The import
// is kept in this one file so a package upgrade has a single place to fix.
// ignore_for_file: implementation_imports
import 'package:pdf/src/pdf/format/num.dart';
import 'package:pdf/src/pdf/format/object_base.dart';
import 'package:pdf/src/pdf/format/string.dart';

/// The 32 byte padding string every PDF password is rounded up with.
const List<int> _padding = <int>[
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

/// Password protection for the produced PDF.
///
/// The `pdf` package leaves the security handler to the caller, so this is the
/// standard one (PDF 1.4, revision 3, RC4 with a 128 bit key): the document and
/// its text cannot be opened without the password. PDF viewers accept it
/// everywhere, including the Android viewers people are likely to use.
///
/// RC4 is only as strong as the password, and the password is never stored on
/// disk: it lives in the screen's state and disappears with the app.
class PdfPasswordProtection extends PdfEncryption {
  PdfPasswordProtection(PdfDocument document, {required String password})
      : _userPassword = password,
        super(document) {
    final Uint8List ownerValue = _ownerValue();
    _fileKey = _fileKeyFor(document, ownerValue);
    final Uint8List userValue = _userValue(document);

    params['/Filter'] = const PdfName('/Standard');
    params['/V'] = const PdfNum(2);
    params['/R'] = const PdfNum(3);
    params['/Length'] = const PdfNum(128);
    params['/P'] = const PdfNum(_permissions);
    params['/O'] = PdfString(ownerValue, format: PdfStringFormat.binary, encrypted: false);
    params['/U'] = PdfString(userValue, format: PdfStringFormat.binary, encrypted: false);
  }

  final String _userPassword;

  /// `/P` in the security dictionary: what the reader may do once opened.
  /// Every bit of permission is set, so printing and copying stay allowed;
  /// the password only controls who may open the document.
  static const int _permissions = -4;

  late final Uint8List _fileKey;

  /// Encrypt one object's strings and streams with its own key.
  @override
  Uint8List encrypt(Uint8List input, PdfObjectBase object) {
    if (input.isEmpty) {
      return input;
    }
    final Uint8List key = _md5(<int>[
      ..._fileKey,
      object.objser & 0xFF,
      (object.objser >> 8) & 0xFF,
      (object.objser >> 16) & 0xFF,
      object.objgen & 0xFF,
      (object.objgen >> 8) & 0xFF,
    ]);
    return _rc4(key, input);
  }

  Uint8List _ownerValue() {
    // With a single password the owner password is the user password, which
    // keeps the document changeable once it is open.
    Uint8List digest = _md5(_paddedPassword(_userPassword));
    for (int i = 0; i < 50; i++) {
      digest = _md5(digest);
    }
    final Uint8List key = digest.sublist(0, 16);

    Uint8List value = _rc4(key, _paddedPassword(_userPassword));
    for (int i = 1; i <= 19; i++) {
      value = _rc4(_xorKey(key, i), value);
    }
    return value;
  }

  Uint8List _fileKeyFor(PdfDocument document, Uint8List ownerValue) {
    final ByteData permissionBits = ByteData(4)
      ..setInt32(0, _permissions, Endian.little);

    Uint8List digest = _md5(<int>[
      ..._paddedPassword(_userPassword),
      ...ownerValue,
      ...permissionBits.buffer.asUint8List(),
      ...document.documentID,
    ]);
    for (int i = 0; i < 50; i++) {
      digest = _md5(digest);
    }
    return digest.sublist(0, 16);
  }

  Uint8List _userValue(PdfDocument document) {
    Uint8List value = _md5(<int>[..._padding, ...document.documentID]);
    value = _rc4(_fileKey, value);
    for (int i = 1; i <= 19; i++) {
      value = _rc4(_xorKey(_fileKey, i), value);
    }
    // The last 16 bytes are arbitrary per the spec.
    return Uint8List(32)..setAll(0, value);
  }

  static Uint8List _paddedPassword(String password) {
    final List<int> raw = password.codeUnits;
    final Uint8List padded = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      padded[i] = i < raw.length ? raw[i] : _padding[i - raw.length];
    }
    return padded;
  }

  static Uint8List _md5(List<int> input) =>
      Uint8List.fromList(md5.convert(input).bytes);

  static Uint8List _xorKey(Uint8List key, int value) =>
      Uint8List.fromList(<int>[for (final int byte in key) byte ^ value]);

  static Uint8List _rc4(Uint8List key, List<int> input) {
    final List<int> state = List<int>.generate(256, (int i) => i);
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + state[i] + key[i % key.length]) & 0xFF;
      final int swap = state[i];
      state[i] = state[j];
      state[j] = swap;
    }

    final Uint8List output = Uint8List(input.length);
    int i = 0;
    j = 0;
    for (int n = 0; n < input.length; n++) {
      i = (i + 1) & 0xFF;
      j = (j + state[i]) & 0xFF;
      final int swap = state[i];
      state[i] = state[j];
      state[j] = swap;
      output[n] = input[n] ^ state[(state[i] + state[j]) & 0xFF];
    }
    return output;
  }
}
