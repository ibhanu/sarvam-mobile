package ai.sarvam.resources

import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.SystemClock
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive

public class JobPoller(
    private val clock: Clock = SystemClock,
    private val sleeper: suspend (Long) -> Unit = { delay(it) }
) {
    public suspend fun <TStatus> waitUntilComplete(
        jobId: String,
        pollIntervalMs: Long = 5000L,
        timeoutMs: Long = 600_000L,
        fetchStatus: suspend (String) -> TStatus,
        isTerminal: (TStatus) -> Boolean,
        isFailed: ((TStatus) -> Boolean)? = null
    ): TStatus {
        val startTime = clock.currentTimeMillis()
        while (true) {
            currentCoroutineContext().ensureActive()
            val status = fetchStatus(jobId)
            if (isFailed != null && isFailed(status)) {
                throw SarvamException.ServerException(
                    statusCode = 500,
                    code = "job_failed",
                    requestId = null,
                    message = "Job $jobId failed with terminal status: $status"
                )
            }
            if (isTerminal(status)) {
                return status
            }
            val elapsed = clock.currentTimeMillis() - startTime
            if (elapsed + pollIntervalMs > timeoutMs) {
                throw SarvamException.TimeoutException(
                    phase = ai.sarvam.core.error.TimeoutPhase.TOTAL,
                    message = "Job $jobId timed out after ${timeoutMs}ms"
                )
            }
            sleeper(pollIntervalMs)
        }
    }
}
