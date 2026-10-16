/**
 * Injectable time and random primitives for testability.
 */

export interface Clock {
  now(): number;
  sleep(ms: number): Promise<void>;
}

export const defaultClock: Clock = {
  now: () => Date.now(),
  sleep: (ms: number) => new Promise((resolve) => setTimeout(resolve, ms)),
};

export interface Random {
  random(): number;
}

export const defaultRandom: Random = {
  random: () => Math.random(),
};
