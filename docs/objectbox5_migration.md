# ObjectBox 5 Migration Notes

Status: blocked by `flutter_map_tile_caching` dependency (FMTC uses ObjectBox 4.x)

Why blocked
------------
- `flutter_map_tile_caching` (used for tile caching) depends on `objectbox_flutter_libs` 4.x.
- ObjectBox 5 and its codegen require `objectbox_flutter_libs` 5.x and `objectbox_generator` 5.x.
- The dependency solver cannot select both; forcing an override is risky because FMTC uses ObjectBox internals.

Options considered
------------------
- Option A: Force-upgrade with dependency_overrides — fast but risky; may break FMTC at runtime.
- Option B: Replace or patch FMTC to an OBX5-compatible backend — more work, safer.
- Option C: Wait for FMTC upstream to release OBX5-compatible versions and prepare code in advance (chosen path).

Chosen path
-----------
We select Option C: keep ObjectBox 4.x for now, document the blocker, and prepare the codebase for a future upgrade.

Migration checklist (preparation)
--------------------------------
- Keep `objectbox: ^4.3.1`, `objectbox_flutter_libs: ^4.3.1`, `objectbox_generator: ^4.3.1`, `flutter_map_tile_caching: ^10.0.0` in `pubspec.yaml`.
- Ensure all entities use named constructors instead of static factories where possible.
- Add `TODO(OBX5)` comments near any queries or `watch()` calls that may change semantics.
- Add a test helper to skip ObjectBox-native tests when native libs are missing.
- Create `prep/objectbox5-ready` branch and commit these notes + TODOs.

Commands to run when FMTC supports OBX5
--------------------------------------
```bash
flutter pub upgrade objectbox objectbox_flutter_libs objectbox_generator
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Tracking
--------
- FMTC repository: https://github.com/ISNIT0/flutter_map_tile_caching (watch for OBX5 support or issues)

Contact
-------
If you want me to attempt an override-based migration (Option A) or replace FMTC (Option B), reply with which path and I'll implement and test it on a feature branch.
