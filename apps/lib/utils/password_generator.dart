import 'dart:math';

/// Cryptographically secure password generation and entropy estimation utility
class PasswordGenerator {
  static const String upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String digits = '0123456789';
  static const String symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

  static final Random _secureRandom = Random.secure();

  /// Generates a secure random password with the specified options
  static String generate({
    int length = 16,
    bool includeUpper = true,
    bool includeLower = true,
    bool includeDigits = true,
    bool includeSymbols = true,
  }) {
    if (length < 4) length = 4;
    if (length > 128) length = 128;

    final StringBuffer charSet = StringBuffer();
    final List<String> mandatoryChars = [];

    if (includeUpper) {
      charSet.write(upper);
      mandatoryChars.add(upper[_secureRandom.nextInt(upper.length)]);
    }
    if (includeLower) {
      charSet.write(lower);
      mandatoryChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }
    if (includeDigits) {
      charSet.write(digits);
      mandatoryChars.add(digits[_secureRandom.nextInt(digits.length)]);
    }
    if (includeSymbols) {
      charSet.write(symbols);
      mandatoryChars.add(symbols[_secureRandom.nextInt(symbols.length)]);
    }

    if (charSet.isEmpty) {
      charSet.write(lower);
      mandatoryChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }

    final String pool = charSet.toString();
    final List<String> result = List<String>.from(mandatoryChars);

    while (result.length < length) {
      result.add(pool[_secureRandom.nextInt(pool.length)]);
    }

    // Cryptographic shuffle
    for (int i = result.length - 1; i > 0; i--) {
      final int j = _secureRandom.nextInt(i + 1);
      final temp = result[i];
      result[i] = result[j];
      result[j] = temp;
    }

    return result.join();
  }

  /// Calculates a strength score between 0.0 (very weak) and 1.0 (very strong)
  static double calculateStrength(String password) {
    if (password.isEmpty) return 0.0;

    double score = 0.0;
    if (password.length >= 8) score += 0.2;
    if (password.length >= 12) score += 0.2;
    if (password.length >= 16) score += 0.2;

    if (password.contains(RegExp(r'[A-Z]'))) score += 0.1;
    if (password.contains(RegExp(r'[a-z]'))) score += 0.1;
    if (password.contains(RegExp(r'[0-9]'))) score += 0.1;
    if (password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score += 0.1;

    return score.clamp(0.0, 1.0);
  }
}
