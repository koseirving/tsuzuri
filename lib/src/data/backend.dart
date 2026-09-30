/// The only surface UI code talks to. A Firebase implementation replaces
/// [DemoBackend] later without touching screens.
library;

import 'package:flutter/foundation.dart';

import '../domain/models.dart';

/// A failure with a message that can be shown to the user as is.
class TsuzuriException implements Exception {
  const TsuzuriException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class TsuzuriBackend extends ChangeNotifier {
  bool get ready;
  Profile? get me;

  Future<void> load();

  // はじめに
  Future<void> createProfile(Profile profile, {required String firstDiary});
  Future<void> updateProfile(Profile profile);
  Future<void> setPaused(bool paused);

  // 読む
  List<Profile> todaysIntroductions();
  Profile? profile(String userId);

  /// Diaries of [authorId] that the current user may read, newest first.
  List<DiaryEntry> readableDiaries(String authorId);
  DiaryEntry? diary(String diaryId);

  // 書く
  List<DiaryEntry> myDiaries();
  Future<DiaryEntry> writeDiary(String body, DiaryScope scope, {String? prompt});

  // 感想
  Future<Letter> sendLetter({required String diaryId, required String quote, required String body});
  List<Letter> incomingLetters();
  List<Letter> outgoingLetters();

  /// The pending or accepted relation with [userId], if any.
  RelationWithUser relationWith(String userId);
  Future<Connection> acceptLetter(String letterId);
  Future<void> declineLetter(String letterId);

  // ふたり
  List<Connection> activeConnections();
  Connection? connection(String connectionId);
  List<SharedPage> pages(String connectionId);
  Future<void> writePage(String connectionId, String body);
  Future<void> replyToPage(String connectionId, String pageId, String body);

  // 写真
  Future<void> proposePhotoReveal(String connectionId);
  Future<void> cancelPhotoProposal(String connectionId);
  Future<void> consentPhotoReveal(String connectionId);

  // 離れる
  Future<void> endConnection(String connectionId);
  Future<void> block(String userId);
  Future<void> report({
    required String targetId,
    required String context,
    required ReportCategory category,
    String? note,
  });
  Set<String> blockedUsers();
  Future<void> unblock(String userId);

  /// Deletes everything stored for this user on the device.
  Future<void> deleteAllData();
}

enum RelationKind { none, letterSent, letterReceived, connected, closed }

class RelationWithUser {
  const RelationWithUser(this.kind, {this.letter, this.connection});
  final RelationKind kind;
  final Letter? letter;
  final Connection? connection;
}
