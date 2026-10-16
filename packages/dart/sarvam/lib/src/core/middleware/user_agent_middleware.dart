import 'package:sarvam/src/generated/sarvam_spec_generated.dart';
import '../transport.dart';
import 'middleware.dart';

/// Middleware injecting standardized User-Agent and SDK version headers.
class UserAgentMiddleware implements Middleware {
  final String customUserAgent;

  UserAgentMiddleware({String? userAgent})
      : customUserAgent = userAgent ??
            'sarvam-dart/${SarvamSpecMetadata.sdkVersion} (spec/${SarvamSpecMetadata.specVersion}; flutter; dart/3.11)';

  @override
  Future<HttpResponse> handle(HttpRequest request, HttpHandler next) {
    if (!request.headers.containsKey('User-Agent') &&
        !request.headers.containsKey('user-agent')) {
      request.headers['User-Agent'] = customUserAgent;
    }
    request.headers['X-Sarvam-SDK-Version'] = SarvamSpecMetadata.sdkVersion;

    return next(request);
  }
}
