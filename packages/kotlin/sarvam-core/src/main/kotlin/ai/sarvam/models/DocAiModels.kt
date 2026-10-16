package ai.sarvam.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
public data class DocAIStartJobResponse(
    @SerialName("job_id")
    public val jobId: String,
    public val status: String,
    @SerialName("run_id")
    public val runId: String? = null
)

@Serializable
public data class DocAIPresignUploadRequest(
    @SerialName("content_type")
    public val contentType: String? = null
)

@Serializable
public data class DocAIPresignUploadResponse(
    @SerialName("upload_id")
    public val uploadId: String,
    public val method: String? = null,
    public val url: String,
    public val headers: Map<String, String> = emptyMap(),
    @SerialName("expires_at")
    public val expiresAt: String? = null
)

@Serializable
public data class DocAIJobStatusResponse(
    @SerialName("job_id")
    public val jobId: String,
    public val status: String,
    public val pipeline: String? = null,
    public val usage: DocAIUsage? = null,
    @SerialName("created_at")
    public val createdAt: String? = null,
    @SerialName("updated_at")
    public val updatedAt: String? = null
) {
    public val isTerminal: Boolean
        get() = status.lowercase() in TERMINAL_STATUSES

    public val isFailed: Boolean
        get() = status.lowercase() in FAILED_STATUSES

    public val isSuccessful: Boolean
        get() = status.lowercase() in SUCCESSFUL_STATUSES

    public companion object {
        public val TERMINAL_STATUSES: Set<String> = setOf("completed", "partially_completed", "failed", "rejected")
        public val FAILED_STATUSES: Set<String> = setOf("failed", "rejected")
        public val SUCCESSFUL_STATUSES: Set<String> = setOf("completed", "partially_completed")
    }
}

@Serializable
public data class DocAIUsage(
    public val pages: Int? = null,
    public val characters: Int? = null
)

@Serializable
public data class DocAIDownloadURLResponse(
    public val method: String? = null,
    public val url: String,
    public val headers: Map<String, String> = emptyMap(),
    @SerialName("expires_at")
    public val expiresAt: String? = null
)
