package com.pureread.pureread

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Bridges PureRead's Flutter TTS channels (`com.pureread.app/tts` and
 * `com.pureread.app/tts/events`) to Android's native [TextToSpeech],
 * [AudioManager] focus lifecycle, and [TtsPlaybackService].
 */
class TtsChannelHandler(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, TtsPlaybackService.Delegate {

    companion object {
        private const val METHOD_CHANNEL = "com.pureread.app/tts"
        private const val EVENT_CHANNEL = "com.pureread.app/tts/events"

        private const val MIN_RATE = 0.5
        private const val MAX_RATE = 2.5
        private const val DEFAULT_RATE = 1.0

        private const val MIN_PITCH = 0.5
        private const val MAX_PITCH = 2.0
        private const val DEFAULT_PITCH = 1.0
    }

    private val appContext: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val audioManager: AudioManager? =
        appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private val speechAudioAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private var eventSink: EventChannel.EventSink? = null
    private var tts: TextToSpeech? = null
    private var isInitialized: Boolean = false
    private var isDisposed: Boolean = false
    private var activeEngineId: String? = null
    private var selectedVoiceId: String? = null
    private var speechRate: Float = DEFAULT_RATE.toFloat()
    private var pitch: Float = DEFAULT_PITCH.toFloat()

    private var activeUtteranceId: String? = null
    private var initGeneration: Long = 0L
    private val pendingInitResults = mutableListOf<MethodChannel.Result>()
    private var pendingSetEngineResult: MethodChannel.Result? = null

    private var isPlayingAudio: Boolean = false
    private var hasAudioFocus: Boolean = false
    private var pausedByTransientFocusLoss: Boolean = false
    private var audioFocusRequest: AudioFocusRequest? = null

    private var lastBookTitle: String? = null
    private var lastChapterTitle: String? = null

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        mainHandler.post {
            handleAudioFocusChange(focusChange)
        }
    }

    private val utteranceListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            mainHandler.post {
                if (isDisposed || utteranceId == null || utteranceId != activeUtteranceId) {
                    return@post
                }
                sendEvent(
                    mapOf(
                        "type" to "start",
                        "utteranceId" to utteranceId,
                    ),
                )
            }
        }

        override fun onDone(utteranceId: String?) {
            mainHandler.post {
                if (isDisposed || utteranceId == null || utteranceId != activeUtteranceId) {
                    return@post
                }
                activeUtteranceId = null
                sendEvent(
                    mapOf(
                        "type" to "complete",
                        "utteranceId" to utteranceId,
                    ),
                )
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            dispatchUtteranceError(utteranceId, "TTS synthesis error")
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            dispatchUtteranceError(utteranceId, "TTS synthesis error ($errorCode)")
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) {
            // Intentional stop/flush clears activeUtteranceId before invoking tts.stop().
        }

        override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            mainHandler.post {
                if (isDisposed || utteranceId == null || utteranceId != activeUtteranceId) {
                    return@post
                }
                sendEvent(
                    mapOf(
                        "type" to "progress",
                        "utteranceId" to utteranceId,
                        "start" to start,
                        "end" to end,
                    ),
                )
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        TtsPlaybackService.setDelegate(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMediaAction(action: String) {
        if (isDisposed) return
        when (action) {
            "pause" -> {
                haltSpeechOnly()
                isPlayingAudio = false
                if (!pausedByTransientFocusLoss) {
                    abandonAudioFocus()
                }
                TtsPlaybackService.updatePaused(appContext, lastBookTitle, lastChapterTitle)
                sendEvent(mapOf("type" to "mediaAction", "action" to "pause"))
            }

            "stop" -> {
                haltSpeechOnly()
                isPlayingAudio = false
                pausedByTransientFocusLoss = false
                abandonAudioFocus()
                TtsPlaybackService.stopPlayback()
                sendEvent(mapOf("type" to "mediaAction", "action" to "stop"))
            }

            else -> {
                sendEvent(mapOf("type" to "mediaAction", "action" to action))
            }
        }
    }

    override fun onBecomingNoisy() {
        if (isDisposed) return
        haltSpeechOnly()
        isPlayingAudio = false
        pausedByTransientFocusLoss = false
        abandonAudioFocus()
        TtsPlaybackService.updatePaused(appContext, lastBookTitle, lastChapterTitle)
        sendEvent(mapOf("type" to "mediaAction", "action" to "pause"))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed) {
            result.error("TTS_DISPOSED", "TTS handler has been disposed.", null)
            return
        }
        when (call.method) {
            "initialize" -> handleInitialize(result)
            "getEngines" -> result.success(queryEngines())
            "setEngine" -> handleSetEngine(call, result)
            "getVoices" -> result.success(queryVoices())
            "setVoice" -> result.success(applyVoice(call.arg("voiceId")))
            "setSpeechRate" -> {
                val rawRate = call.arg<Number>("rate")?.toDouble() ?: DEFAULT_RATE
                val clamped = rawRate.coerceIn(MIN_RATE, MAX_RATE).toFloat()
                speechRate = clamped
                runCatching { tts?.setSpeechRate(clamped) }
                TtsPlaybackService.updateSpeechRate(clamped)
                result.success(null)
            }

            "setPitch" -> {
                val rawPitch = call.arg<Number>("pitch")?.toDouble() ?: DEFAULT_PITCH
                val clamped = rawPitch.coerceIn(MIN_PITCH, MAX_PITCH).toFloat()
                pitch = clamped
                runCatching { tts?.setPitch(clamped) }
                result.success(null)
            }

            "speak" -> result.success(handleSpeak(call))
            "stop" -> {
                handleStop()
                result.success(null)
            }

            "pauseNotification" -> {
                handlePauseNotification(call)
                result.success(null)
            }

            "updateMetadata" -> {
                handleUpdateMetadata(call)
                result.success(null)
            }

            "shutdown" -> {
                shutdownInternal()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        TtsPlaybackService.setDelegate(null)
        shutdownInternal()
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        if (isInitialized && tts != null) {
            result.success(
                mapOf(
                    "available" to true,
                    "engine" to (activeEngineId ?: runCatching { tts?.defaultEngine }.getOrNull()),
                    "error" to null,
                ),
            )
            return
        }

        val alreadyPending = pendingInitResults.isNotEmpty()
        pendingInitResults.add(result)
        if (alreadyPending) {
            return
        }

        startTtsEngine(enginePackage = activeEngineId, isExplicitSwitch = false)
    }

    private fun handleSetEngine(call: MethodCall, result: MethodChannel.Result) {
        val engineId = call.arg<String>("engineId")?.trim()
        if (engineId.isNullOrEmpty()) {
            result.success(false)
            return
        }
        if (isInitialized && tts != null && activeEngineId == engineId) {
            result.success(true)
            return
        }

        pendingSetEngineResult?.success(false)
        pendingSetEngineResult = result
        failPendingInitResults("Engine switched before initialization finished")

        selectedVoiceId = null
        startTtsEngine(enginePackage = engineId, isExplicitSwitch = true)
    }

    private fun startTtsEngine(enginePackage: String?, isExplicitSwitch: Boolean) {
        val generation = ++initGeneration
        haltSpeechOnly()
        isInitialized = false
        val previousTts = tts
        tts = null
        runCatching { previousTts?.shutdown() }

        var createdTts: TextToSpeech? = null
        val listener = TextToSpeech.OnInitListener { status ->
            mainHandler.post {
                if (isDisposed || generation != initGeneration) {
                    runCatching { createdTts?.shutdown() }
                    return@post
                }

                val readyTts = createdTts
                if (status == TextToSpeech.SUCCESS && readyTts != null) {
                    tts = readyTts
                    isInitialized = true
                    activeEngineId = enginePackage ?: runCatching { readyTts.defaultEngine }.getOrNull()
                    configureReadyTts(readyTts)

                    if (isExplicitSwitch) {
                        val setResult = pendingSetEngineResult
                        pendingSetEngineResult = null
                        setResult?.success(true)
                    } else {
                        completePendingInitResults(
                            available = true,
                            engine = activeEngineId,
                            error = null,
                        )
                    }
                } else {
                    runCatching { createdTts?.shutdown() }
                    tts = null
                    isInitialized = false
                    if (isExplicitSwitch) {
                        val setResult = pendingSetEngineResult
                        pendingSetEngineResult = null
                        setResult?.success(false)
                    } else {
                        completePendingInitResults(
                            available = false,
                            engine = null,
                            error = "TTS initialization failed (status=$status)",
                        )
                    }
                }
            }
        }

        try {
            createdTts = if (enginePackage.isNullOrEmpty()) {
                TextToSpeech(appContext, listener)
            } else {
                TextToSpeech(appContext, listener, enginePackage)
            }
        } catch (t: Throwable) {
            tts = null
            isInitialized = false
            if (isExplicitSwitch) {
                val setResult = pendingSetEngineResult
                pendingSetEngineResult = null
                setResult?.success(false)
            } else {
                completePendingInitResults(
                    available = false,
                    engine = null,
                    error = t.message ?: "Unable to initialize Android TTS",
                )
            }
        }
    }

    private fun configureReadyTts(readyTts: TextToSpeech) {
        runCatching {
            readyTts.setOnUtteranceProgressListener(utteranceListener)
            readyTts.setAudioAttributes(speechAudioAttributes)
            readyTts.setSpeechRate(speechRate)
            readyTts.setPitch(pitch)
            val voiceId = selectedVoiceId
            if (!voiceId.isNullOrBlank()) {
                applyVoice(voiceId)
            }
        }
    }

    private fun queryEngines(): List<Map<String, Any?>> {
        val currentTts = tts
        if (currentTts != null) {
            val defaultEngine = runCatching { currentTts.defaultEngine }.getOrNull()
            val engines = runCatching { currentTts.engines }.getOrNull().orEmpty()
            if (engines.isNotEmpty()) {
                return engines
                    .filter { !it.name.isNullOrBlank() }
                    .sortedByDescending { it.name == defaultEngine }
                    .map { info ->
                        val engineId = info.name.orEmpty()
                        val engineLabel = info.label?.takeIf { it.isNotBlank() } ?: engineId
                        mapOf(
                            "id" to engineId,
                            "label" to engineLabel,
                            "isDefault" to (engineId == defaultEngine),
                        )
                    }
            }
        }

        // Fallback via PackageManager when queried before initialize() completes.
        val pm = appContext.packageManager
        val intent = Intent(TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE)
        val resolveInfos = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentServices(intent, PackageManager.ResolveInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentServices(intent, 0)
            }
        }.getOrNull().orEmpty()

        return resolveInfos.mapNotNull { resolveInfo ->
            val pkg = resolveInfo.serviceInfo?.packageName ?: return@mapNotNull null
            val label = resolveInfo.loadLabel(pm).toString().takeIf { it.isNotBlank() } ?: pkg
            mapOf(
                "id" to pkg,
                "label" to label,
                "isDefault" to false,
            )
        }
    }

    private fun queryVoices(): List<Map<String, Any?>> {
        val currentTts = tts ?: return emptyList()
        if (!isInitialized) return emptyList()

        val voices = runCatching { currentTts.voices }.getOrNull().orEmpty()
        if (voices.isEmpty()) return emptyList()

        return voices
            .filter { !it.name.isNullOrBlank() }
            .sortedWith(
                compareBy<Voice>(
                    { voiceSortPriority(it.locale) },
                    { it.isNetworkConnectionRequired },
                    { it.locale?.toLanguageTag().orEmpty() },
                    { it.name.orEmpty() },
                ),
            )
            .map { voice ->
                val voiceName = voice.name.orEmpty()
                val localeTag = voice.locale?.toLanguageTag().orEmpty()
                mapOf(
                    "id" to voiceName,
                    "name" to formatVoiceDisplayName(voice, voiceName),
                    "locale" to localeTag,
                )
            }
    }

    private fun voiceSortPriority(locale: Locale?): Int {
        if (locale == null) return 3
        val lang = locale.language.lowercase(Locale.ROOT)
        val tag = locale.toLanguageTag().lowercase(Locale.ROOT)
        val isChinese = lang == "zh" ||
            tag.startsWith("zh") ||
            tag.startsWith("cmn") ||
            tag.startsWith("yue")
        if (isChinese) {
            val country = locale.country.uppercase(Locale.ROOT)
            return if (country == "CN" || tag.contains("-hans") || tag.startsWith("cmn-cn")) {
                0
            } else {
                1
            }
        }
        return if (lang == "en") 2 else 3
    }

    private fun formatVoiceDisplayName(voice: Voice, voiceName: String): String {
        val locale = voice.locale ?: return voiceName
        val displayLocale = runCatching {
            locale.getDisplayName(Locale.getDefault())
        }.getOrNull()?.trim().orEmpty()
        return if (displayLocale.isNotEmpty() && !voiceName.contains(displayLocale, ignoreCase = true)) {
            "$displayLocale · $voiceName"
        } else {
            voiceName
        }
    }

    private fun applyVoice(voiceId: String?): Boolean {
        if (voiceId.isNullOrBlank()) return false
        val currentTts = tts ?: return false
        if (!isInitialized) return false

        val targetVoice = runCatching {
            currentTts.voices?.firstOrNull { it.name == voiceId }
        }.getOrNull() ?: return false

        val status = runCatching { currentTts.setVoice(targetVoice) }.getOrDefault(TextToSpeech.ERROR)
        if (status == TextToSpeech.SUCCESS) {
            selectedVoiceId = voiceId
            return true
        }
        return false
    }

    private fun handleSpeak(call: MethodCall): Boolean {
        val rawText = call.arg<String>("text") ?: ""
        val utteranceId = call.arg<String>("utteranceId")?.trim() ?: ""
        val bookTitle = call.arg<String>("bookTitle")
        val chapterTitle = call.arg<String>("chapterTitle")

        if (utteranceId.isEmpty() || rawText.isBlank()) {
            return false
        }
        val currentTts = tts
        if (currentTts == null || !isInitialized) {
            return false
        }

        if (!bookTitle.isNullOrBlank()) {
            lastBookTitle = bookTitle
        }
        if (!chapterTitle.isNullOrBlank()) {
            lastChapterTitle = chapterTitle
        }

        pausedByTransientFocusLoss = false
        if (!requestAudioFocus()) {
            return false
        }

        val maxLen = TextToSpeech.getMaxSpeechInputLength()
        val safeText = if (maxLen > 0 && rawText.length > maxLen) {
            rawText.substring(0, maxLen)
        } else {
            rawText
        }

        activeUtteranceId = utteranceId
        isPlayingAudio = true
        TtsPlaybackService.updatePlaying(
            context = appContext,
            bookTitle = lastBookTitle,
            chapterTitle = lastChapterTitle,
            speechRate = speechRate,
        )

        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }
        runCatching {
            currentTts.setSpeechRate(speechRate)
            currentTts.setPitch(pitch)
        }

        val status = runCatching {
            currentTts.speak(safeText, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        }.getOrDefault(TextToSpeech.ERROR)

        if (status != TextToSpeech.SUCCESS) {
            if (activeUtteranceId == utteranceId) {
                activeUtteranceId = null
            }
            isPlayingAudio = false
            return false
        }
        return true
    }

    private fun handleStop() {
        haltSpeechOnly()
        isPlayingAudio = false
        pausedByTransientFocusLoss = false
        abandonAudioFocus()
        TtsPlaybackService.stopPlayback()
    }

    private fun handlePauseNotification(call: MethodCall) {
        val bookTitle = call.arg<String>("bookTitle")
        val chapterTitle = call.arg<String>("chapterTitle")
        if (!bookTitle.isNullOrBlank()) {
            lastBookTitle = bookTitle
        }
        if (!chapterTitle.isNullOrBlank()) {
            lastChapterTitle = chapterTitle
        }

        haltSpeechOnly()
        isPlayingAudio = false
        if (!pausedByTransientFocusLoss) {
            abandonAudioFocus()
        }
        TtsPlaybackService.updatePaused(
            context = appContext,
            bookTitle = lastBookTitle,
            chapterTitle = lastChapterTitle,
        )
    }

    private fun handleUpdateMetadata(call: MethodCall) {
        val bookTitle = call.arg<String>("bookTitle")
        val chapterTitle = call.arg<String>("chapterTitle")
        val isPlaying = call.arg<Boolean>("isPlaying") ?: isPlayingAudio

        if (!bookTitle.isNullOrBlank()) {
            lastBookTitle = bookTitle
        }
        if (!chapterTitle.isNullOrBlank()) {
            lastChapterTitle = chapterTitle
        }
        TtsPlaybackService.updateMetadataOnly(
            bookTitle = lastBookTitle,
            chapterTitle = lastChapterTitle,
            isPlaying = isPlaying,
        )
    }

    private fun shutdownInternal() {
        initGeneration++
        haltSpeechOnly()
        isInitialized = false
        isPlayingAudio = false
        pausedByTransientFocusLoss = false

        val oldTts = tts
        tts = null
        runCatching { oldTts?.shutdown() }

        abandonAudioFocus()
        TtsPlaybackService.stopPlayback()

        pendingSetEngineResult?.success(false)
        pendingSetEngineResult = null
        failPendingInitResults("TTS shut down")
    }

    private fun haltSpeechOnly() {
        activeUtteranceId = null
        runCatching { tts?.stop() }
    }

    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) return true
        val manager = audioManager ?: return true

        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = audioFocusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(speechAudioAttributes)
                .setWillPauseWhenDucked(true)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(audioFocusListener, mainHandler)
                .build()
                .also { audioFocusRequest = it }
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }

        hasAudioFocus = (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
        return hasAudioFocus
    }

    private fun abandonAudioFocus() {
        val manager = audioManager
        if (manager != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { req ->
                    runCatching { manager.abandonAudioFocusRequest(req) }
                }
            } else {
                @Suppress("DEPRECATION")
                runCatching { manager.abandonAudioFocus(audioFocusListener) }
            }
        }
        hasAudioFocus = false
    }

    private fun handleAudioFocusChange(focusChange: Int) {
        if (isDisposed) return
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                val wasPlaying = isPlayingAudio || activeUtteranceId != null
                hasAudioFocus = false
                pausedByTransientFocusLoss = false
                haltSpeechOnly()
                isPlayingAudio = false
                abandonAudioFocus()
                if (TtsPlaybackService.isSessionActive()) {
                    TtsPlaybackService.updatePaused(appContext, lastBookTitle, lastChapterTitle)
                }
                if (wasPlaying) {
                    sendEvent(mapOf("type" to "mediaAction", "action" to "pause"))
                }
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                val wasPlaying = isPlayingAudio || activeUtteranceId != null
                hasAudioFocus = false
                if (wasPlaying) {
                    pausedByTransientFocusLoss = true
                    haltSpeechOnly()
                    isPlayingAudio = false
                    if (TtsPlaybackService.isSessionActive()) {
                        TtsPlaybackService.updatePaused(appContext, lastBookTitle, lastChapterTitle)
                    }
                    sendEvent(mapOf("type" to "mediaAction", "action" to "pause"))
                }
            }

            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                if (pausedByTransientFocusLoss) {
                    pausedByTransientFocusLoss = false
                    sendEvent(mapOf("type" to "mediaAction", "action" to "resumeFromFocus"))
                }
            }
        }
    }

    private fun dispatchUtteranceError(utteranceId: String?, message: String) {
        mainHandler.post {
            if (isDisposed) return@post
            if (utteranceId == null || utteranceId != activeUtteranceId) {
                return@post
            }
            activeUtteranceId = null
            sendEvent(
                mapOf(
                    "type" to "error",
                    "utteranceId" to utteranceId,
                    "message" to message,
                ),
            )
        }
    }

    private fun completePendingInitResults(
        available: Boolean,
        engine: String?,
        error: String?,
    ) {
        if (pendingInitResults.isEmpty()) return
        val results = pendingInitResults.toList()
        pendingInitResults.clear()
        val payload = mapOf(
            "available" to available,
            "engine" to engine,
            "error" to error,
        )
        results.forEach { it.success(payload) }
    }

    private fun failPendingInitResults(error: String) {
        completePendingInitResults(available = false, engine = null, error = error)
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        if (isDisposed) return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(payload)
        } else {
            mainHandler.post {
                if (!isDisposed) {
                    eventSink?.success(payload)
                }
            }
        }
    }

    private inline fun <reified T> MethodCall.arg(key: String): T? {
        return if (arguments is Map<*, *>) argument<T>(key) else null
    }
}
