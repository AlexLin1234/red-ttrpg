/**
 * The dice surface used by the resolver.
 *
 * Kept behind an interface so every rule can be tested with a scripted sequence
 * instead of a seeded generator.
 */
export interface RandomSource {
  randint(low: number, high: number): number
}

export interface Roll {
  readonly rolls: readonly number[]
  readonly total: number
}

/** A RED d10 check: 10s explode upward once, 1s fumble downward once. */
export function rollCheck(rng: RandomSource): Roll {
  const first = rng.randint(1, 10)
  if (first === 10) {
    const extra = rng.randint(1, 10)
    return { rolls: [first, extra], total: first + extra }
  }
  if (first === 1) {
    const extra = rng.randint(1, 10)
    return { rolls: [first, extra], total: first - extra }
  }
  return { rolls: [first], total: first }
}

export function damageRoll(dice: number, rng: RandomSource): { rolls: number[]; total: number } {
  const rolls: number[] = []
  for (let index = 0; index < dice; index += 1) rolls.push(rng.randint(1, 6))
  return { rolls, total: rolls.reduce((sum, value) => sum + value, 0) }
}

/**
 * A small deterministic generator. Seeded so a campaign can replay the same
 * fight, and so tests that want realistic rolls do not depend on Math.random.
 */
export class SeededRandom implements RandomSource {
  private state: number

  constructor(seed: number) {
    // Force a non-zero 32-bit state; mulberry32 stalls on zero.
    this.state = (seed >>> 0) || 0x9e3779b9
  }

  private next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0
    let t = this.state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }

  randint(low: number, high: number): number {
    return low + Math.floor(this.next() * (high - low + 1))
  }
}
