import 'dart:math';

/// Utility for generating standard RFC 4122 v4 UUID strings using cryptographic randomness
class UuidUtil {
  static final Random _secureRandom = Random.secure();

  /// Generates a v4 random UUID string
  static String generateV4() {
    final values = List<int>.generate(16, (i) => _secureRandom.nextInt(256));

    // Set version to 4 (0100 in bits 4-7 of byte 6)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122 (10 in bits 6-7 of byte 8)
    values[8] = (values[8] & 0x3f) | 0x80;

    String hex(int val) => val.toRadixString(16).padLeft(2, '0');

    final buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(hex(values[i]));
    }

    return buffer.toString();
  }
}
