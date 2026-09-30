import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'theme.dart';

/// Runs [action]; shows a user-facing message on [TsuzuriException].
/// Returns null on failure.
Future<T?> runGuarded<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on TsuzuriException catch (e) {
    if (context.mounted) showNote(context, e.message);
    return null;
  } catch (_) {
    if (context.mounted) showNote(context, '保存できませんでした。もう一度お試しください。');
    return null;
  }
}

void showNote(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// In-app confirmation. Returns true only on explicit agreement.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめておく')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFF9A4A3C)) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Row(children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      );
}

class QuoteBlock extends StatelessWidget {
  const QuoteBlock(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: const BoxDecoration(
          color: TsuzuriColors.highlight,
          border: Border(left: BorderSide(color: TsuzuriColors.osmanthus, width: 3)),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      );
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.icon = Icons.spa_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 16, color: TsuzuriColors.sub),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, this.text = 'デモ版：登場する書き手はすべて架空の人物です。データはこの端末の中だけに保存されます。'});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: TsuzuriColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Hint(text, icon: Icons.info_outline),
      );
}

String profileLine(Profile p) => '${p.ageBand}・${p.prefecture}';

String dateLabel(DateTime d) {
  final t = d.toLocal();
  return '${t.month}月${t.day}日';
}

const _photoPalette = <List<Color>>[
  [Color(0xFF8FA6B8), Color(0xFF3E5A73)],
  [Color(0xFFE8B77A), Color(0xFFB0643A)],
  [Color(0xFF9BB39A), Color(0xFF4F6E55)],
  [Color(0xFFB9A6C9), Color(0xFF6A5680)],
  [Color(0xFFD8A7A0), Color(0xFF94574F)],
  [Color(0xFFA7C4C2), Color(0xFF4A7775)],
  [Color(0xFFE2C98F), Color(0xFF9A7A34)],
  [Color(0xFFB7B1A5), Color(0xFF625C52)],
];

/// Stands in for a real photo in the demo. Hidden until both people agree.
class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.profile, required this.revealed, this.size = 96});
  final Profile profile;
  final bool revealed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = _photoPalette[profile.photoSeed % _photoPalette.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 8),
      child: SizedBox.square(
        dimension: size,
        child: revealed
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    profile.penName.characters.first,
                    style: TextStyle(fontSize: size * 0.4, color: Colors.white, fontWeight: FontWeight.w300),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: const BoxDecoration(color: TsuzuriColors.line),
                child: Icon(Icons.lock_outline, color: TsuzuriColors.sub, size: size * 0.3),
              ),
      ),
    );
  }
}
