package ai.sarvam.core.util

public interface Clock {
    public fun currentTimeMillis(): Long
}

public object SystemClock : Clock {
    override fun currentTimeMillis(): Long = System.currentTimeMillis()
}
