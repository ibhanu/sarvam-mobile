import 'dart:async';

import '../transport.dart';

/// Handler function representing the next step in the HTTP middleware pipeline.
typedef HttpHandler = Future<HttpResponse> Function(HttpRequest request);

/// Interceptor executing cross-cutting concerns around HTTP request execution.
abstract interface class Middleware {
  /// Processes an [HttpRequest] and invokes [next] to continue the pipeline.
  Future<HttpResponse> handle(HttpRequest request, HttpHandler next);
}

/// Builds an executable pipeline by chaining [middlewares] around [transport].
HttpHandler buildPipeline(
    HttpTransport transport, List<Middleware> middlewares) {
  HttpHandler handler = transport.send;
  for (var i = middlewares.length - 1; i >= 0; i--) {
    final middleware = middlewares[i];
    final currentHandler = handler;
    handler = (req) => middleware.handle(req, currentHandler);
  }
  return handler;
}
