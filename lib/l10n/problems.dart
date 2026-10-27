import '../data/seerr_api.dart';
import '../data/tmdb_api.dart';
import 'app_localizations.dart';

extension L10nProblems on L10n {
  String seerrProblem(SeerrProblem p) => switch (p.kind) {
        SeerrProblemKind.notConfigured => seerrNotConfigured,
        SeerrProblemKind.notSeerr => seerrNotSeerr('${p.url}', p.status ?? 0),
        SeerrProblemKind.unreachable => seerrUnreachable('${p.url}'),
        SeerrProblemKind.keyRejected => seerrKeyRejected,
        SeerrProblemKind.keyCheckFailed => seerrKeyCheckFailed(p.status ?? 0),
      };

  String tmdbProblem(TmdbProblem p) => switch (p.kind) {
        TmdbProblemKind.invalidKey => tmdbInvalidKey,
        TmdbProblemKind.error => tmdbError(p.status ?? 0, p.message ?? ''),
        TmdbProblemKind.unreachable => tmdbUnreachable,
      };
}
