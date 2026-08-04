import 'package:arena_os/app/bootstrap.dart';

/// Entrypoint for the **staging** flavour.
///
/// One entrypoint per Supabase project (D34). The environment name is not
/// hardcoded here: it arrives with the URL and anon key via
/// `--dart-define-from-file=env/staging.json`, so an entrypoint can never
/// disagree with the credentials it was built with.
///
///   flutter run --flavor staging -t lib/main_staging.dart \
///     --dart-define-from-file=env/staging.json
void main() => bootstrap();
