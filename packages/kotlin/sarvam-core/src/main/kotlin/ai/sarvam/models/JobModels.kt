package ai.sarvam.models

import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.SttModel
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// --- STT Bulk Jobs ---

@Serializable
public data class SpeechToTextJobInitRequest(
    @SerialName("job_parameters")
    public val jobParameters: SpeechToTextJobParameters? = null,
    public val callback: BulkJobCallback? = null
)

@Serializable
public data class SpeechToTextJobParameters(
    public val model: SttModel? = null,
    @SerialName("language_code")
    public val languageCode: LanguageCode? = null,
    @SerialName("with_diarization")
    public val withDiarization: Boolean? = null,
    @SerialName("with_timestamps")
    public val withTimestamps: Boolean? = null
)

@Serializable
public data class BulkJobCallback(
    public val url: String,
    public val headers: Map<String, String>? = null
)

@Serializable
public data class BulkJobInitResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("storage_container_type")
    public val storageContainerType: String? = null,
    @SerialName("job_state")
    public val jobState: String? = null
)

@Serializable
public data class FilesRequest(
    @SerialName("job_id")
    public val jobId: String,
    public val files: List<String>
)

@Serializable
public data class FilesUploadResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("job_state")
    public val jobState: String? = null,
    @SerialName("upload_urls")
    public val uploadUrls: Map<String, FileSignedURLDetails> = emptyMap(),
    @SerialName("storage_container_type")
    public val storageContainerType: String? = null
)

@Serializable
public data class FilesDownloadResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("job_state")
    public val jobState: String? = null,
    @SerialName("download_urls")
    public val downloadUrls: Map<String, FileSignedURLDetails> = emptyMap(),
    @SerialName("storage_container_type")
    public val storageContainerType: String? = null
)

@Serializable
public data class FileSignedURLDetails(
    @SerialName("file_url")
    public val fileUrl: String? = null,
    @SerialName("error_message")
    public val errorMessage: String? = null
)

@Serializable
public data class JobStatusResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("job_state")
    public val jobState: String? = null,
    @SerialName("created_at")
    public val createdAt: String? = null,
    @SerialName("updated_at")
    public val updatedAt: String? = null,
    @SerialName("total_files")
    public val totalFiles: Int = 0,
    @SerialName("successful_files_count")
    public val successfulFilesCount: Int = 0,
    @SerialName("failed_files_count")
    public val failedFilesCount: Int = 0,
    @SerialName("storage_container_type")
    public val storageContainerType: String? = null,
    @SerialName("error_message")
    public val errorMessage: String = "",
    @SerialName("job_details")
    public val jobDetails: List<TaskDetail> = emptyList()
)

@Serializable
public data class TaskDetail(
    @SerialName("file_name")
    public val fileName: String? = null,
    public val status: String? = null,
    @SerialName("error_message")
    public val errorMessage: String? = null,
    public val outputs: List<OutputFile> = emptyList()
)

@Serializable
public data class OutputFile(
    @SerialName("file_name")
    public val fileName: String,
    @SerialName("output_type")
    public val outputType: String? = null
)

// --- Document Translation Jobs ---

@Serializable
public data class CreateDocumentJobRequest(
    @SerialName("original_filename")
    public val originalFilename: String,
    @SerialName("source_language_code")
    public val sourceLanguageCode: LanguageCode? = null,
    @SerialName("target_language_codes")
    public val targetLanguageCodes: List<LanguageCode> = emptyList(),
    @SerialName("job_name")
    public val jobName: String? = null,
    public val genre: String? = null,
    @SerialName("use_native_numerals")
    public val useNativeNumerals: Boolean? = null,
    @SerialName("style_guidelines")
    public val styleGuidelines: String? = null,
    @SerialName("language_specific_guidelines")
    public val languageSpecificGuidelines: Map<String, String>? = null
)

@Serializable
public data class CreateDocumentJobResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("upload_url")
    public val uploadUrl: String,
    @SerialName("expires_in_hours")
    public val expiresInHours: Int? = null,
    @SerialName("source_language_code")
    public val sourceLanguageCode: String? = null,
    @SerialName("target_language_codes")
    public val targetLanguageCodes: List<String> = emptyList()
)

@Serializable
public data class DocumentJobStartResponse(
    public val message: String? = null,
    @SerialName("job_id")
    public val jobId: String? = null
)

@Serializable
public data class DocumentJobLiveStatusResponse(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("job_name")
    public val jobName: String? = null,
    @SerialName("job_state")
    public val jobState: String? = null,
    @SerialName("source_language_code")
    public val sourceLanguageCode: String? = null,
    public val progress: Int = 0,
    @SerialName("created_at")
    public val createdAt: String? = null,
    @SerialName("updated_at")
    public val updatedAt: String? = null,
    @SerialName("error_message")
    public val errorMessage: String? = null
)

@Serializable
public data class DocumentJobExportStatusResponse(
    @SerialName("export_id")
    public val exportId: String,
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("target_language_code")
    public val targetLanguageCode: String? = null,
    public val format: String? = null,
    @SerialName("export_state")
    public val exportState: String? = null,
    @SerialName("download_url")
    public val downloadUrl: String? = null,
    public val filename: String? = null,
    @SerialName("file_size")
    public val fileSize: Long? = null,
    @SerialName("expires_in_hours")
    public val expiresInHours: Int? = null,
    @SerialName("error_message")
    public val errorMessage: String? = null,
    @SerialName("created_at")
    public val createdAt: String? = null,
    @SerialName("completed_at")
    public val completedAt: String? = null,
    public val progress: Int? = null
)

// --- Dubbing Jobs ---

@Serializable
public data class CreateDubbingJobRequest(
    @SerialName("src_lang")
    public val sourceLanguageCode: LanguageCode? = null,
    @SerialName("target_langs")
    public val targetLanguageCodes: List<LanguageCode> = emptyList(),
    @SerialName("export_options")
    public val exportOptions: List<String>? = null,
    @SerialName("voice_cloning")
    public val voiceCloning: Boolean? = true,
    @SerialName("voice_id")
    public val voiceId: String? = null,
    @SerialName("pace_preset")
    public val pacePreset: String? = null,
    @SerialName("num_speakers")
    public val numSpeakers: Int? = 1,
    @SerialName("disable_watermark")
    public val disableWatermark: Boolean? = false,
    public val register: String? = null,
    @SerialName("editor_flow")
    public val editorFlow: Boolean? = false,
    @SerialName("job_name")
    public val jobName: String? = null
)

@Serializable
public data class CreateDubbingJobResponse(
    public val status: String? = null,
    public val message: String? = null,
    public val data: CreateDubbingJobData? = null
)

@Serializable
public data class CreateDubbingJobData(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("upload_url")
    public val uploadUrl: String? = null
)

@Serializable
public data class DubbingStartResponse(
    public val status: String? = null,
    public val message: String? = null
)

@Serializable
public data class DubbingLiveStatusResponse(
    public val status: String? = null,
    public val message: String? = null,
    public val data: DubbingLiveStatusData? = null
)

@Serializable
public data class DubbingLiveStatusData(
    @SerialName("job_id")
    public val jobId: String,
    @SerialName("job_name")
    public val jobName: String? = null,
    public val status: String? = null,
    @SerialName("current_step")
    public val currentStep: String? = null,
    @SerialName("current_step_label")
    public val currentStepLabel: String? = null,
    public val progress: Int = 0,
    @SerialName("error_message")
    public val errorMessage: String? = null
)

@Serializable
public data class DubbingExportStatusResponse(
    public val status: String? = null,
    public val message: String? = null,
    public val data: DubbingExportStatusData? = null
)

@Serializable
public data class DubbingExportStatusData(
    @SerialName("job_id")
    public val jobId: String? = null,
    public val exports: List<DubbingExportItem> = emptyList()
)

@Serializable
public data class DubbingExportItem(
    @SerialName("export_id")
    public val exportId: String? = null,
    public val format: String? = null,
    public val language: String? = null,
    public val status: String? = null,
    public val url: String? = null
)
