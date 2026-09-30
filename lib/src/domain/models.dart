/// Domain models for つづり. Plain Dart, JSON-serializable, no vendor SDKs.
library;

enum Gender { woman, man, nonbinary, unspecified }

extension GenderLabel on Gender {
  String get label => switch (this) {
        Gender.woman => '女性',
        Gender.man => '男性',
        Gender.nonbinary => 'ノンバイナリー',
        Gender.unspecified => '回答しない',
      };
}

/// Who may read a diary entry.
enum DiaryScope { intro, connections, private }

extension DiaryScopeLabel on DiaryScope {
  String get label => switch (this) {
        DiaryScope.intro => '紹介に使う',
        DiaryScope.connections => 'つながった人だけ',
        DiaryScope.private => '自分だけ',
      };
}

enum LetterStatus { pending, accepted, declined, closed }

enum ConnectionStatus { active, ended }

enum PhotoState { hidden, proposed, revealed }

enum ReportCategory { impersonation, solicitation, sexual, harassment, minor, other }

extension ReportCategoryLabel on ReportCategory {
  String get label => switch (this) {
        ReportCategory.impersonation => 'なりすまし',
        ReportCategory.solicitation => '勧誘・営業',
        ReportCategory.sexual => '性的な内容',
        ReportCategory.harassment => '脅し・嫌がらせ',
        ReportCategory.minor => '未成年の疑い',
        ReportCategory.other => 'その他',
      };
}

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.firstWhere((v) => v.name == name, orElse: () => values.first);

DateTime _date(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
String _iso(DateTime d) => d.toUtc().toIso8601String();

class Profile {
  const Profile({
    required this.id,
    required this.penName,
    required this.ageBand,
    required this.prefecture,
    required this.bio,
    required this.gender,
    required this.seeking,
    this.paused = false,
    this.photoSeed = 0,
    this.isDemo = false,
  });

  final String id;
  final String penName;
  final String ageBand;
  final String prefecture;
  final String bio;
  final Gender gender;
  final Set<Gender> seeking;
  final bool paused;

  /// Index into the demo photo palette. Real photos are not handled in v0.
  final int photoSeed;

  /// True for the fictional writers bundled with the demo.
  final bool isDemo;

  Profile copyWith({
    String? penName,
    String? ageBand,
    String? prefecture,
    String? bio,
    Gender? gender,
    Set<Gender>? seeking,
    bool? paused,
  }) =>
      Profile(
        id: id,
        penName: penName ?? this.penName,
        ageBand: ageBand ?? this.ageBand,
        prefecture: prefecture ?? this.prefecture,
        bio: bio ?? this.bio,
        gender: gender ?? this.gender,
        seeking: seeking ?? this.seeking,
        paused: paused ?? this.paused,
        photoSeed: photoSeed,
        isDemo: isDemo,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'penName': penName,
        'ageBand': ageBand,
        'prefecture': prefecture,
        'bio': bio,
        'gender': gender.name,
        'seeking': seeking.map((g) => g.name).toList(),
        'paused': paused,
        'photoSeed': photoSeed,
        'isDemo': isDemo,
      };

  factory Profile.fromJson(Map<String, Object?> j) => Profile(
        id: j['id'] as String,
        penName: j['penName'] as String,
        ageBand: j['ageBand'] as String,
        prefecture: j['prefecture'] as String,
        bio: (j['bio'] as String?) ?? '',
        gender: _enum(Gender.values, j['gender']),
        seeking: ((j['seeking'] as List?) ?? const [])
            .map((n) => _enum(Gender.values, n))
            .toSet(),
        paused: (j['paused'] as bool?) ?? false,
        photoSeed: (j['photoSeed'] as int?) ?? 0,
        isDemo: (j['isDemo'] as bool?) ?? false,
      );
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.authorId,
    required this.body,
    required this.scope,
    required this.createdAt,
    this.prompt,
  });

  final String id;
  final String authorId;
  final String body;
  final DiaryScope scope;
  final DateTime createdAt;
  final String? prompt;

  Map<String, Object?> toJson() => {
        'id': id,
        'authorId': authorId,
        'body': body,
        'scope': scope.name,
        'createdAt': _iso(createdAt),
        'prompt': prompt,
      };

  factory DiaryEntry.fromJson(Map<String, Object?> j) => DiaryEntry(
        id: j['id'] as String,
        authorId: j['authorId'] as String,
        body: j['body'] as String,
        scope: _enum(DiaryScope.values, j['scope']),
        createdAt: _date(j['createdAt']),
        prompt: j['prompt'] as String?,
      );
}

/// The first message: a quoted sentence from a diary plus an impression.
class Letter {
  const Letter({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.diaryId,
    required this.quote,
    required this.body,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String fromId;
  final String toId;
  final String diaryId;
  final String quote;
  final String body;
  final LetterStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  Letter withStatus(LetterStatus s, DateTime at) => Letter(
        id: id,
        fromId: fromId,
        toId: toId,
        diaryId: diaryId,
        quote: quote,
        body: body,
        status: s,
        createdAt: createdAt,
        resolvedAt: at,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'diaryId': diaryId,
        'quote': quote,
        'body': body,
        'status': status.name,
        'createdAt': _iso(createdAt),
        'resolvedAt': resolvedAt == null ? null : _iso(resolvedAt!),
      };

  factory Letter.fromJson(Map<String, Object?> j) => Letter(
        id: j['id'] as String,
        fromId: j['fromId'] as String,
        toId: j['toId'] as String,
        diaryId: j['diaryId'] as String,
        quote: j['quote'] as String,
        body: j['body'] as String,
        status: _enum(LetterStatus.values, j['status']),
        createdAt: _date(j['createdAt']),
        resolvedAt: _dateOrNull(j['resolvedAt']),
      );
}

class Connection {
  const Connection({
    required this.id,
    required this.members,
    required this.createdAt,
    required this.status,
    this.photoState = PhotoState.hidden,
    this.proposedBy,
    this.proposedAt,
    this.revealedAt,
    this.endedAt,
  });

  final String id;
  final List<String> members;
  final DateTime createdAt;
  final ConnectionStatus status;
  final PhotoState photoState;
  final String? proposedBy;
  final DateTime? proposedAt;
  final DateTime? revealedAt;
  final DateTime? endedAt;

  bool includes(String userId) => members.contains(userId);
  String partnerOf(String userId) => members.firstWhere((m) => m != userId);

  Connection copyWith({
    ConnectionStatus? status,
    PhotoState? photoState,
    String? proposedBy,
    DateTime? proposedAt,
    DateTime? revealedAt,
    DateTime? endedAt,
    bool clearProposal = false,
  }) =>
      Connection(
        id: id,
        members: members,
        createdAt: createdAt,
        status: status ?? this.status,
        photoState: photoState ?? this.photoState,
        proposedBy: clearProposal ? null : (proposedBy ?? this.proposedBy),
        proposedAt: clearProposal ? null : (proposedAt ?? this.proposedAt),
        revealedAt: revealedAt ?? this.revealedAt,
        endedAt: endedAt ?? this.endedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'members': members,
        'createdAt': _iso(createdAt),
        'status': status.name,
        'photoState': photoState.name,
        'proposedBy': proposedBy,
        'proposedAt': proposedAt == null ? null : _iso(proposedAt!),
        'revealedAt': revealedAt == null ? null : _iso(revealedAt!),
        'endedAt': endedAt == null ? null : _iso(endedAt!),
      };

  factory Connection.fromJson(Map<String, Object?> j) => Connection(
        id: j['id'] as String,
        members: List<String>.from(j['members'] as List),
        createdAt: _date(j['createdAt']),
        status: _enum(ConnectionStatus.values, j['status']),
        photoState: _enum(PhotoState.values, j['photoState']),
        proposedBy: j['proposedBy'] as String?,
        proposedAt: _dateOrNull(j['proposedAt']),
        revealedAt: _dateOrNull(j['revealedAt']),
        endedAt: _dateOrNull(j['endedAt']),
      );
}

class PageReply {
  const PageReply({required this.authorId, required this.body, required this.createdAt});
  final String authorId;
  final String body;
  final DateTime createdAt;

  Map<String, Object?> toJson() =>
      {'authorId': authorId, 'body': body, 'createdAt': _iso(createdAt)};

  factory PageReply.fromJson(Map<String, Object?> j) => PageReply(
        authorId: j['authorId'] as String,
        body: j['body'] as String,
        createdAt: _date(j['createdAt']),
      );
}

/// A page of "ふたりの日記".
class SharedPage {
  const SharedPage({
    required this.id,
    required this.connectionId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.replies = const [],
  });

  final String id;
  final String connectionId;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final List<PageReply> replies;

  SharedPage withReply(PageReply r) => SharedPage(
        id: id,
        connectionId: connectionId,
        authorId: authorId,
        body: body,
        createdAt: createdAt,
        replies: [...replies, r],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'connectionId': connectionId,
        'authorId': authorId,
        'body': body,
        'createdAt': _iso(createdAt),
        'replies': replies.map((r) => r.toJson()).toList(),
      };

  factory SharedPage.fromJson(Map<String, Object?> j) => SharedPage(
        id: j['id'] as String,
        connectionId: j['connectionId'] as String,
        authorId: j['authorId'] as String,
        body: j['body'] as String,
        createdAt: _date(j['createdAt']),
        replies: ((j['replies'] as List?) ?? const [])
            .map((r) => PageReply.fromJson(Map<String, Object?>.from(r as Map)))
            .toList(),
      );
}

class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.targetId,
    required this.context,
    required this.category,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String reporterId;
  final String targetId;

  /// letter | page | diary | profile
  final String context;
  final ReportCategory category;
  final String note;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'reporterId': reporterId,
        'targetId': targetId,
        'context': context,
        'category': category.name,
        'note': note,
        'createdAt': _iso(createdAt),
      };

  factory Report.fromJson(Map<String, Object?> j) => Report(
        id: j['id'] as String,
        reporterId: j['reporterId'] as String,
        targetId: j['targetId'] as String,
        context: j['context'] as String,
        category: _enum(ReportCategory.values, j['category']),
        note: (j['note'] as String?) ?? '',
        createdAt: _date(j['createdAt']),
      );
}
