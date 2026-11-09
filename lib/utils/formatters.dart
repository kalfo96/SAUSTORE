/// Dependency-free display formatting used throughout DreamStore.
///
/// Money is accepted as an integer in the currency's minor unit. For example,
/// `12345` with two decimal digits is displayed as `123.45`, while `12345`
/// with zero decimal digits is displayed as `12,345`.
abstract final class AppFormatters {
  static const List<String> _shortMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _shortWeekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _compactSuffixes = <String>[
    '',
    'K',
    'M',
    'B',
    'T',
    'Q',
  ];

  /// Formats [minorUnits] as money using integer arithmetic.
  ///
  /// Set [decimalDigits] to the number of minor-unit digits used by the
  /// currency (`0` for TZS, `2` for USD, and so on). When both [symbol] and
  /// [code] are supplied the unambiguous code is appended, for example
  /// `$12.50 USD`. Pass an empty [symbol] to show only the code.
  static String money(
    int minorUnits, {
    String symbol = 'TSh',
    String? code,
    int decimalDigits = 0,
  }) {
    _checkDecimalDigits(decimalDigits);

    final scale = _powerOfTen(decimalDigits);
    final absolute = minorUnits.abs();
    final whole = absolute ~/ scale;
    final fraction = absolute.remainder(scale);
    final buffer = StringBuffer(_groupInteger(whole));

    if (decimalDigits > 0) {
      buffer
        ..write('.')
        ..write(fraction.toString().padLeft(decimalDigits, '0'));
    }

    return _withCurrency(
      buffer.toString(),
      negative: minorUnits.isNegative,
      symbol: symbol,
      code: code,
    );
  }

  /// Formats large monetary values with a compact suffix such as K, M, or B.
  ///
  /// Values below one thousand major units are returned using [money]. The
  /// compact part uses at most [fractionDigits] digits and removes trailing
  /// zeroes.
  static String compactMoney(
    int minorUnits, {
    String symbol = 'TSh',
    String? code,
    int decimalDigits = 0,
    int fractionDigits = 1,
  }) {
    _checkDecimalDigits(decimalDigits);
    RangeError.checkValueInInterval(fractionDigits, 0, 3, 'fractionDigits');

    final scale = _powerOfTen(decimalDigits);
    final absolute = minorUnits.abs();
    if (absolute < scale * 1000) {
      return money(
        minorUnits,
        symbol: symbol,
        code: code,
        decimalDigits: decimalDigits,
      );
    }

    var suffixIndex = 0;
    var divisor = scale.toDouble();
    final absoluteAsDouble = absolute.toDouble();
    while (suffixIndex < _compactSuffixes.length - 1 &&
        absoluteAsDouble >= divisor * 1000) {
      divisor *= 1000;
      suffixIndex++;
    }

    var compactValue = absoluteAsDouble / divisor;
    var rounded = double.parse(compactValue.toStringAsFixed(fractionDigits));

    // Avoid awkward edge output such as 1000K after rounding.
    if (rounded >= 1000 && suffixIndex < _compactSuffixes.length - 1) {
      suffixIndex++;
      compactValue /= 1000;
      rounded = double.parse(compactValue.toStringAsFixed(fractionDigits));
    }

    final amount =
        '${_trimFraction(rounded.toStringAsFixed(fractionDigits))}'
        '${_compactSuffixes[suffixIndex]}';
    return _withCurrency(
      amount,
      negative: minorUnits.isNegative,
      symbol: symbol,
      code: code,
    );
  }

  /// Adds thousands separators to an integer quantity.
  static String quantity(int value) {
    final sign = value.isNegative ? '-' : '';
    return '$sign${_groupInteger(value.abs())}';
  }

  /// Produces a short, human-readable description relative to [now].
  ///
  /// Passing [now] is useful when rendering a stable list and makes tests fully
  /// deterministic. Dates at least seven days away fall back to [date].
  static String relativeTime(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final difference = value.difference(reference);
    final future = difference > Duration.zero;
    final elapsed = difference.abs();

    if (elapsed < const Duration(seconds: 10)) {
      return 'Just now';
    }
    if (elapsed < const Duration(minutes: 1)) {
      return future
          ? 'in ${elapsed.inSeconds} sec'
          : '${elapsed.inSeconds} sec ago';
    }
    if (elapsed < const Duration(hours: 1)) {
      final minutes = elapsed.inMinutes;
      return future
          ? 'in $minutes ${minutes == 1 ? 'min' : 'mins'}'
          : '$minutes ${minutes == 1 ? 'min' : 'mins'} ago';
    }
    if (elapsed < const Duration(days: 1)) {
      final hours = elapsed.inHours;
      return future
          ? 'in $hours ${hours == 1 ? 'hr' : 'hrs'}'
          : '$hours ${hours == 1 ? 'hr' : 'hrs'} ago';
    }
    if (elapsed < const Duration(days: 2)) {
      return future ? 'Tomorrow' : 'Yesterday';
    }
    if (elapsed < const Duration(days: 7)) {
      final days = elapsed.inDays;
      return future ? 'in $days days' : '$days days ago';
    }
    return date(value);
  }

  /// Formats a date as `12 Sep 2026`.
  ///
  /// The fields are read in the timezone already carried by [value]. Call
  /// `toLocal()` first when converting a UTC persistence timestamp for display.
  static String date(
    DateTime value, {
    bool includeYear = true,
    bool includeWeekday = false,
  }) {
    final weekday = includeWeekday
        ? '${_shortWeekdays[value.weekday - 1]}, '
        : '';
    final year = includeYear ? ' ${value.year}' : '';
    return '$weekday${value.day} ${_shortMonths[value.month - 1]}$year';
  }

  /// Formats a time in 12-hour form by default, for example `3:05 PM`.
  static String time(
    DateTime value, {
    bool use24Hour = false,
    bool includeSeconds = false,
  }) {
    final minute = _twoDigits(value.minute);
    final second = includeSeconds ? ':${_twoDigits(value.second)}' : '';

    if (use24Hour) {
      return '${_twoDigits(value.hour)}:$minute$second';
    }

    final period = value.hour < 12 ? 'AM' : 'PM';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:$minute$second $period';
  }

  /// Combines [date] and [time] with a compact visual separator.
  static String dateTime(
    DateTime value, {
    bool includeYear = true,
    bool includeWeekday = false,
    bool use24Hour = false,
    bool includeSeconds = false,
  }) {
    return '${date(value, includeYear: includeYear, includeWeekday: includeWeekday)}'
        ' • '
        '${time(value, use24Hour: use24Hour, includeSeconds: includeSeconds)}';
  }

  /// Normalizes a stored receipt identifier and adds a leading `#`.
  ///
  /// Set [visibleCharacters] when a compact representation of a long internal
  /// identifier is needed. Human-friendly receipt numbers are preserved by
  /// default.
  static String receiptNumber(String id, {int? visibleCharacters}) {
    if (visibleCharacters != null) {
      RangeError.checkValueInInterval(
        visibleCharacters,
        1,
        64,
        'visibleCharacters',
      );
    }

    var normalized = id.trim();
    while (normalized.startsWith('#')) {
      normalized = normalized.substring(1).trimLeft();
    }
    normalized = normalized.toUpperCase();
    if (normalized.isEmpty) {
      return '#—';
    }
    if (visibleCharacters != null && normalized.length > visibleCharacters) {
      normalized = normalized.substring(normalized.length - visibleCharacters);
    }
    return '#$normalized';
  }

  /// Returns a complete receipt label, such as `Receipt #4F29A10C`.
  static String receiptLabel(
    String id, {
    String prefix = 'Receipt',
    int? visibleCharacters,
  }) {
    final cleanPrefix = prefix.trim();
    final number = receiptNumber(id, visibleCharacters: visibleCharacters);
    return cleanPrefix.isEmpty ? number : '$cleanPrefix $number';
  }

  /// Creates avatar initials from a person or business name.
  ///
  /// A single word contributes its first characters; a multi-word name uses
  /// the first character of the first and last words by default.
  static String initials(String name, {int maxCharacters = 2}) {
    RangeError.checkValueInInterval(maxCharacters, 1, 4, 'maxCharacters');
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);

    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return _takeRunes(words.first, maxCharacters).toUpperCase();
    }

    final selected = <String>[_firstRune(words.first)];
    if (maxCharacters > 2) {
      for (
        var index = 1;
        index < words.length - 1 && selected.length < maxCharacters - 1;
        index++
      ) {
        selected.add(_firstRune(words[index]));
      }
    }
    if (selected.length < maxCharacters) {
      selected.add(_firstRune(words.last));
    }
    return selected.join().toUpperCase();
  }

  static void _checkDecimalDigits(int value) {
    RangeError.checkValueInInterval(value, 0, 6, 'decimalDigits');
  }

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }

  static String _groupInteger(int value) {
    final digits = value.toString();
    final firstGroupLength = digits.length % 3;
    final buffer = StringBuffer();
    var index = 0;

    if (firstGroupLength != 0) {
      buffer.write(digits.substring(0, firstGroupLength));
      index = firstGroupLength;
    }
    while (index < digits.length) {
      if (buffer.isNotEmpty) {
        buffer.write(',');
      }
      buffer.write(digits.substring(index, index + 3));
      index += 3;
    }
    return buffer.toString();
  }

  static String _withCurrency(
    String amount, {
    required bool negative,
    required String symbol,
    String? code,
  }) {
    final cleanSymbol = symbol.trim();
    final cleanCode = code?.trim().toUpperCase() ?? '';
    final hasCode = cleanCode.isNotEmpty;
    final sign = negative ? '-' : '';

    if (cleanSymbol.isEmpty) {
      return hasCode ? '$sign$cleanCode $amount' : '$sign$amount';
    }

    final symbolIsPunctuation = cleanSymbol.runes.every((rune) {
      final character = String.fromCharCode(rune);
      return !RegExp(r'[A-Za-z0-9]').hasMatch(character);
    });
    final main = symbolIsPunctuation
        ? '$sign$cleanSymbol$amount'
        : '$sign$cleanSymbol $amount';
    if (!hasCode || cleanCode.toLowerCase() == cleanSymbol.toLowerCase()) {
      return main;
    }
    return '$main $cleanCode';
  }

  static String _trimFraction(String value) {
    if (!value.contains('.')) {
      return value;
    }
    var result = value;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    return result.endsWith('.')
        ? result.substring(0, result.length - 1)
        : result;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _firstRune(String value) {
    return String.fromCharCode(value.runes.first);
  }

  static String _takeRunes(String value, int count) {
    return String.fromCharCodes(value.runes.take(count));
  }
}
