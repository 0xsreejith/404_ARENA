import 'package:arena_os/app/bootstrap.dart';

/// Entrypoint for the **production** flavour.
///
/// One entrypoint per Supabase project (D34). The environment name is not
/// hardcoded here: it arrives with the URL and anon key via
/// `--dart-define-from-file=env/production.json`, so an entrypoint can never
/// disagree with the credentials it was built with.
///
///   flutter run --flavor production -t lib/main_production.dart \
///     --dart-define-from-file=env/production.json
void main() => bootstrap();
