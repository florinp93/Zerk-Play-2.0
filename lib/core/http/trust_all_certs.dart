import 'dart:io';

void trustAllCertificates() => HttpOverrides.global = _TrustAllCerts();

final class _TrustAllCerts extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..badCertificateCallback = (_, _, _) => true;
}
