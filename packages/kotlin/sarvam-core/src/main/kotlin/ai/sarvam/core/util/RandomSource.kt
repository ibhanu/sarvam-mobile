package ai.sarvam.core.util

public interface RandomSource {
    public fun nextLong(until: Long): Long
}

public object DefaultRandomSource : RandomSource {
    override fun nextLong(until: Long): Long {
        if (until <= 1L) return 0L
        return java.util.concurrent.ThreadLocalRandom.current().nextLong(until)
    }
}
