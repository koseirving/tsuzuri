# つづり service
Product ID: `tsuzuri`. Repository: `services/tsuzuri`. Bundle ID (proposed): `com.koseirving.tsuzuri`.
Diary-first friendship and dating app for adults, same-gender and different-gender. Design: `docs/DESIGN.md`.
Demand, retention and pricing are unvalidated hypotheses. "つづり" is a working title.
Keep the calm-by-design rules: no read receipts, no public like counts or rankings, 3 introductions/day,
3 pending letters, 3 active connections, no streaks, leave/block/report without reasons, no AI personality scores.
Photos are revealed only simultaneously after both people consent; never show them before.
UI depends only on `TsuzuriBackend`; `DemoBackend` is on-device with fictional writers. No Firebase, login,
analytics SDK, push, purchases or ads until an approved task needs them; use separate Firebase projects.
Public release additionally needs age verification, a legal check of Japan's online dating-service
notification duties, a moderation process and a privacy policy. Do not claim any of these are done.
Run `flutter analyze` and `flutter test` here after `ops.py bootstrap-mobile tsuzuri --org com.koseirving`.
