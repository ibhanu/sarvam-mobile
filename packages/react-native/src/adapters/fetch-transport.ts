import {
  HttpTransport,
  HttpRequest,
  HttpResponse,
  FetchHttpTransport,
} from '@sarvam-mobile/core';

export class ReactNativeFetchTransport implements HttpTransport {
  private readonly underlyingTransport: FetchHttpTransport;

  constructor(options?: { defaultTimeoutMs?: number }) {
    this.underlyingTransport = new FetchHttpTransport(options);
  }

  async execute(request: HttpRequest): Promise<HttpResponse> {
    // If request.body contains a FileInput or FormData, ReactNativeFormDataAdapter ensures native format
    return this.underlyingTransport.execute(request);
  }
}
