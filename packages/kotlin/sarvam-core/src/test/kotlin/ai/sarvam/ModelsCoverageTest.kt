package ai.sarvam

import ai.sarvam.core.io.FileInput
import ai.sarvam.generated.AudioCodec
import ai.sarvam.generated.ChatModel
import ai.sarvam.generated.LanguageCode
import ai.sarvam.generated.Speaker
import ai.sarvam.generated.SttMode
import ai.sarvam.generated.SttModel
import ai.sarvam.generated.TtsModel
import ai.sarvam.models.*
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class ModelsCoverageTest {

    private fun <T : Any> exerciseDataClass(
        instance1: T,
        instance2Same: T,
        instance3Diff: T
    ) {
        // equals
        assertEquals(instance1, instance1)
        assertEquals(instance1, instance2Same)
        assertNotEquals(instance1, instance3Diff)
        assertNotEquals(instance1, null)
        assertNotEquals(instance1, "some other object")

        // hashCode
        assertEquals(instance1.hashCode(), instance2Same.hashCode())

        // toString
        assertNotNull(instance1.toString())
        assertTrue(instance1.toString().isNotEmpty())
    }

    // ==========================================
    // JobModels.kt
    // ==========================================

    @Test
    fun `test JobModels data classes`() {
        // SpeechToTextJobInitRequest
        val reqDefault = SpeechToTextJobInitRequest()
        assertNull(reqDefault.jobParameters)
        assertNull(reqDefault.callback)

        val params = SpeechToTextJobParameters(
            model = SttModel.SAARAS_V4,
            languageCode = LanguageCode.HI_IN,
            withDiarization = true,
            withTimestamps = true
        )
        val paramsDefault = SpeechToTextJobParameters()
        assertNull(paramsDefault.model)
        assertNull(paramsDefault.languageCode)
        assertNull(paramsDefault.withDiarization)
        assertNull(paramsDefault.withTimestamps)
        exerciseDataClass(params, params.copy(), paramsDefault)

        val callback = BulkJobCallback(url = "https://callback.url", headers = mapOf("H" to "V"))
        val callbackDefault = BulkJobCallback(url = "https://callback.url")
        assertNull(callbackDefault.headers)
        exerciseDataClass(callback, callback.copy(), callbackDefault)

        val reqExplicit = SpeechToTextJobInitRequest(jobParameters = params, callback = callback)
        exerciseDataClass(reqExplicit, reqExplicit.copy(), reqDefault)

        // BulkJobInitResponse
        val bRespDefault = BulkJobInitResponse(jobId = "j1")
        assertNull(bRespDefault.storageContainerType)
        assertNull(bRespDefault.jobState)
        val bRespExplicit = BulkJobInitResponse(jobId = "j1", storageContainerType = "azure", jobState = "pending")
        exerciseDataClass(bRespExplicit, bRespExplicit.copy(), bRespDefault)

        // FilesRequest
        val fReq = FilesRequest(jobId = "j1", files = listOf("f1.wav", "f2.wav"))
        exerciseDataClass(fReq, fReq.copy(), FilesRequest("j2", emptyList()))

        // FileSignedURLDetails
        val signedUrlDefault = FileSignedURLDetails()
        assertNull(signedUrlDefault.fileUrl)
        assertNull(signedUrlDefault.errorMessage)
        val signedUrlExplicit = FileSignedURLDetails(fileUrl = "https://url", errorMessage = "err")
        exerciseDataClass(signedUrlExplicit, signedUrlExplicit.copy(), signedUrlDefault)

        // FilesUploadResponse
        val upRespDefault = FilesUploadResponse(jobId = "j1")
        assertNull(upRespDefault.jobState)
        assertTrue(upRespDefault.uploadUrls.isEmpty())
        assertNull(upRespDefault.storageContainerType)
        val upRespExplicit = FilesUploadResponse(
            jobId = "j1",
            jobState = "ok",
            uploadUrls = mapOf("f1" to signedUrlExplicit),
            storageContainerType = "blob"
        )
        exerciseDataClass(upRespExplicit, upRespExplicit.copy(), upRespDefault)

        // FilesDownloadResponse
        val downRespDefault = FilesDownloadResponse(jobId = "j1")
        assertNull(downRespDefault.jobState)
        assertTrue(downRespDefault.downloadUrls.isEmpty())
        assertNull(downRespDefault.storageContainerType)
        val downRespExplicit = FilesDownloadResponse(
            jobId = "j1",
            jobState = "ok",
            downloadUrls = mapOf("f1" to signedUrlExplicit),
            storageContainerType = "blob"
        )
        exerciseDataClass(downRespExplicit, downRespExplicit.copy(), downRespDefault)

        // OutputFile
        val outFileDefault = OutputFile(fileName = "out.txt")
        assertNull(outFileDefault.outputType)
        val outFileExplicit = OutputFile(fileName = "out.txt", outputType = "text")
        exerciseDataClass(outFileExplicit, outFileExplicit.copy(), outFileDefault)

        // TaskDetail
        val taskDetailDefault = TaskDetail()
        assertNull(taskDetailDefault.fileName)
        assertNull(taskDetailDefault.status)
        assertNull(taskDetailDefault.errorMessage)
        assertTrue(taskDetailDefault.outputs.isEmpty())
        val taskDetailExplicit = TaskDetail(
            fileName = "f.wav",
            status = "completed",
            errorMessage = null,
            outputs = listOf(outFileExplicit)
        )
        exerciseDataClass(taskDetailExplicit, taskDetailExplicit.copy(), taskDetailDefault)

        // JobStatusResponse
        val jobStatusDefault = JobStatusResponse(jobId = "j1")
        assertNull(jobStatusDefault.jobState)
        assertNull(jobStatusDefault.createdAt)
        assertNull(jobStatusDefault.updatedAt)
        assertEquals(0, jobStatusDefault.totalFiles)
        assertEquals(0, jobStatusDefault.successfulFilesCount)
        assertEquals(0, jobStatusDefault.failedFilesCount)
        assertNull(jobStatusDefault.storageContainerType)
        assertEquals("", jobStatusDefault.errorMessage)
        assertTrue(jobStatusDefault.jobDetails.isEmpty())
        val jobStatusExplicit = JobStatusResponse(
            jobId = "j1",
            jobState = "running",
            createdAt = "2026-01-01",
            updatedAt = "2026-01-02",
            totalFiles = 10,
            successfulFilesCount = 8,
            failedFilesCount = 2,
            storageContainerType = "s3",
            errorMessage = "some error",
            jobDetails = listOf(taskDetailExplicit)
        )
        exerciseDataClass(jobStatusExplicit, jobStatusExplicit.copy(), jobStatusDefault)

        // CreateDocumentJobRequest
        val docReqDefault = CreateDocumentJobRequest(originalFilename = "doc.pdf")
        assertNull(docReqDefault.sourceLanguageCode)
        assertTrue(docReqDefault.targetLanguageCodes.isEmpty())
        assertNull(docReqDefault.jobName)
        assertNull(docReqDefault.genre)
        assertNull(docReqDefault.useNativeNumerals)
        assertNull(docReqDefault.styleGuidelines)
        assertNull(docReqDefault.languageSpecificGuidelines)
        val docReqExplicit = CreateDocumentJobRequest(
            originalFilename = "doc.pdf",
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCodes = listOf(LanguageCode.HI_IN),
            jobName = "job1",
            genre = "legal",
            useNativeNumerals = false,
            styleGuidelines = "formal",
            languageSpecificGuidelines = mapOf("hi-IN" to "guide")
        )
        exerciseDataClass(docReqExplicit, docReqExplicit.copy(), docReqDefault)

        // CreateDocumentJobResponse
        val docRespDefault = CreateDocumentJobResponse(jobId = "d1", uploadUrl = "https://up")
        assertNull(docRespDefault.expiresInHours)
        assertNull(docRespDefault.sourceLanguageCode)
        assertTrue(docRespDefault.targetLanguageCodes.isEmpty())
        val docRespExplicit = CreateDocumentJobResponse(
            jobId = "d1",
            uploadUrl = "https://up",
            expiresInHours = 24,
            sourceLanguageCode = "en-IN",
            targetLanguageCodes = listOf("hi-IN")
        )
        exerciseDataClass(docRespExplicit, docRespExplicit.copy(), docRespDefault)

        // DocumentJobStartResponse
        val docStartDefault = DocumentJobStartResponse()
        assertNull(docStartDefault.message)
        assertNull(docStartDefault.jobId)
        val docStartExplicit = DocumentJobStartResponse(message = "ok", jobId = "d1")
        exerciseDataClass(docStartExplicit, docStartExplicit.copy(), docStartDefault)

        // DocumentJobLiveStatusResponse
        val docLiveDefault = DocumentJobLiveStatusResponse(jobId = "d1")
        assertNull(docLiveDefault.jobName)
        assertNull(docLiveDefault.jobState)
        assertNull(docLiveDefault.sourceLanguageCode)
        assertEquals(0, docLiveDefault.progress)
        assertNull(docLiveDefault.createdAt)
        assertNull(docLiveDefault.updatedAt)
        assertNull(docLiveDefault.errorMessage)
        val docLiveExplicit = DocumentJobLiveStatusResponse(
            jobId = "d1",
            jobName = "job1",
            jobState = "processing",
            sourceLanguageCode = "en-IN",
            progress = 50,
            createdAt = "2026-01-01",
            updatedAt = "2026-01-02",
            errorMessage = "err"
        )
        exerciseDataClass(docLiveExplicit, docLiveExplicit.copy(), docLiveDefault)

        // DocumentJobExportStatusResponse
        val docExportDefault = DocumentJobExportStatusResponse(exportId = "exp1", jobId = "d1")
        assertNull(docExportDefault.targetLanguageCode)
        assertNull(docExportDefault.format)
        assertNull(docExportDefault.exportState)
        assertNull(docExportDefault.downloadUrl)
        assertNull(docExportDefault.filename)
        assertNull(docExportDefault.fileSize)
        assertNull(docExportDefault.expiresInHours)
        assertNull(docExportDefault.errorMessage)
        assertNull(docExportDefault.createdAt)
        assertNull(docExportDefault.completedAt)
        assertNull(docExportDefault.progress)
        val docExportExplicit = DocumentJobExportStatusResponse(
            exportId = "exp1",
            jobId = "d1",
            targetLanguageCode = "hi-IN",
            format = "pdf",
            exportState = "completed",
            downloadUrl = "https://down",
            filename = "hi.pdf",
            fileSize = 1024L,
            expiresInHours = 12,
            errorMessage = null,
            createdAt = "2026-01-01",
            completedAt = "2026-01-02",
            progress = 100
        )
        exerciseDataClass(docExportExplicit, docExportExplicit.copy(), docExportDefault)

        // CreateDubbingJobRequest
        val dubReqDefault = CreateDubbingJobRequest()
        assertNull(dubReqDefault.sourceLanguageCode)
        assertTrue(dubReqDefault.targetLanguageCodes.isEmpty())
        assertNull(dubReqDefault.exportOptions)
        assertEquals(true, dubReqDefault.voiceCloning)
        assertNull(dubReqDefault.voiceId)
        assertNull(dubReqDefault.pacePreset)
        assertEquals(1, dubReqDefault.numSpeakers)
        assertEquals(false, dubReqDefault.disableWatermark)
        assertNull(dubReqDefault.register)
        assertEquals(false, dubReqDefault.editorFlow)
        assertNull(dubReqDefault.jobName)
        val dubReqExplicit = CreateDubbingJobRequest(
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCodes = listOf(LanguageCode.HI_IN),
            exportOptions = listOf("mp4"),
            voiceCloning = false,
            voiceId = "v1",
            pacePreset = "fast",
            numSpeakers = 2,
            disableWatermark = true,
            register = "casual",
            editorFlow = true,
            jobName = "dub1"
        )
        exerciseDataClass(dubReqExplicit, dubReqExplicit.copy(), dubReqDefault)

        // CreateDubbingJobData & CreateDubbingJobResponse
        val dubDataDefault = CreateDubbingJobData(jobId = "dub1")
        assertNull(dubDataDefault.uploadUrl)
        val dubDataExplicit = CreateDubbingJobData(jobId = "dub1", uploadUrl = "https://up")
        exerciseDataClass(dubDataExplicit, dubDataExplicit.copy(), dubDataDefault)

        val dubRespDefault = CreateDubbingJobResponse()
        assertNull(dubRespDefault.status)
        assertNull(dubRespDefault.message)
        assertNull(dubRespDefault.data)
        val dubRespExplicit = CreateDubbingJobResponse(status = "ok", message = "created", data = dubDataExplicit)
        exerciseDataClass(dubRespExplicit, dubRespExplicit.copy(), dubRespDefault)

        // DubbingStartResponse
        val dubStartDefault = DubbingStartResponse()
        assertNull(dubStartDefault.status)
        assertNull(dubStartDefault.message)
        val dubStartExplicit = DubbingStartResponse(status = "ok", message = "started")
        exerciseDataClass(dubStartExplicit, dubStartExplicit.copy(), dubStartDefault)

        // DubbingLiveStatusData & DubbingLiveStatusResponse
        val dubLiveDefault = DubbingLiveStatusData(jobId = "dub1")
        assertNull(dubLiveDefault.jobName)
        assertNull(dubLiveDefault.status)
        assertNull(dubLiveDefault.currentStep)
        assertNull(dubLiveDefault.currentStepLabel)
        assertEquals(0, dubLiveDefault.progress)
        assertNull(dubLiveDefault.errorMessage)
        val dubLiveExplicit = DubbingLiveStatusData(
            jobId = "dub1",
            jobName = "name1",
            status = "dubbing",
            currentStep = "step1",
            currentStepLabel = "Step 1",
            progress = 25,
            errorMessage = "err"
        )
        exerciseDataClass(dubLiveExplicit, dubLiveExplicit.copy(), dubLiveDefault)

        val dubLiveRespDefault = DubbingLiveStatusResponse()
        assertNull(dubLiveRespDefault.status)
        assertNull(dubLiveRespDefault.message)
        assertNull(dubLiveRespDefault.data)
        val dubLiveRespExplicit = DubbingLiveStatusResponse(status = "ok", message = "msg", data = dubLiveExplicit)
        exerciseDataClass(dubLiveRespExplicit, dubLiveRespExplicit.copy(), dubLiveRespDefault)

        // DubbingExportItem & DubbingExportStatusData & DubbingExportStatusResponse
        val dubItemDefault = DubbingExportItem()
        assertNull(dubItemDefault.exportId)
        assertNull(dubItemDefault.format)
        assertNull(dubItemDefault.language)
        assertNull(dubItemDefault.status)
        assertNull(dubItemDefault.url)
        val dubItemExplicit = DubbingExportItem(
            exportId = "e1",
            format = "mp4",
            language = "hi",
            status = "ready",
            url = "https://url"
        )
        exerciseDataClass(dubItemExplicit, dubItemExplicit.copy(), dubItemDefault)

        val dubExpDataDefault = DubbingExportStatusData()
        assertNull(dubExpDataDefault.jobId)
        assertTrue(dubExpDataDefault.exports.isEmpty())
        val dubExpDataExplicit = DubbingExportStatusData(jobId = "dub1", exports = listOf(dubItemExplicit))
        exerciseDataClass(dubExpDataExplicit, dubExpDataExplicit.copy(), dubExpDataDefault)

        val dubExpRespDefault = DubbingExportStatusResponse()
        assertNull(dubExpRespDefault.status)
        assertNull(dubExpRespDefault.message)
        assertNull(dubExpRespDefault.data)
        val dubExpRespExplicit = DubbingExportStatusResponse(status = "ok", message = "msg", data = dubExpDataExplicit)
        exerciseDataClass(dubExpRespExplicit, dubExpRespExplicit.copy(), dubExpRespDefault)
    }

    // ==========================================
    // VoiceCloningModels.kt
    // ==========================================

    @Test
    fun `test VoiceCloningModels data classes`() {
        // VoiceCloneRequest
        val file = FileInput.fromBytes(byteArrayOf(1, 2, 3), "test.wav")
        val vcReqDefault = VoiceCloneRequest(text = "Hello")
        assertNull(vcReqDefault.voiceId)
        assertNull(vcReqDefault.refAudio)
        assertNull(vcReqDefault.refText)
        assertNull(vcReqDefault.languageCode)
        assertNull(vcReqDefault.pace)
        assertNull(vcReqDefault.outputAudioCodec)
        assertNull(vcReqDefault.speechSampleRate)
        assertNull(vcReqDefault.enableQc)
        assertNull(vcReqDefault.enableCachedResponses)
        assertNull(vcReqDefault.enableVad)
        assertNull(vcReqDefault.enableTextNormalization)
        assertNull(vcReqDefault.minAudioDuration)
        assertNull(vcReqDefault.maxAudioDuration)
        assertNull(vcReqDefault.refAudioDuration)

        val vcReqExplicit = VoiceCloneRequest(
            text = "Hello",
            voiceId = "v1",
            refAudio = file,
            refText = "ref",
            languageCode = LanguageCode.HI_IN,
            pace = 1.0,
            outputAudioCodec = AudioCodec.WAV,
            speechSampleRate = 16000,
            enableQc = true,
            enableCachedResponses = false,
            enableVad = true,
            enableTextNormalization = true,
            minAudioDuration = 0.5,
            maxAudioDuration = 10.0,
            refAudioDuration = 3.0
        )
        exerciseDataClass(vcReqExplicit, vcReqExplicit.copy(), vcReqDefault)

        // VoiceCloneResponse
        val b64Audio = Base64.getEncoder().encodeToString(byteArrayOf(4, 5, 6))
        val respAudio = VoiceCloneResponse(audio = b64Audio, requestId = "r1", audioDuration = 1.2)
        assertArrayEquals(byteArrayOf(4, 5, 6), respAudio.audioBytes)
        exerciseDataClass(respAudio, respAudio.copy(), VoiceCloneResponse())

        val respAudioB64 = VoiceCloneResponse(audioB64 = b64Audio)
        assertArrayEquals(byteArrayOf(4, 5, 6), respAudioB64.audioBytes)

        val respEmpty = VoiceCloneResponse(audio = "", audioB64 = "")
        assertArrayEquals(ByteArray(0), respEmpty.audioBytes)

        val respNull = VoiceCloneResponse()
        assertArrayEquals(ByteArray(0), respNull.audioBytes)

        // VoiceLibraryListResponse & VoiceLibraryListData
        val voiceDefault = VoiceLibraryVoice(id = "v1", name = "Priya")
        assertNull(voiceDefault.language)
        assertNull(voiceDefault.gender)
        assertNull(voiceDefault.accent)
        assertNull(voiceDefault.descriptor)
        assertNull(voiceDefault.status)
        assertNull(voiceDefault.source)
        assertNull(voiceDefault.createdAt)

        val voiceExplicit = VoiceLibraryVoice(
            id = "v1",
            name = "Priya",
            language = "hi",
            gender = "female",
            accent = "delhi",
            descriptor = "calm",
            status = "ready",
            source = "studio",
            createdAt = "2026-01-01"
        )
        exerciseDataClass(voiceExplicit, voiceExplicit.copy(), voiceDefault)

        val listDataDefault = VoiceLibraryListData()
        assertTrue(listDataDefault.voices.isEmpty())
        assertEquals(0, listDataDefault.total)
        val listDataExplicit = VoiceLibraryListData(voices = listOf(voiceExplicit), total = 1)
        exerciseDataClass(listDataExplicit, listDataExplicit.copy(), listDataDefault)

        val listRespDefault = VoiceLibraryListResponse()
        assertNull(listRespDefault.status)
        assertNull(listRespDefault.data)
        val listRespExplicit = VoiceLibraryListResponse(status = "ok", data = listDataExplicit)
        exerciseDataClass(listRespExplicit, listRespExplicit.copy(), listRespDefault)

        // VoiceLibraryCreateResponse & VoiceLibraryCreateData
        val createDataDefault = VoiceLibraryCreateData(voiceId = "v1")
        assertNull(createDataDefault.status)
        assertNull(createDataDefault.referenceText)
        val createDataExplicit = VoiceLibraryCreateData(voiceId = "v1", status = "created", referenceText = "ref")
        exerciseDataClass(createDataExplicit, createDataExplicit.copy(), createDataDefault)

        val createRespDefault = VoiceLibraryCreateResponse()
        assertNull(createRespDefault.status)
        assertNull(createRespDefault.data)
        val createRespExplicit = VoiceLibraryCreateResponse(status = "ok", data = createDataExplicit)
        exerciseDataClass(createRespExplicit, createRespExplicit.copy(), createRespDefault)

        // VoiceLibraryDetailResponse & VoiceLibraryDetail
        val detailDefault = VoiceLibraryDetail(id = "v1", name = "Priya")
        assertNull(detailDefault.language)
        assertNull(detailDefault.gender)
        assertNull(detailDefault.accent)
        assertNull(detailDefault.descriptor)
        assertNull(detailDefault.status)
        assertNull(detailDefault.source)
        assertNull(detailDefault.createdAt)
        assertNull(detailDefault.referenceText)
        assertNull(detailDefault.previewAudioUrl)
        assertNull(detailDefault.referenceAudioUrl)

        val detailExplicit = VoiceLibraryDetail(
            id = "v1",
            name = "Priya",
            language = "hi",
            gender = "female",
            accent = "in",
            descriptor = "desc",
            status = "ready",
            source = "user",
            createdAt = "2026-01-01",
            referenceText = "text",
            previewAudioUrl = "https://prev",
            referenceAudioUrl = "https://ref"
        )
        exerciseDataClass(detailExplicit, detailExplicit.copy(), detailDefault)

        val detailRespDefault = VoiceLibraryDetailResponse()
        assertNull(detailRespDefault.status)
        assertNull(detailRespDefault.data)
        val detailRespExplicit = VoiceLibraryDetailResponse(status = "ok", data = detailExplicit)
        exerciseDataClass(detailRespExplicit, detailRespExplicit.copy(), detailRespDefault)
    }

    // ==========================================
    // DocAiModels.kt
    // ==========================================

    @Test
    fun `test DocAiModels data classes and status helpers`() {
        // DocAIStartJobResponse
        val startRespDefault = DocAIStartJobResponse(jobId = "j1", status = "pending")
        assertNull(startRespDefault.runId)
        val startRespExplicit = DocAIStartJobResponse(jobId = "j1", status = "pending", runId = "r1")
        exerciseDataClass(startRespExplicit, startRespExplicit.copy(), startRespDefault)

        // DocAIPresignUploadRequest
        val presignReqDefault = DocAIPresignUploadRequest()
        assertNull(presignReqDefault.contentType)
        val presignReqExplicit = DocAIPresignUploadRequest(contentType = "application/pdf")
        exerciseDataClass(presignReqExplicit, presignReqExplicit.copy(), presignReqDefault)

        // DocAIPresignUploadResponse
        val presignRespDefault = DocAIPresignUploadResponse(uploadId = "u1", url = "https://url")
        assertNull(presignRespDefault.method)
        assertTrue(presignRespDefault.headers.isEmpty())
        assertNull(presignRespDefault.expiresAt)
        val presignRespExplicit = DocAIPresignUploadResponse(
            uploadId = "u1",
            method = "PUT",
            url = "https://url",
            headers = mapOf("H" to "V"),
            expiresAt = "2026-12-31"
        )
        exerciseDataClass(presignRespExplicit, presignRespExplicit.copy(), presignRespDefault)

        // DocAIUsage
        val usageDefault = DocAIUsage()
        assertNull(usageDefault.pages)
        assertNull(usageDefault.characters)
        val usageExplicit = DocAIUsage(pages = 5, characters = 1000)
        exerciseDataClass(usageExplicit, usageExplicit.copy(), usageDefault)

        // DocAIJobStatusResponse
        val jobStatusDefault = DocAIJobStatusResponse(jobId = "j1", status = "pending")
        assertNull(jobStatusDefault.pipeline)
        assertNull(jobStatusDefault.usage)
        assertNull(jobStatusDefault.createdAt)
        assertNull(jobStatusDefault.updatedAt)
        val jobStatusExplicit = DocAIJobStatusResponse(
            jobId = "j1",
            status = "completed",
            pipeline = "digitise",
            usage = usageExplicit,
            createdAt = "2026-01-01",
            updatedAt = "2026-01-02"
        )
        exerciseDataClass(jobStatusExplicit, jobStatusExplicit.copy(), jobStatusDefault)

        // Status helpers
        for (status in listOf("completed", "partially_completed", "failed", "rejected", "COMPLETED", "FAILED")) {
            val s = DocAIJobStatusResponse(jobId = "j1", status = status)
            assertTrue(s.isTerminal)
        }
        for (status in listOf("failed", "rejected", "FAILED")) {
            val s = DocAIJobStatusResponse(jobId = "j1", status = status)
            assertTrue(s.isFailed)
            assertFalse(s.isSuccessful)
        }
        for (status in listOf("completed", "partially_completed", "COMPLETED")) {
            val s = DocAIJobStatusResponse(jobId = "j1", status = status)
            assertTrue(s.isSuccessful)
            assertFalse(s.isFailed)
        }
        val runningStatus = DocAIJobStatusResponse(jobId = "j1", status = "running")
        assertFalse(runningStatus.isTerminal)
        assertFalse(runningStatus.isFailed)
        assertFalse(runningStatus.isSuccessful)

        // Companion object sets
        assertTrue(DocAIJobStatusResponse.TERMINAL_STATUSES.contains("completed"))
        assertTrue(DocAIJobStatusResponse.FAILED_STATUSES.contains("failed"))
        assertTrue(DocAIJobStatusResponse.SUCCESSFUL_STATUSES.contains("partially_completed"))

        // DocAIDownloadURLResponse
        val downRespDefault = DocAIDownloadURLResponse(url = "https://down")
        assertNull(downRespDefault.method)
        assertTrue(downRespDefault.headers.isEmpty())
        assertNull(downRespDefault.expiresAt)
        val downRespExplicit = DocAIDownloadURLResponse(
            method = "GET",
            url = "https://down",
            headers = mapOf("A" to "B"),
            expiresAt = "2026-12-31"
        )
        exerciseDataClass(downRespExplicit, downRespExplicit.copy(), downRespDefault)
    }

    // ==========================================
    // ChatModels.kt
    // ==========================================

    @Test
    fun `test ChatModels data classes`() {
        // ChatMessage
        val msg = ChatMessage(role = "user", content = "hello")
        exerciseDataClass(msg, msg.copy(), ChatMessage("assistant", "hi"))

        // ChatCompletionRequest
        val chatReqDefault = ChatCompletionRequest(model = "sarvam-2b", messages = listOf(msg))
        assertNull(chatReqDefault.stream)
        assertNull(chatReqDefault.temperature)
        assertNull(chatReqDefault.topP)
        assertNull(chatReqDefault.maxTokens)

        val chatReqExplicit = ChatCompletionRequest(
            model = "sarvam-2b",
            messages = listOf(msg),
            stream = true,
            temperature = 0.7,
            topP = 0.9,
            maxTokens = 100
        )
        exerciseDataClass(chatReqExplicit, chatReqExplicit.copy(), chatReqDefault)

        // ChatUsage
        val usageDefault = ChatUsage()
        assertEquals(0, usageDefault.promptTokens)
        assertEquals(0, usageDefault.completionTokens)
        assertEquals(0, usageDefault.totalTokens)
        val usageExplicit = ChatUsage(promptTokens = 10, completionTokens = 20, totalTokens = 30)
        exerciseDataClass(usageExplicit, usageExplicit.copy(), usageDefault)

        // ChatChoice & ChatCompletionResponse
        val choiceDefault = ChatChoice()
        assertEquals(0, choiceDefault.index)
        assertNull(choiceDefault.message)
        assertNull(choiceDefault.finishReason)
        val choiceExplicit = ChatChoice(index = 1, message = msg, finishReason = "stop")
        exerciseDataClass(choiceExplicit, choiceExplicit.copy(), choiceDefault)

        val compRespDefault = ChatCompletionResponse()
        assertEquals("", compRespDefault.id)
        assertTrue(compRespDefault.choices.isEmpty())
        assertNull(compRespDefault.usage)
        val compRespExplicit = ChatCompletionResponse(id = "c1", choices = listOf(choiceExplicit), usage = usageExplicit)
        exerciseDataClass(compRespExplicit, compRespExplicit.copy(), compRespDefault)

        // ChatChunkDelta & ChatChunkChoice & ChatCompletionChunk
        val deltaDefault = ChatChunkDelta()
        assertNull(deltaDefault.role)
        assertNull(deltaDefault.content)
        val deltaExplicit = ChatChunkDelta(role = "assistant", content = "word")
        exerciseDataClass(deltaExplicit, deltaExplicit.copy(), deltaDefault)

        val chunkChoiceDefault = ChatChunkChoice()
        assertEquals(0, chunkChoiceDefault.index)
        assertNull(chunkChoiceDefault.delta)
        assertNull(chunkChoiceDefault.finishReason)
        val chunkChoiceExplicit = ChatChunkChoice(index = 0, delta = deltaExplicit, finishReason = "stop")
        exerciseDataClass(chunkChoiceExplicit, chunkChoiceExplicit.copy(), chunkChoiceDefault)

        val chunkDefault = ChatCompletionChunk()
        assertNull(chunkDefault.id)
        assertTrue(chunkDefault.choices.isEmpty())
        assertNull(chunkDefault.usage)
        assertNull(chunkDefault.firstDeltaContent)

        val chunkExplicit = ChatCompletionChunk(id = "chk1", choices = listOf(chunkChoiceExplicit), usage = usageExplicit)
        assertEquals("word", chunkExplicit.firstDeltaContent)
        exerciseDataClass(chunkExplicit, chunkExplicit.copy(), chunkDefault)

        val chunkNoDelta = ChatCompletionChunk(choices = listOf(ChatChunkChoice(delta = null)))
        assertNull(chunkNoDelta.firstDeltaContent)

        // ModelInfo & ModelListResponse
        val modelInfoDefault = ModelInfo(id = "m1")
        assertNull(modelInfoDefault.created)
        assertNull(modelInfoDefault.ownedBy)
        val modelInfoExplicit = ModelInfo(id = "m1", created = 123456L, ownedBy = "sarvam")
        exerciseDataClass(modelInfoExplicit, modelInfoExplicit.copy(), modelInfoDefault)

        val modelListDefault = ModelListResponse()
        assertTrue(modelListDefault.models.isEmpty())
        val modelListExplicit = ModelListResponse(models = listOf(modelInfoExplicit))
        exerciseDataClass(modelListExplicit, modelListExplicit.copy(), modelListDefault)
    }

    // ==========================================
    // TextToSpeechModels.kt
    // ==========================================

    @Test
    fun `test TextToSpeechModels data classes and audio chunk equals-hashCode`() {
        // TextToSpeechRequest
        val ttsReqDefault = TextToSpeechRequest(
            text = "Hello world",
            targetLanguageCode = LanguageCode.HI_IN
        )
        assertNull(ttsReqDefault.speaker)
        assertNull(ttsReqDefault.pitch)
        assertNull(ttsReqDefault.pace)
        assertNull(ttsReqDefault.loudness)
        assertNull(ttsReqDefault.speechSampleRate)
        assertNull(ttsReqDefault.enablePreprocessing)
        assertNull(ttsReqDefault.model)
        assertNull(ttsReqDefault.outputAudioCodec)

        val ttsReqExplicit = TextToSpeechRequest(
            text = "Hello world",
            targetLanguageCode = LanguageCode.HI_IN,
            speaker = Speaker.ANUSHKA,
            pitch = 1.0,
            pace = 1.0,
            loudness = 1.5,
            speechSampleRate = 22050,
            enablePreprocessing = true,
            model = TtsModel.BULBUL_V2,
            outputAudioCodec = AudioCodec.MP3
        )
        exerciseDataClass(ttsReqExplicit, ttsReqExplicit.copy(), ttsReqDefault)

        // TtsAudio
        val ttsAudio = TtsAudio("aGVsbG8=")
        exerciseDataClass(ttsAudio, ttsAudio.copy(), TtsAudio("d29ybGQ="))

        // TextToSpeechResponse
        val ttsRespDefault = TextToSpeechResponse()
        assertTrue(ttsRespDefault.audios.isEmpty())
        assertNull(ttsRespDefault.firstAudioBase64)
        assertEquals(0, ttsRespDefault.firstAudioByteLength)
        assertEquals(0, ttsRespDefault.audioCount)
        assertArrayEquals(ByteArray(0), ttsRespDefault.audioBytes)

        val ttsRespExplicit = TextToSpeechResponse(audios = listOf(TtsAudio("aGVsbG8=")))
        assertEquals("aGVsbG8=", ttsRespExplicit.firstAudioBase64)
        assertEquals(5, ttsRespExplicit.firstAudioByteLength)
        assertEquals(1, ttsRespExplicit.audioCount)
        assertEquals("hello", String(ttsRespExplicit.audioBytes))
        exerciseDataClass(ttsRespExplicit, ttsRespExplicit.copy(), ttsRespDefault)

        val ttsRespEmptyAudio = TextToSpeechResponse(audios = listOf(TtsAudio("")))
        assertEquals("", ttsRespEmptyAudio.firstAudioBase64)
        assertEquals(0, ttsRespEmptyAudio.firstAudioByteLength)
        assertArrayEquals(ByteArray(0), ttsRespEmptyAudio.audioBytes)

        // TtsStreamingConfig
        val ttsStreamConfigDefault = TtsStreamingConfig()
        assertEquals(LanguageCode.HI_IN, ttsStreamConfigDefault.languageCode)
        assertNull(ttsStreamConfigDefault.speaker)
        assertEquals(TtsModel.BULBUL_V4_FLASH, ttsStreamConfigDefault.model)
        assertEquals(22050, ttsStreamConfigDefault.speechSampleRate)
        assertEquals(AudioCodec.MP3, ttsStreamConfigDefault.outputAudioCodec)
        assertNull(ttsStreamConfigDefault.pitch)
        assertNull(ttsStreamConfigDefault.pace)
        assertNull(ttsStreamConfigDefault.loudness)
        assertNull(ttsStreamConfigDefault.enablePreprocessing)
        assertNull(ttsStreamConfigDefault.voiceId)

        val ttsStreamConfigExplicit = TtsStreamingConfig(
            languageCode = LanguageCode.EN_IN,
            speaker = Speaker.ABHILASH,
            model = TtsModel.BULBUL_V2,
            speechSampleRate = 16000,
            outputAudioCodec = AudioCodec.WAV,
            pitch = 0.5,
            pace = 1.2,
            loudness = 2.0,
            enablePreprocessing = false,
            voiceId = "custom-voice"
        )
        exerciseDataClass(ttsStreamConfigExplicit, ttsStreamConfigExplicit.copy(), ttsStreamConfigDefault)

        // TtsStreamEvent sealed classes
        val audioBytes = byteArrayOf(10, 20, 30)
        val chunk1 = TtsStreamEvent.AudioChunk(audioBytes, "audio/mp3", "req1")
        val chunkSame = TtsStreamEvent.AudioChunk(byteArrayOf(10, 20, 30), "audio/mp3", "req1")
        val chunkDiffBytes = TtsStreamEvent.AudioChunk(byteArrayOf(10, 20, 31), "audio/mp3", "req1")
        val chunkDiffType = TtsStreamEvent.AudioChunk(audioBytes, "audio/wav", "req1")
        val chunkDiffReq = TtsStreamEvent.AudioChunk(audioBytes, "audio/mp3", "req2")
        val chunkNulls = TtsStreamEvent.AudioChunk(audioBytes, null, null)

        // equals coverage for AudioChunk
        assertEquals(chunk1, chunk1)
        assertEquals(chunk1, chunkSame)
        assertNotEquals(chunk1, chunkDiffBytes)
        assertNotEquals(chunk1, chunkDiffType)
        assertNotEquals(chunk1, chunkDiffReq)
        assertNotEquals(chunk1, chunkNulls)
        assertNotEquals(chunk1, null)
        assertNotEquals(chunk1, "string")

        // hashCode coverage for AudioChunk
        assertEquals(chunk1.hashCode(), chunkSame.hashCode())
        assertNotNull(chunkNulls.hashCode())

        // Completed, Error, Unknown
        val completedDefault = TtsStreamEvent.Completed()
        assertNull(completedDefault.requestId)
        val completedExplicit = TtsStreamEvent.Completed(requestId = "r1")
        exerciseDataClass(completedExplicit, completedExplicit.copy(), completedDefault)

        val errorDefault = TtsStreamEvent.Error(message = "fail")
        assertNull(errorDefault.code)
        val errorExplicit = TtsStreamEvent.Error(message = "fail", code = "err_500")
        exerciseDataClass(errorExplicit, errorExplicit.copy(), errorDefault)

        val unknown = TtsStreamEvent.Unknown(rawJson = "{}")
        exerciseDataClass(unknown, unknown.copy(), TtsStreamEvent.Unknown("""{"x":1}"""))
    }

    // ==========================================
    // SpeechToTextModels.kt
    // ==========================================

    @Test
    fun `test SpeechToTextModels data classes and events`() {
        // SpeechTimestamp
        val tsDefault = SpeechTimestamp()
        assertNull(tsDefault.word)
        assertNull(tsDefault.startS)
        assertNull(tsDefault.endS)
        val tsExplicit = SpeechTimestamp(word = "hello", startS = 0.0, endS = 0.5)
        exerciseDataClass(tsExplicit, tsExplicit.copy(), tsDefault)

        // DiarizedEntry & DiarizedTranscript
        val entryDefault = DiarizedEntry(transcript = "text")
        assertNull(entryDefault.startTimeSeconds)
        assertNull(entryDefault.endTimeSeconds)
        assertNull(entryDefault.speakerId)
        val entryExplicit = DiarizedEntry(transcript = "text", startTimeSeconds = 1.0, endTimeSeconds = 2.0, speakerId = "spk1")
        exerciseDataClass(entryExplicit, entryExplicit.copy(), entryDefault)

        val diarTranscriptDefault = DiarizedTranscript()
        assertTrue(diarTranscriptDefault.entries.isEmpty())
        val diarTranscriptExplicit = DiarizedTranscript(entries = listOf(entryExplicit))
        exerciseDataClass(diarTranscriptExplicit, diarTranscriptExplicit.copy(), diarTranscriptDefault)

        // SpeechToTextResponse
        val sttRespDefault = SpeechToTextResponse()
        assertNull(sttRespDefault.transcript)
        assertNull(sttRespDefault.languageCode)
        assertNull(sttRespDefault.timestamps)
        assertNull(sttRespDefault.diarizedTranscript)
        val sttRespExplicit = SpeechToTextResponse(
            transcript = "hello",
            languageCode = LanguageCode.HI_IN,
            timestamps = listOf(tsExplicit),
            diarizedTranscript = diarTranscriptExplicit
        )
        exerciseDataClass(sttRespExplicit, sttRespExplicit.copy(), sttRespDefault)

        // SttRealtimeConfig
        val rtConfigDefault = SttRealtimeConfig()
        assertEquals(LanguageCode.HI_IN, rtConfigDefault.languageCode)
        assertEquals(SttModel.SAARAS_V3_REALTIME, rtConfigDefault.model)
        assertEquals(16000, rtConfigDefault.sampleRate)
        assertNull(rtConfigDefault.streamType)
        assertNull(rtConfigDefault.mode)
        assertNull(rtConfigDefault.encoding)
        assertNull(rtConfigDefault.returnTimestamps)
        assertNull(rtConfigDefault.endpointing)
        assertNull(rtConfigDefault.threshold)
        assertNull(rtConfigDefault.prefixPaddingMs)
        assertNull(rtConfigDefault.silenceDurationMs)
        assertNull(rtConfigDefault.minSpeechDurationMs)
        assertNull(rtConfigDefault.prompt)
        assertNull(rtConfigDefault.keyterms)
        assertEquals(false, rtConfigDefault.useSubprotocolAuth)

        val rtConfigExplicit = SttRealtimeConfig(
            languageCode = LanguageCode.EN_IN,
            model = SttModel.SAARAS_V4,
            sampleRate = 8000,
            streamType = "raw",
            mode = SttMode.TRANSCRIBE,
            encoding = "pcm_s16le",
            returnTimestamps = true,
            endpointing = true,
            threshold = 0.5,
            prefixPaddingMs = 300,
            silenceDurationMs = 500,
            minSpeechDurationMs = 200,
            prompt = "context",
            keyterms = listOf("a", "b"),
            useSubprotocolAuth = true
        )
        exerciseDataClass(rtConfigExplicit, rtConfigExplicit.copy(), rtConfigDefault)

        // SttRealtimeEvent subclasses
        val sb = SttRealtimeEvent.SessionBegin(sessionId = "sess_1")
        exerciseDataClass(sb, sb.copy(), SttRealtimeEvent.SessionBegin("sess_2"))

        val vssDefault = SttRealtimeEvent.VadSpeechStart()
        assertNull(vssDefault.timestampMs)
        val vssExplicit = SttRealtimeEvent.VadSpeechStart(timestampMs = 100L)
        exerciseDataClass(vssExplicit, vssExplicit.copy(), vssDefault)

        val vseDefault = SttRealtimeEvent.VadSpeechEnd()
        assertNull(vseDefault.timestampMs)
        val vseExplicit = SttRealtimeEvent.VadSpeechEnd(timestampMs = 200L)
        exerciseDataClass(vseExplicit, vseExplicit.copy(), vseDefault)

        val tpDefault = SttRealtimeEvent.TranscriptPartial(text = "partial")
        assertNull(tpDefault.utteranceIdx)
        assertNull(tpDefault.language)
        val tpExplicit = SttRealtimeEvent.TranscriptPartial(utteranceIdx = 1, text = "partial", language = LanguageCode.HI_IN)
        exerciseDataClass(tpExplicit, tpExplicit.copy(), tpDefault)

        val tfDefault = SttRealtimeEvent.TranscriptFinal(text = "final")
        assertNull(tfDefault.utteranceIdx)
        assertNull(tfDefault.language)
        assertNull(tfDefault.languageConfidence)
        assertNull(tfDefault.startS)
        assertNull(tfDefault.endS)
        val tfExplicit = SttRealtimeEvent.TranscriptFinal(
            utteranceIdx = 2,
            text = "final",
            language = LanguageCode.HI_IN,
            languageConfidence = 0.99,
            startS = 1.0,
            endS = 3.5
        )
        exerciseDataClass(tfExplicit, tfExplicit.copy(), tfDefault)

        val seDefault = SttRealtimeEvent.SessionEnd()
        assertNull(seDefault.durationSeconds)
        val seExplicit = SttRealtimeEvent.SessionEnd(durationSeconds = 12.3)
        exerciseDataClass(seExplicit, seExplicit.copy(), seDefault)

        val errDefault = SttRealtimeEvent.Error(message = "some error")
        assertNull(errDefault.code)
        val errExplicit = SttRealtimeEvent.Error(code = "err_code", message = "some error")
        exerciseDataClass(errExplicit, errExplicit.copy(), errDefault)

        val unk = SttRealtimeEvent.Unknown(rawJson = "{}")
        exerciseDataClass(unk, unk.copy(), SttRealtimeEvent.Unknown("""{"other":1}"""))
    }

    // ==========================================
    // TextModels.kt
    // ==========================================

    @Test
    fun `test TextModels data classes`() {
        // TranslateRequest
        val trReqDefault = TranslateRequest(input = "hello", targetLanguageCode = LanguageCode.HI_IN)
        assertEquals(LanguageCode.AUTO, trReqDefault.sourceLanguageCode)
        assertNull(trReqDefault.speakerGender)
        assertNull(trReqDefault.mode)
        assertNull(trReqDefault.model)
        assertNull(trReqDefault.enablePreprocessing)

        val trReqExplicit = TranslateRequest(
            input = "hello",
            sourceLanguageCode = LanguageCode.EN_IN,
            targetLanguageCode = LanguageCode.HI_IN,
            speakerGender = "female",
            mode = "formal",
            model = "mayura:v1",
            enablePreprocessing = true
        )
        exerciseDataClass(trReqExplicit, trReqExplicit.copy(), trReqDefault)

        // TranslateResponse
        val trResp = TranslateResponse(translatedText = "नमस्ते")
        exerciseDataClass(trResp, trResp.copy(), TranslateResponse("hello"))

        // TransliterateRequest
        val tlitReqDefault = TransliterateRequest(
            input = "namaste",
            sourceLanguageCode = LanguageCode.HI_IN,
            targetLanguageCode = LanguageCode.EN_IN
        )
        assertNull(tlitReqDefault.spokenForm)
        assertNull(tlitReqDefault.model)

        val tlitReqExplicit = TransliterateRequest(
            input = "namaste",
            sourceLanguageCode = LanguageCode.HI_IN,
            targetLanguageCode = LanguageCode.EN_IN,
            spokenForm = true,
            model = "akshara:v1"
        )
        exerciseDataClass(tlitReqExplicit, tlitReqExplicit.copy(), tlitReqDefault)

        // TransliterateResponse
        val tlitResp = TransliterateResponse(transliteratedText = "namaste")
        exerciseDataClass(tlitResp, tlitResp.copy(), TransliterateResponse("other"))

        // TextLidRequest & TextLidResponse
        val lidReq = TextLidRequest(input = "text to detect")
        exerciseDataClass(lidReq, lidReq.copy(), TextLidRequest("other text"))

        val lidResp = TextLidResponse(detectedLanguage = "hi-IN", confidence = 0.98)
        exerciseDataClass(lidResp, lidResp.copy(), TextLidResponse("en-IN", 0.5))
    }

    // ==========================================
    // ResponsesModels.kt
    // ==========================================

    @Test
    fun `test ResponsesModels data classes and events`() {
        // ResponsesRequest
        val respReqDefault = ResponsesRequest(model = "sarvam-2b", input = "hi")
        assertEquals(true, respReqDefault.stream)
        val respReqExplicit = ResponsesRequest(model = "sarvam-2b", input = "hi", stream = false)
        exerciseDataClass(respReqExplicit, respReqExplicit.copy(), respReqDefault)

        // ResponseItem & ContentPart
        val itemDefault = ResponseItem()
        assertNull(itemDefault.id)
        assertNull(itemDefault.type)
        assertNull(itemDefault.role)
        val itemExplicit = ResponseItem(id = "it1", type = "message", role = "assistant")
        exerciseDataClass(itemExplicit, itemExplicit.copy(), itemDefault)

        val partDefault = ContentPart()
        assertNull(partDefault.type)
        assertNull(partDefault.text)
        val partExplicit = ContentPart(type = "text", text = "hello")
        exerciseDataClass(partExplicit, partExplicit.copy(), partDefault)

        // ResponseStreamEvent classes
        val rc = ResponseStreamEvent.ResponseCreated(id = "r1", type = "response.created")
        exerciseDataClass(rc, rc.copy(), ResponseStreamEvent.ResponseCreated("r2", "response.created"))

        val roiDefault = ResponseStreamEvent.ResponseOutputItemAdded(id = "r1", type = "response.output_item.added")
        assertNull(roiDefault.item)
        val roiExplicit = ResponseStreamEvent.ResponseOutputItemAdded(id = "r1", type = "response.output_item.added", item = itemExplicit)
        exerciseDataClass(roiExplicit, roiExplicit.copy(), roiDefault)

        val rcpDefault = ResponseStreamEvent.ResponseContentPartAdded(id = "r1", type = "response.content_part.added")
        assertNull(rcpDefault.itemId)
        assertNull(rcpDefault.part)
        val rcpExplicit = ResponseStreamEvent.ResponseContentPartAdded(
            id = "r1",
            type = "response.content_part.added",
            itemId = "it1",
            part = partExplicit
        )
        exerciseDataClass(rcpExplicit, rcpExplicit.copy(), rcpDefault)

        val rcompDefault = ResponseStreamEvent.ResponseCompleted(id = "r1", type = "response.completed")
        assertNull(rcompDefault.status)
        val rcompExplicit = ResponseStreamEvent.ResponseCompleted(id = "r1", type = "response.completed", status = "completed")
        exerciseDataClass(rcompExplicit, rcompExplicit.copy(), rcompDefault)

        val rfDefault = ResponseStreamEvent.ResponseFailed(id = "r1", type = "response.failed")
        assertNull(rfDefault.error)
        val rfExplicit = ResponseStreamEvent.ResponseFailed(id = "r1", type = "response.failed", error = "something broke")
        exerciseDataClass(rfExplicit, rfExplicit.copy(), rfDefault)

        val riDefault = ResponseStreamEvent.ResponseIncomplete(id = "r1", type = "response.incomplete")
        assertNull(riDefault.reason)
        val riExplicit = ResponseStreamEvent.ResponseIncomplete(id = "r1", type = "response.incomplete", reason = "length")
        exerciseDataClass(riExplicit, riExplicit.copy(), riDefault)

        val unkDefault = ResponseStreamEvent.Unknown(eventType = null, rawJson = "{}")
        assertNull(unkDefault.eventType)
        val unkExplicit = ResponseStreamEvent.Unknown(eventType = "custom", rawJson = "{}")
        exerciseDataClass(unkExplicit, unkExplicit.copy(), unkDefault)
    }

    // ==========================================
    // PronunciationDictionaryModels.kt
    // ==========================================

    @Test
    fun `test PronunciationDictionaryModels data classes`() {
        // PronunciationDictionaryCreateResponse
        val createResp = PronunciationDictionaryCreateResponse(dictionaryId = "dict1")
        exerciseDataClass(createResp, createResp.copy(), PronunciationDictionaryCreateResponse("dict2"))

        // PronunciationDictionaryListResponse
        val listRespDefault = PronunciationDictionaryListResponse()
        assertEquals(0, listRespDefault.dictionaryCount)
        assertTrue(listRespDefault.dictionaries.isEmpty())
        val listRespExplicit = PronunciationDictionaryListResponse(dictionaryCount = 2, dictionaries = listOf("d1", "d2"))
        exerciseDataClass(listRespExplicit, listRespExplicit.copy(), listRespDefault)

        // PronunciationDictionaryUpdateResponse
        val updateRespDefault = PronunciationDictionaryUpdateResponse(dictionaryId = "dict1")
        assertTrue(updateRespDefault.updatedPronunciations.isEmpty())
        val updateRespExplicit = PronunciationDictionaryUpdateResponse(
            dictionaryId = "dict1",
            updatedPronunciations = mapOf("hi" to mapOf("w" to "p"))
        )
        exerciseDataClass(updateRespExplicit, updateRespExplicit.copy(), updateRespDefault)

        // PronunciationDictionaryDeleteResponse
        val delResp = PronunciationDictionaryDeleteResponse(success = true, message = "deleted")
        exerciseDataClass(delResp, delResp.copy(), PronunciationDictionaryDeleteResponse(false, "err"))

        // PronunciationDictionaryData
        val dataDefault = PronunciationDictionaryData()
        assertTrue(dataDefault.pronunciations.isEmpty())
        val dataExplicit = PronunciationDictionaryData(pronunciations = mapOf("hi" to mapOf("w" to "p")))
        exerciseDataClass(dataExplicit, dataExplicit.copy(), dataDefault)
    }
}
