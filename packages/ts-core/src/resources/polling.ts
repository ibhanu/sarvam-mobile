import { Clock, defaultClock } from '../utils/timing.js';
import { TimeoutError, ServerError } from '../errors.js';

export interface PollUntilCompleteOptions<T> {
  /** The polling function invoked on each attempt. Receives an AbortSignal. */
  poll: (signal?: AbortSignal) => Promise<T>;

  /** Predicate returning true when the job has succeeded or reached a terminal completed state. */
  isComplete: (result: T) => boolean;

  /** Optional predicate returning true when the job has failed. */
  isFailed?: (result: T) => boolean;

  /** Optional function to extract an error message from a failed result. */
  getFailureMessage?: (result: T) => string;

  /** Initial polling interval in milliseconds. Defaults to 1000. */
  initialIntervalMs?: number;

  /** Maximum polling interval in milliseconds. Defaults to 10000. */
  maxIntervalMs?: number;

  /** Exponential backoff multiplier. Defaults to 1.5. */
  backoffMultiplier?: number;

  /** Maximum overall duration in milliseconds before throwing TimeoutError. */
  timeoutMs?: number;

  /** Optional AbortSignal to cancel polling. */
  signal?: AbortSignal;

  /** Optional Clock primitive for testing time progression without real delays. */
  clock?: Clock;
}

export interface WaitUntilCompleteOptions {
  initialIntervalMs?: number;
  maxIntervalMs?: number;
  backoffMultiplier?: number;
  timeoutMs?: number;
  signal?: AbortSignal;
  clock?: Clock;
}

export function isStandardJobComplete(res: unknown): boolean {
  if (!res || typeof res !== 'object') return false;
  const r = res as Record<string, unknown>;
  const statusStr = String(
    r['job_state'] ?? r['status'] ?? r['state'] ?? r['export_status'] ?? ''
  ).toUpperCase();
  return statusStr === 'COMPLETED' || statusStr === 'SUCCESS' || statusStr === 'DONE';
}

export function isStandardJobFailed(res: unknown): boolean {
  if (!res || typeof res !== 'object') return false;
  const r = res as Record<string, unknown>;
  const statusStr = String(
    r['job_state'] ?? r['status'] ?? r['state'] ?? r['export_status'] ?? ''
  ).toUpperCase();
  return statusStr === 'FAILED' || statusStr === 'FAILURE' || statusStr === 'ERROR';
}

export function getStandardJobFailureMessage(res: unknown): string {
  if (!res || typeof res !== 'object') return 'Job failed';
  const r = res as Record<string, unknown>;
  return (
    (r['error_message'] as string) ??
    (r['error'] as string) ??
    (r['message'] as string) ??
    `Job failed with state: ${r['job_state'] ?? r['status'] ?? r['state'] ?? 'FAILED'}`
  );
}

async function cancellableSleep(ms: number, clock: Clock, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) {
    const err = new Error('Operation aborted');
    err.name = 'AbortError';
    throw err;
  }
  if (!signal) {
    return clock.sleep(ms);
  }

  return new Promise<void>((resolve, reject) => {
    let finished = false;
    const onAbort = () => {
      if (!finished) {
        finished = true;
        const err = new Error('Operation aborted');
        err.name = 'AbortError';
        reject(err);
      }
    };

    signal.addEventListener('abort', onAbort, { once: true });

    clock.sleep(ms).then(
      () => {
        if (!finished) {
          finished = true;
          signal.removeEventListener('abort', onAbort);
          resolve();
        }
      },
      (err) => {
        if (!finished) {
          finished = true;
          signal.removeEventListener('abort', onAbort);
          reject(err);
        }
      }
    );
  });
}

/**
 * Generic cancellable polling helper respecting AbortSignal, exponential backoff,
 * and injectable clock/sleep for deterministic testing.
 */
export async function pollUntilComplete<T>(options: PollUntilCompleteOptions<T>): Promise<T> {
  const clock = options.clock ?? defaultClock;
  const initialInterval = options.initialIntervalMs ?? 1000;
  const maxInterval = options.maxIntervalMs ?? 10000;
  const multiplier = options.backoffMultiplier ?? 1.5;
  const startTime = clock.now();
  let currentInterval = initialInterval;

  while (true) {
    if (options.signal?.aborted) {
      const err = new Error('Operation aborted');
      err.name = 'AbortError';
      throw err;
    }

    if (options.timeoutMs !== undefined && clock.now() - startTime >= options.timeoutMs) {
      throw new TimeoutError(`Job polling timed out after ${options.timeoutMs}ms`, {
        phase: 'total',
      });
    }

    const result = await options.poll(options.signal);

    if (options.isComplete(result)) {
      return result;
    }

    if (options.isFailed?.(result)) {
      const message = options.getFailureMessage?.(result) ?? getStandardJobFailureMessage(result);
      throw new ServerError(message, { statusCode: 500 });
    }

    let delay = currentInterval;
    if (options.timeoutMs !== undefined) {
      const elapsed = clock.now() - startTime;
      const remaining = options.timeoutMs - elapsed;
      if (remaining <= 0) {
        throw new TimeoutError(`Job polling timed out after ${options.timeoutMs}ms`, {
          phase: 'total',
        });
      }
      delay = Math.min(delay, remaining);
    }

    await cancellableSleep(delay, clock, options.signal);
    currentInterval = Math.min(currentInterval * multiplier, maxInterval);
  }
}
