import 'package:arena_os/app/bootstrap.dart';

/// Entrypoint for the **development** flavour.
///
/// One entrypoint per Supabase project (D34). The environment name is not
/// hardcoded here: it arrives with the URL and anon key via
/// `--dart-define-from-file=env/development.json`, so an entrypoint can never
/// disagree with the credentials it was built with.
///
///   flutter run --flavor development -t lib/main_development.dart \
///     --dart-define-from-file=env/development.json
void main() => bootstrap();
