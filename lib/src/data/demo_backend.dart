/// On-device demo backend. Stores the user's own data in app_core's
/// [LocalStore]; the fictional writers come from [seedWriters].
///
/// Demo writers answer automatically after [demoDelay] so the whole flow can
/// be tried alone. The UI labels this behaviour as a demo.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app_core/app_core.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import 'backend.dart';
import 'seed.dart';

const _kMeta = 'tsuzuri.v1.meta';
const _kMe = 'tsuzuri.v1.me';
const _kDiaries = 'tsuzuri.v1.diaries';
const _kLetters = 'tsuzuri.v1.letters';
const _kConnections = 'tsuzuri.v1.connections';
const _kPages = 'tsuzuri.v1.pages';
const _kSafety = 'tsuzuri.v1.safety';
const _kIntro = 'tsuzuri.v1.intro';
const _listKeys = [_kDiaries, _kLetters, _kConnections, _kPages];
const _plainKeys = [_kMeta, _kMe, _kSafety, _kIntro];

/// SqliteLocalStore rejects records above 65,536 JSON characters, so growing
/// lists are split into chunks below this budget.
const _chunkBudget = 60000;
const _maxRepliesPerPage = 20;

const meId = 'me';

class DemoBackend extends TsuzuriBackend {
  DemoBackend(
    this._store, {
    DateTime Function()? clock,
    this.demoDelay = const Duration(seconds: 8),
  }) : _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _clock;

  /// How long a demo writer "takes" to answer.
  final Duration demoDelay;

  bool _ready = false;
  int _seq = 0;
  Profile? _me;
  final List<DiaryEntry> _myDiaries = [];
  final List<Letter> _letters = [];
  final List<Connection> _connections = [];
  final List<SharedPage> _pages = [];
  final Set<String> _blocked = {};
  final List<Report> _reports = [];
  String? _introDay;
  List<String> _introIds = [];
  final Map<String, String> _lastIntroduced = {};

  late final Map<String, SeedWriter> _writers = {
    for (final w in seedWriters) w.profile.id: w,
  };

  DateTime get _now => _clock().toUtc();

  @override
  bool get ready => _ready;

  @override
  Profile? get me => _me;

  List<Report> get reports => List.unmodifiable(_reports);

  // ---------------------------------------------------------------- storage

  @override
  Future<void> load() async {
    final meta = await _store.read(_kMeta);
    _seq = (meta?['seq'] as int?) ?? 0;
    final me = await _store.read(_kMe);
    _me = me == null ? null : Profile.fromJson(me);

    _myDiaries
      ..clear()
      ..addAll((await _readList(_kDiaries)).map(DiaryEntry.fromJson));
    _letters
      ..clear()
      ..addAll((await _readList(_kLetters)).map(Letter.fromJson));
    _connections
      ..clear()
      ..addAll((await _readList(_kConnections)).map(Connection.fromJson));
    _pages
      ..clear()
      ..addAll((await _readList(_kPages)).map(SharedPage.fromJson));

    final safety = await _store.read(_kSafety);
    _blocked
      ..clear()
      ..addAll(((safety?['blocked'] as List?) ?? const []).cast<String>());
    _reports
      ..clear()
      ..addAll(((safety?['reports'] as List?) ?? const [])
          .map((r) => Report.fromJson(Map<String, Object?>.from(r as Map))));

    final intro = await _store.read(_kIntro);
    _introDay = intro?['day'] as String?;
    _introIds = ((intro?['ids'] as List?) ?? const []).cast<String>().toList();
    _lastIntroduced
      ..clear()
      ..addAll(Map<String, String>.from((intro?['last'] as Map?) ?? const {}));

    _ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await _store.write(_kMeta, {'seq': _seq});
    final me = _me;
    if (me != null) await _store.write(_kMe, me.toJson());
    await _writeList(_kDiaries, _myDiaries.map((e) => e.toJson()).toList());
    await _writeList(_kLetters, _letters.map((e) => e.toJson()).toList());
    await _writeList(_kConnections, _connections.map((e) => e.toJson()).toList());
    await _writeList(_kPages, _pages.map((e) => e.toJson()).toList());
    await _store.write(_kSafety, {
      'blocked': _blocked.toList(),
      'reports': _reports.map((e) => e.toJson()).toList(),
    });
    await _saveIntro();
  }

  static List<Map<String, Object?>> _items(Map<String, Object?>? m) =>
      ((m?['items'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();

  Future<List<Map<String, Object?>>> _readList(String base) async {
    final head = await _store.read(base);
    if (head == null) return const [];
    if (head.containsKey('items')) return _items(head); // single-record layout
    final chunks = (head['chunks'] as int?) ?? 0;
    return [
      for (var i = 0; i < chunks; i++) ..._items(await _store.read('$base.$i')),
    ];
  }

  Future<void> _writeList(String base, List<Map<String, Object?>> items) async {
    final chunks = <List<Map<String, Object?>>>[];
    var current = <Map<String, Object?>>[];
    var size = 0;
    for (final item in items) {
      final length = jsonEncode(item).length + 1;
      if (current.isNotEmpty && size + length > _chunkBudget) {
        chunks.add(current);
        current = [];
        size = 0;
      }
      current.add(item);
      size += length;
    }
    if (current.isNotEmpty) chunks.add(current);
    final previous = ((await _store.read(base))?['chunks'] as int?) ?? 0;
    for (var i = 0; i < chunks.length; i++) {
      await _store.write('$base.$i', {'items': chunks[i]});
    }
    await _store.write(base, {'chunks': chunks.length});
    for (var i = chunks.length; i < previous; i++) {
      await _store.remove('$base.$i');
    }
  }

  Future<void> _saveIntro() => _store.write(_kIntro, {
        'day': _introDay,
        // Copies: MemoryLocalStore keeps a shallow copy, so passing the live
        // collections would let later in-place edits leak into the store.
        'ids': [..._introIds],
        'last': {..._lastIntroduced},
      });

  Future<void> _commit() async {
    await _save();
    notifyListeners();
  }

  String _id(String prefix) => '$prefix-${_now.microsecondsSinceEpoch}-${_seq++}';

  Profile _requireMe() {
    final me = _me;
    if (me == null) throw const TsuzuriException('はじめにプロフィールを作成してください。');
    return me;
  }

  // ---------------------------------------------------------------- profile

  @override
  Future<void> createProfile(Profile profile, {required String firstDiary}) async {
    _validateProfile(profile);
    final body = firstDiary.trim();
    if (body.isEmpty) throw const TsuzuriException('最初の日記を一行だけ書いてください。');
    if (body.runes.length > Limits.diaryMax) {
      throw const TsuzuriException('日記は${Limits.diaryMax}文字までです。');
    }
    final me = Profile(
      id: meId,
      penName: profile.penName.trim(),
      ageBand: profile.ageBand,
      prefecture: profile.prefecture,
      bio: profile.bio.trim(),
      gender: profile.gender,
      seeking: profile.seeking,
      photoSeed: 0,
    );
    _me = me;
    final diary = DiaryEntry(
      id: _id('diary'),
      authorId: meId,
      body: body,
      scope: DiaryScope.intro,
      createdAt: _now,
    );
    _myDiaries.add(diary);
    _seedWelcomeLetter(me, diary);
    await _commit();
  }

  void _validateProfile(Profile p) {
    final name = p.penName.trim();
    if (name.isEmpty) throw const TsuzuriException('ペンネームを入れてください。');
    if (name.runes.length > Limits.penNameMax) {
      throw const TsuzuriException('ペンネームは${Limits.penNameMax}文字までです。');
    }
    if (containsContactInfo(name) || containsContactInfo(p.bio)) {
      throw const TsuzuriException('プロフィールに連絡先やSNSのIDは書けません。');
    }
    if (p.seeking.isEmpty) throw const TsuzuriException('出会いたい相手を1つ以上選んでください。');
  }

  /// A demo writer who is mutually compatible sends the first letter, so the
  /// "届いた感想" flow can be tried immediately.
  void _seedWelcomeLetter(Profile me, DiaryEntry diary) {
    final writer = seedWriters.map((w) => w.profile).where((p) => mutuallyCompatible(me, p)).firstOrNull;
    if (writer == null) return;
    final quote = splitSentences(diary.body).first;
    _letters.add(Letter(
      id: _id('letter'),
      fromId: writer.id,
      toId: meId,
      diaryId: diary.id,
      quote: quote,
      body: '「$quote」という一文が、今日の自分にも少し重なりました。'
          'よかったら、もう少しお話を聞かせてください。',
      status: LetterStatus.pending,
      createdAt: _now,
    ));
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    final me = _requireMe();
    _validateProfile(profile);
    _me = me.copyWith(
      penName: profile.penName.trim(),
      ageBand: profile.ageBand,
      prefecture: profile.prefecture,
      bio: profile.bio.trim(),
      gender: profile.gender,
      seeking: profile.seeking,
    );
    // Preferences changed: today's introductions are recomputed.
    _introDay = null;
    await _commit();
  }

  @override
  Future<void> setPaused(bool paused) async {
    _me = _requireMe().copyWith(paused: paused);
    await _commit();
  }

  @override
  Profile? profile(String userId) => userId == meId ? _me : _writers[userId]?.profile;

  // ---------------------------------------------------------------- diaries

  DateTime _seedDate(int daysAgo) => _now.subtract(Duration(days: daysAgo, hours: 3));

  List<DiaryEntry> _seedDiaries(String authorId) {
    final w = _writers[authorId];
    if (w == null) return const [];
    return [
      for (var i = 0; i < w.diaries.length; i++)
        DiaryEntry(
          id: '$authorId-d$i',
          authorId: authorId,
          body: w.diaries[i].$2,
          prompt: w.diaries[i].$3,
          scope: DiaryScope.intro,
          createdAt: _seedDate(w.diaries[i].$1),
        ),
    ];
  }

  @override
  DiaryEntry? diary(String diaryId) {
    for (final d in _myDiaries) {
      if (d.id == diaryId) return d;
    }
    final authorId = diaryId.contains('-d') ? diaryId.substring(0, diaryId.lastIndexOf('-d')) : '';
    for (final d in _seedDiaries(authorId)) {
      if (d.id == diaryId) return d;
    }
    return null;
  }

  @override
  List<DiaryEntry> readableDiaries(String authorId) {
    if (authorId == meId) return myDiaries();
    if (_blocked.contains(authorId)) return const [];
    final connected = relationWith(authorId).kind == RelationKind.connected;
    final list = _seedDiaries(authorId)
        .where((d) => d.scope == DiaryScope.intro || (connected && d.scope == DiaryScope.connections))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  List<DiaryEntry> myDiaries() => [..._myDiaries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<DiaryEntry> writeDiary(String body, DiaryScope scope, {String? prompt}) async {
    _requireMe();
    final text = body.trim();
    if (text.isEmpty) throw const TsuzuriException('一行だけでも書いてみてください。');
    if (text.runes.length > Limits.diaryMax) {
      throw const TsuzuriException('日記は${Limits.diaryMax}文字までです。');
    }
    final entry = DiaryEntry(
      id: _id('diary'),
      authorId: meId,
      body: text,
      scope: scope,
      prompt: prompt,
      createdAt: _now,
    );
    _myDiaries.add(entry);
    await _commit();
    return entry;
  }

  // ---------------------------------------------------------- introductions

  Set<String> _excludedFromIntro() {
    final ids = <String>{..._blocked};
    for (final c in _connections) {
      ids.add(c.partnerOf(meId));
    }
    for (final l in _letters) {
      ids.add(l.fromId == meId ? l.toId : l.fromId);
    }
    return ids;
  }

  @override
  List<Profile> todaysIntroductions() {
    final me = _me;
    if (me == null || me.paused) return const [];
    final day = introDayKey(_now);
    if (_introDay != day) {
      _introIds = pickIntroductions(
        me: me,
        others: _writers.values.map((w) => w.profile),
        dayKey: day,
        excluded: _excludedFromIntro(),
        lastIntroduced: _lastIntroduced,
        hasRecentIntroDiary: (id) => _seedDiaries(id).any(
            (d) => d.scope == DiaryScope.intro && _now.difference(d.createdAt) <= Limits.activeWriterWindow),
        atConnectionLimit: (_) => false,
      );
      _introDay = day;
      for (final id in _introIds) {
        _lastIntroduced[id] = day;
      }
      unawaited(_saveIntro().catchError((Object _) {}));
    }
    return _introIds
        .where((id) => !_blocked.contains(id) && _writers.containsKey(id))
        .map((id) => _writers[id]!.profile)
        .toList();
  }

  // ---------------------------------------------------------------- letters

  /// Letters past their lifetime no longer count, even before tickDemo closes them.
  int get _pendingOutgoing => _letters
      .where((l) =>
          l.fromId == meId &&
          l.status == LetterStatus.pending &&
          _now.difference(l.createdAt) < Limits.letterLifetime)
      .length;

  @override
  Future<Letter> sendLetter({required String diaryId, required String quote, required String body}) async {
    final me = _requireMe();
    final d = diary(diaryId);
    if (d == null || d.authorId == meId) throw const TsuzuriException('この日記は見つかりませんでした。');
    final author = profile(d.authorId);
    if (_blocked.contains(d.authorId) || author == null || !mutuallyCompatible(me, author)) {
      throw const TsuzuriException('この人には感想を送れません。');
    }
    if (relationWith(d.authorId).kind != RelationKind.none) {
      throw const TsuzuriException('この人とは、すでにやりとりがあります。');
    }
    if (_pendingOutgoing >= Limits.pendingLetters) {
      throw const TsuzuriException('返事を待っている感想が${Limits.pendingLetters}通あります。'
          'ひとつ落ち着いてから、また送れます。');
    }
    if (activeConnections().length >= Limits.activeConnections) {
      throw const TsuzuriException('いまは${Limits.activeConnections}人とつながっています。'
          '今のつながりを大切にする期間です。');
    }
    final problem = letterProblem(quote: quote, body: body, diaryBody: d.body);
    if (problem != null) throw TsuzuriException(problem);
    final letter = Letter(
      id: _id('letter'),
      fromId: meId,
      toId: d.authorId,
      diaryId: d.id,
      quote: quote,
      body: body.trim(),
      status: LetterStatus.pending,
      createdAt: _now,
    );
    _letters.add(letter);
    await _commit();
    return letter;
  }

  @override
  List<Letter> incomingLetters() => _letters
      .where((l) => l.toId == meId && l.status == LetterStatus.pending && !_blocked.contains(l.fromId))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Accepted letters become connections and are not listed here. Declined
  /// and expired letters look the same to the sender: quietly closed.
  @override
  List<Letter> outgoingLetters() => _letters
      .where((l) => l.fromId == meId && l.status != LetterStatus.accepted)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  RelationWithUser relationWith(String userId) {
    for (final c in _connections) {
      if (c.includes(userId) && c.includes(meId)) {
        return RelationWithUser(
          c.status == ConnectionStatus.active ? RelationKind.connected : RelationKind.closed,
          connection: c,
        );
      }
    }
    for (final l in _letters.reversed) {
      if (l.fromId == meId && l.toId == userId) {
        return RelationWithUser(
            l.status == LetterStatus.pending ? RelationKind.letterSent : RelationKind.closed,
            letter: l);
      }
      if (l.fromId == userId && l.toId == meId) {
        return RelationWithUser(
            l.status == LetterStatus.pending ? RelationKind.letterReceived : RelationKind.closed,
            letter: l);
      }
    }
    return const RelationWithUser(RelationKind.none);
  }

  int _letterIndex(String letterId) {
    final i = _letters.indexWhere((l) => l.id == letterId);
    if (i < 0) throw const TsuzuriException('この感想は見つかりませんでした。');
    return i;
  }

  @override
  Future<Connection> acceptLetter(String letterId) async {
    _requireMe();
    final i = _letterIndex(letterId);
    final l = _letters[i];
    if (l.toId != meId || l.status != LetterStatus.pending) {
      throw const TsuzuriException('この感想には、もう返事ができません。');
    }
    if (activeConnections().length >= Limits.activeConnections) {
      throw const TsuzuriException('つながりは同時に${Limits.activeConnections}人までです。'
          'どなたかとの関係を見直してから、また返事ができます。');
    }
    _letters[i] = l.withStatus(LetterStatus.accepted, _now);
    final c = _connect(l.fromId);
    await _commit();
    return c;
  }

  Connection _connect(String partnerId) {
    final c = Connection(
      id: _id('conn'),
      members: [partnerId, meId],
      createdAt: _now,
      status: ConnectionStatus.active,
    );
    _connections.add(c);
    final w = _writers[partnerId];
    if (w != null) {
      _pages.add(SharedPage(
        id: _id('page'),
        connectionId: c.id,
        authorId: partnerId,
        body: 'つながってくれて、ありがとうございます。${w.profile.penName}です。'
            '急がず、思い出したときに書いていきましょう。',
        createdAt: _now,
      ));
    }
    return c;
  }

  @override
  Future<void> declineLetter(String letterId) async {
    final i = _letterIndex(letterId);
    final l = _letters[i];
    if (l.toId != meId || l.status != LetterStatus.pending) return;
    _letters[i] = l.withStatus(LetterStatus.declined, _now);
    await _commit();
  }

  // ------------------------------------------------------------- connections

  @override
  List<Connection> activeConnections() => _connections
      .where((c) => c.status == ConnectionStatus.active && !_blocked.contains(c.partnerOf(meId)))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Connection? connection(String connectionId) {
    for (final c in _connections) {
      if (c.id == connectionId) return c;
    }
    return null;
  }

  Connection _activeConnection(String connectionId) {
    final c = connection(connectionId);
    if (c == null || c.status != ConnectionStatus.active) {
      throw const TsuzuriException('この関係は終わっています。');
    }
    return c;
  }

  void _replaceConnection(Connection c) {
    final i = _connections.indexWhere((x) => x.id == c.id);
    _connections[i] = c;
  }

  /// Pages are readable only while the connection is active.
  @override
  List<SharedPage> pages(String connectionId) {
    final c = connection(connectionId);
    if (c == null || c.status != ConnectionStatus.active) return const [];
    return _pages.where((p) => p.connectionId == connectionId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  String _checkPageText(String body) {
    final text = body.trim();
    if (text.isEmpty) throw const TsuzuriException('一行だけでも書いてみてください。');
    if (text.runes.length > Limits.pageMax) {
      throw const TsuzuriException('${Limits.pageMax}文字までです。');
    }
    return text;
  }

  @override
  Future<void> writePage(String connectionId, String body) async {
    final c = _activeConnection(connectionId);
    _pages.add(SharedPage(
      id: _id('page'),
      connectionId: c.id,
      authorId: meId,
      body: _checkPageText(body),
      createdAt: _now,
    ));
    await _commit();
  }

  @override
  Future<void> replyToPage(String connectionId, String pageId, String body) async {
    _activeConnection(connectionId);
    final i = _pages.indexWhere((p) => p.id == pageId && p.connectionId == connectionId);
    if (i < 0) throw const TsuzuriException('このページは見つかりませんでした。');
    if (_pages[i].replies.length >= _maxRepliesPerPage) {
      throw const TsuzuriException('このページには、もう返事を添えられません。新しいページに書いてみてください。');
    }
    _pages[i] = _pages[i].withReply(PageReply(authorId: meId, body: _checkPageText(body), createdAt: _now));
    await _commit();
  }

  // ------------------------------------------------------------------ photos

  @override
  Future<void> proposePhotoReveal(String connectionId) async {
    final c = _activeConnection(connectionId);
    if (!PhotoRules.canPropose(c)) throw const TsuzuriException('いまは提案できません。');
    _replaceConnection(c.copyWith(photoState: PhotoState.proposed, proposedBy: meId, proposedAt: _now));
    await _commit();
  }

  @override
  Future<void> cancelPhotoProposal(String connectionId) async {
    final c = _activeConnection(connectionId);
    if (!PhotoRules.canCancel(c, meId)) throw const TsuzuriException('この提案は取り消せません。');
    _replaceConnection(c.copyWith(photoState: PhotoState.hidden, clearProposal: true));
    await _commit();
  }

  @override
  Future<void> consentPhotoReveal(String connectionId) async {
    final c = _activeConnection(connectionId);
    if (!PhotoRules.canConsent(c, meId)) throw const TsuzuriException('いまは同意できません。');
    _replaceConnection(c.copyWith(photoState: PhotoState.revealed, revealedAt: _now));
    await _commit();
  }

  // ------------------------------------------------------------------ safety

  @override
  Future<void> endConnection(String connectionId) async {
    final c = connection(connectionId);
    if (c == null || c.status == ConnectionStatus.ended) return;
    _replaceConnection(c.copyWith(status: ConnectionStatus.ended, endedAt: _now));
    await _commit();
  }

  void _closeEverythingWith(String userId) {
    for (var i = 0; i < _connections.length; i++) {
      final c = _connections[i];
      if (c.includes(userId) && c.status == ConnectionStatus.active) {
        _connections[i] = c.copyWith(status: ConnectionStatus.ended, endedAt: _now);
      }
    }
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if ((l.fromId == userId || l.toId == userId) && l.status == LetterStatus.pending) {
        _letters[i] = l.withStatus(LetterStatus.closed, _now);
      }
    }
  }

  @override
  Future<void> block(String userId) async {
    if (userId == meId) return;
    _blocked.add(userId);
    _closeEverythingWith(userId);
    await _commit();
  }

  @override
  Future<void> report({
    required String targetId,
    required String context,
    required ReportCategory category,
    String? note,
  }) async {
    final me = _requireMe();
    final text = (note ?? '').trim();
    if (text.runes.length > 1000) throw const TsuzuriException('説明は1000文字までです。');
    _reports.add(Report(
      id: _id('report'),
      reporterId: me.id,
      targetId: targetId,
      context: context,
      category: category,
      note: text,
      createdAt: _now,
    ));
    // Reporting always blocks, so the reporter is never exposed again.
    _blocked.add(targetId);
    _closeEverythingWith(targetId);
    await _commit();
  }

  @override
  Set<String> blockedUsers() => Set.unmodifiable(_blocked);

  @override
  Future<void> unblock(String userId) async {
    if (_blocked.remove(userId)) await _commit();
  }

  @override
  Future<void> deleteAllData() async {
    for (final base in _listKeys) {
      final chunks = ((await _store.read(base))?['chunks'] as int?) ?? 0;
      for (var i = 0; i < chunks; i++) {
        await _store.remove('$base.$i');
      }
      await _store.remove(base);
    }
    for (final k in _plainKeys) {
      await _store.remove(k);
    }
    _me = null;
    _seq = 0;
    _myDiaries.clear();
    _letters.clear();
    _connections.clear();
    _pages.clear();
    _blocked.clear();
    _reports.clear();
    _introDay = null;
    _introIds = [];
    _lastIntroduced.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------- demo world

  /// Advances the fictional writers. Returns true when something changed.
  Future<bool> tickDemo() async {
    if (_me == null) return false;
    final now = _now;
    var changed = false;

    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (l.status != LetterStatus.pending) continue;
      final age = now.difference(l.createdAt);
      if (age >= Limits.letterLifetime) {
        _letters[i] = l.withStatus(LetterStatus.closed, now);
        changed = true;
        continue;
      }
      final writer = _writers[l.toId];
      if (l.fromId == meId &&
          writer != null &&
          !_blocked.contains(l.toId) &&
          age >= demoDelay &&
          activeConnections().length < Limits.activeConnections) {
        _letters[i] = l.withStatus(LetterStatus.accepted, now);
        _connect(l.toId);
        changed = true;
      }
    }

    for (final c in activeConnections()) {
      final partner = c.partnerOf(meId);
      final writer = _writers[partner];
      if (writer == null) continue;

      if (c.photoState == PhotoState.proposed &&
          c.proposedBy == meId &&
          c.proposedAt != null &&
          now.difference(c.proposedAt!) >= demoDelay) {
        _replaceConnection(c.copyWith(photoState: PhotoState.revealed, revealedAt: now));
        changed = true;
      }

      final list = pages(c.id);
      if (list.isEmpty) continue;
      final last = list.last;
      final answered = last.replies.any((r) => r.authorId == partner);
      if (last.authorId == meId && !answered && now.difference(last.createdAt) >= demoDelay) {
        final used = list.fold<int>(0, (n, p) => n + p.replies.where((r) => r.authorId == partner).length);
        final text = writer.pageReplies[used % writer.pageReplies.length];
        final i = _pages.indexWhere((p) => p.id == last.id);
        _pages[i] = last.withReply(PageReply(authorId: partner, body: text, createdAt: now));
        changed = true;
      }
    }

    if (changed) await _commit();
    return changed;
  }
}
