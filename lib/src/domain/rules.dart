/// Product rules that keep つづり calm. Pure functions so they can be tested and
/// later mirrored in Cloud Functions (the server must enforce the same limits).
library;

import 'dart:math';

import 'models.dart';

abstract final class Limits {
  /// People introduced per day.
  static const introsPerDay = 3;

  /// Letters that may wait for an answer at the same time.
  static const pendingLetters = 3;

  /// Active connections at the same time.
  static const activeConnections = 3;

  static const letterMin = 10;
  static const letterMax = 400;
  static const diaryMax = 2000;
  static const pageMax = 2000;
  static const penNameMax = 16;

  /// An unanswered letter quietly closes after this period.
  static const letterLifetime = Duration(days: 14);

  /// Someone introduced within this window is not introduced again.
  static const introCooldownDays = 30;

  /// Only people who wrote an intro diary within this window are introduced.
  static const activeWriterWindow = Duration(days: 30);
}

const allSeekable = {Gender.woman, Gender.man, Gender.nonbinary};

/// True when [a] wants to meet [b]'s gender. "回答しない" is only met by people
/// open to everyone.
bool wantsToMeet(Profile a, Profile b) {
  if (b.gender == Gender.unspecified) {
    return a.seeking.containsAll(allSeekable);
  }
  return a.seeking.contains(b.gender);
}

/// Introductions require the wish to be mutual.
bool mutuallyCompatible(Profile a, Profile b) =>
    a.id != b.id && wantsToMeet(a, b) && wantsToMeet(b, a);

/// The introduction day rolls over at 05:00 Japan time (UTC+9, no DST).
String introDayKey(DateTime now) {
  final t = now.toUtc().add(const Duration(hours: 9 - 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Parsed as UTC so a DST change in the device time zone cannot shorten a day.
int dayDistance(String fromKey, String toKey) =>
    DateTime.parse('${toKey}T00:00:00Z').difference(DateTime.parse('${fromKey}T00:00:00Z')).inDays;

/// Stable 32-bit FNV-1a; String.hashCode is not stable across runs.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Picks today's introductions. No personality scoring: eligibility filters,
/// then a deterministic shuffle per user and day.
List<String> pickIntroductions({
  required Profile me,
  required Iterable<Profile> others,
  required String dayKey,
  required Set<String> excluded,
  required Map<String, String> lastIntroduced,
  required bool Function(String userId) hasRecentIntroDiary,
  required bool Function(String userId) atConnectionLimit,
}) {
  final eligible = others.where((p) {
    if (p.paused || excluded.contains(p.id)) return false;
    if (!mutuallyCompatible(me, p)) return false;
    if (!hasRecentIntroDiary(p.id)) return false;
    if (atConnectionLimit(p.id)) return false;
    final last = lastIntroduced[p.id];
    if (last != null && last != dayKey && dayDistance(last, dayKey) < Limits.introCooldownDays) {
      return false;
    }
    return true;
  }).map((p) => p.id).toList()
    ..sort();
  eligible.shuffle(Random(stableHash('$dayKey/${me.id}')));
  return eligible.take(Limits.introsPerDay).toList();
}

String _halfWidth(String s) => String.fromCharCodes(s.runes.map((r) {
      if (r >= 0xFF01 && r <= 0xFF5E) return r - 0xFEE0;
      if (r == 0x3000) return 0x20;
      if (r == 0x2010 || r == 0x2212) return 0x2D; // ‐ −
      return r;
    }));

final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
final _url = RegExp(r'(https?://|www\.|\b[\w-]+\.(com|jp|net|org|me|io|co)\b)', caseSensitive: false);
final _handle = RegExp(r'@[a-z0-9_.]{3,}', caseSensitive: false);
final _sns = RegExp(
    r'(instagram|インスタ|twitter|ツイッター|discord|ディスコード|kakao|カカオ|telegram|テレグラム|tiktok|ティックトック)',
    caseSensitive: false);
final _line = RegExp(r'(line|ライン|らいん)\s*(id|アイディ|交換|教え|追加|で話)', caseSensitive: false);
final _digitRun = RegExp(r'\d[\d\s\-ー]{8,}\d');

/// Detects contact details that must not be exchanged before connecting.
bool containsContactInfo(String text) {
  final t = _halfWidth(text);
  if (_email.hasMatch(t) || _url.hasMatch(t) || _handle.hasMatch(t)) return true;
  if (_sns.hasMatch(t) || _line.hasMatch(t)) return true;
  for (final m in _digitRun.allMatches(t)) {
    final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return true;
  }
  return false;
}

/// Splits a diary into sentences a reader can quote.
List<String> splitSentences(String body) {
  final result = <String>[];
  final buffer = StringBuffer();
  const enders = {'。', '！', '？', '!', '?', '\n'};
  // 「きょうは、よいてんき。」のような括弧内の句点では区切らない。
  var depth = 0;
  for (final ch in body.split('')) {
    if (ch == '「' || ch == '『') depth++;
    if ((ch == '」' || ch == '』') && depth > 0) depth--;
    if (ch == '\n') depth = 0;
    if (ch != '\n') buffer.write(ch);
    if (enders.contains(ch) && depth == 0) {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) result.add(s);
      buffer.clear();
    }
  }
  final rest = buffer.toString().trim();
  if (rest.isNotEmpty) result.add(rest);
  return result;
}

/// Validates a letter before sending. Returns a user-facing reason or null.
String? letterProblem({required String quote, required String body, required String diaryBody}) {
  final trimmed = body.trim();
  if (quote.isEmpty || !diaryBody.contains(quote)) return '日記の中から一文を選んでください。';
  if (trimmed.charCount < Limits.letterMin) return '感想は${Limits.letterMin}文字以上で書いてください。';
  if (trimmed.charCount > Limits.letterMax) return '感想は${Limits.letterMax}文字までです。';
  if (containsContactInfo(trimmed)) {
    return 'つながる前の連絡先の交換は控えてください。電話番号・メールアドレス・URL・SNSのIDを消してから送れます。';
  }
  return null;
}

extension on String {
  /// Counts user-perceived characters closely enough for Japanese text.
  int get charCount => runes.length;
}

/// Photo reveal state machine.
abstract final class PhotoRules {
  static bool canPropose(Connection c) =>
      c.status == ConnectionStatus.active && c.photoState == PhotoState.hidden;

  static bool canCancel(Connection c, String userId) =>
      c.status == ConnectionStatus.active &&
      c.photoState == PhotoState.proposed &&
      c.proposedBy == userId;

  /// Only the other member can consent, which reveals both photos at once.
  static bool canConsent(Connection c, String userId) =>
      c.status == ConnectionStatus.active &&
      c.photoState == PhotoState.proposed &&
      c.proposedBy != null &&
      c.proposedBy != userId &&
      c.includes(userId);

  static bool photosVisible(Connection c) =>
      c.status == ConnectionStatus.active && c.photoState == PhotoState.revealed;
}
