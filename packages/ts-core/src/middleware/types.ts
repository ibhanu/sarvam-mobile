import { HttpRequest, HttpResponse } from '../transport/http.js';

export type NextHandler = (request: HttpRequest) => Promise<HttpResponse>;

export interface Middleware {
  (request: HttpRequest, next: NextHandler): Promise<HttpResponse>;
}

export function composeMiddlewares(
  middlewares: Middleware[],
  finalHandler: NextHandler
): NextHandler {
  return middlewares.reduceRight<NextHandler>(
    (next, mw) => (req) => mw(req, next),
    finalHandler
  );
}
