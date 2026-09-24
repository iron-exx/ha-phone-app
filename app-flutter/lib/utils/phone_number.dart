/// Separators people type or phone books store: spaces, dashes, slashes,
/// dots and brackets ("+49 (30) 123-45 67").
final _separators = RegExp(r'[\s\-/().]');

/// Canonical form for comparing numbers from different sources: separators
/// removed, German international prefixes (+49 / 0049) turned into the
/// national 0, any other "+" into "00". Short internal numbers ("11") and
/// codes ("*1") stay as they are.
String normalizePhoneNumber(String number) {
  var n = number.trim().replaceAll(_separators, '');
  if (n.startsWith('+49')) return '0${n.substring(3)}';
  if (n.startsWith('0049')) return '0${n.substring(4)}';
  if (n.startsWith('+')) n = '00${n.substring(1)}';
  return n;
}

/// Same number, ignoring formatting and +49 vs. 0.
bool phoneNumbersMatch(String a, String b) {
  final na = normalizePhoneNumber(a);
  return na.isNotEmpty && na == normalizePhoneNumber(b);
}
