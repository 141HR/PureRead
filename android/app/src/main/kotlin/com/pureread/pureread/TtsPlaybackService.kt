package com.pureread.pureread

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.view.KeyEvent

/**
 * Foreground media playback service managing PureRead's TTS notification,
 * MediaSession (lockscreen + Bluetooth transport/media button controls),
 * partial wake lock, and noisy-audio disconnect handling.
 */
class TtsPlaybackService : Service() {

    enum class PlaybackStatus {
        STOPPED,
        PLAYING,
        PAUSED,
    }

    interface Delegate {
        fun onMediaAction(action: String)
        fun onBecomingNoisy()
    }

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "pureread_tts_playback"
        private const val NOTIFICATION_CHANNEL_NAME = "朗读播放控制"
        private const val NOTIFICATION_ID = 4201

        private const val ACTION_PLAY = "com.pureread.app.tts.ACTION_PLAY"
        private const val ACTION_PAUSE = "com.pureread.app.tts.ACTION_PAUSE"
        private const val ACTION_NEXT = "com.pureread.app.tts.ACTION_NEXT"
        private const val ACTION_PREV = "com.pureread.app.tts.ACTION_PREV"
        private const val ACTION_STOP = "com.pureread.app.tts.ACTION_STOP"

        private const val REQ_CONTENT = 100
        private const val REQ_PREV = 101
        private const val REQ_PLAY_PAUSE = 102
        private const val REQ_NEXT = 103
        private const val REQ_STOP = 104

        private const val WAKE_LOCK_TAG = "PureRead:TtsWakeLock"
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L

        @Volatile
        private var desiredStatus: PlaybackStatus = PlaybackStatus.STOPPED

        @Volatile
        private var currentBookTitle: String = ""

        @Volatile
        private var currentChapterTitle: String = ""

        @Volatile
        private var currentSpeechRate: Float = 1.0f

        @Volatile
        private var hasPendingForegroundStart: Boolean = false

        @Volatile
        private var activeService: TtsPlaybackService? = null

        @Volatile
        private var delegate: Delegate? = null

        fun setDelegate(newDelegate: Delegate?) {
            delegate = newDelegate
        }

        fun isSessionActive(): Boolean {
            return desiredStatus != PlaybackStatus.STOPPED || activeService != null
        }

        fun updatePlaying(
            context: Context,
            bookTitle: String?,
            chapterTitle: String?,
            speechRate: Float,
        ) {
            desiredStatus = PlaybackStatus.PLAYING
            if (!bookTitle.isNullOrBlank()) {
                currentBookTitle = bookTitle
            }
            if (!chapterTitle.isNullOrBlank()) {
                currentChapterTitle = chapterTitle
            }
            currentSpeechRate = speechRate
            syncOrStart(context)
        }

        fun updatePaused(
            context: Context,
            bookTitle: String?,
            chapterTitle: String?,
        ) {
            desiredStatus = PlaybackStatus.PAUSED
            if (!bookTitle.isNullOrBlank()) {
                currentBookTitle = bookTitle
            }
            if (!chapterTitle.isNullOrBlank()) {
                currentChapterTitle = chapterTitle
            }
            val service = activeService
            if (service != null) {
                service.syncWithCurrentState()
            } else {
                syncOrStart(context)
            }
        }

        fun updateMetadataOnly(
            bookTitle: String?,
            chapterTitle: String?,
            isPlaying: Boolean,
        ) {
            if (!bookTitle.isNullOrBlank()) {
                currentBookTitle = bookTitle
            }
            if (!chapterTitle.isNullOrBlank()) {
                currentChapterTitle = chapterTitle
            }
            if (isSessionActive()) {
                desiredStatus = if (isPlaying) PlaybackStatus.PLAYING else PlaybackStatus.PAUSED
                activeService?.syncWithCurrentState()
            }
        }

        fun updateSpeechRate(speechRate: Float) {
            currentSpeechRate = speechRate
            if (desiredStatus == PlaybackStatus.PLAYING) {
                activeService?.updateMediaSessionStateOnly()
            }
        }

        fun stopPlayback() {
            desiredStatus = PlaybackStatus.STOPPED
            activeService?.stopAndTearDown()
        }

        private fun syncOrStart(context: Context) {
            val service = activeService
            if (service != null) {
                service.syncWithCurrentState()
                return
            }

            val appContext = context.applicationContext
            val intent = Intent(appContext, TtsPlaybackService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    hasPendingForegroundStart = true
                    appContext.startForegroundService(intent)
                } else {
                    appContext.startService(intent)
                }
            } catch (e: Exception) {
                hasPendingForegroundStart = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    e is ForegroundServiceStartNotAllowedException
                ) {
                    return
                }
                if (e is SecurityException || e is IllegalStateException) {
                    return
                }
                throw e
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var notificationManager: NotificationManager? = null
    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var isForegroundStarted: Boolean = false
    private var isNoisyReceiverRegistered: Boolean = false

    private val becomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                mainHandler.post {
                    val activeDelegate = delegate
                    if (activeDelegate != null) {
                        activeDelegate.onBecomingNoisy()
                    } else if (desiredStatus == PlaybackStatus.PLAYING) {
                        desiredStatus = PlaybackStatus.PAUSED
                        syncWithCurrentState()
                    }
                }
            }
        }
    }

    private val mediaSessionCallback = object : MediaSession.Callback() {
        override fun onPlay() {
            delegate?.onMediaAction("play")
        }

        override fun onPause() {
            delegate?.onMediaAction("pause")
        }

        override fun onStop() {
            delegate?.onMediaAction("stop")
        }

        override fun onSkipToNext() {
            delegate?.onMediaAction("next")
        }

        override fun onSkipToPrevious() {
            delegate?.onMediaAction("prev")
        }

        override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
            val keyEvent: KeyEvent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
            }

            if (keyEvent != null) {
                val action = when (keyEvent.keyCode) {
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                    KeyEvent.KEYCODE_HEADSETHOOK -> "toggle"
                    KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
                    KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
                    KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
                    KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
                    KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
                    else -> null
                }
                if (action != null) {
                    if (keyEvent.action == KeyEvent.ACTION_DOWN && keyEvent.repeatCount == 0) {
                        delegate?.onMediaAction(action)
                    }
                    return true
                }
            }
            return super.onMediaButtonEvent(mediaButtonIntent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeService = this
        notificationManager = getSystemService(NotificationManager::class.java)
        ensureNotificationChannel()

        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)?.apply {
            setReferenceCounted(false)
        }

        val sessionAudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        mediaSession = MediaSession(this, "PureReadTtsSession").apply {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                        MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
                )
            }
            setPlaybackToLocal(sessionAudioAttributes)
            setSessionActivity(createMainActivityPendingIntent())
            setCallback(mediaSessionCallback, mainHandler)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val pendingStart = hasPendingForegroundStart
        hasPendingForegroundStart = false

        when (intent?.action) {
            ACTION_PLAY -> delegate?.onMediaAction("play")
            ACTION_PAUSE -> {
                val activeDelegate = delegate
                if (activeDelegate != null) {
                    activeDelegate.onMediaAction("pause")
                } else {
                    desiredStatus = PlaybackStatus.PAUSED
                }
            }
            ACTION_NEXT -> delegate?.onMediaAction("next")
            ACTION_PREV -> delegate?.onMediaAction("prev")
            ACTION_STOP -> {
                val activeDelegate = delegate
                if (activeDelegate != null) {
                    activeDelegate.onMediaAction("stop")
                } else {
                    desiredStatus = PlaybackStatus.STOPPED
                }
            }
        }

        if (desiredStatus == PlaybackStatus.STOPPED) {
            // Balance any prior startForegroundService() call before stopping so Android
            // never raises ForegroundServiceDidNotStartInTimeException.
            if (pendingStart && !isForegroundStarted) {
                startForegroundCompat(buildNotification(isPlaying = false))
            }
            stopAndTearDown()
            return START_NOT_STICKY
        }

        syncWithCurrentState()
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        desiredStatus = PlaybackStatus.STOPPED
        delegate?.onMediaAction("stop")
        stopAndTearDown()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        unregisterNoisyReceiver()
        releaseWakeLock()
        mediaSession?.runCatching {
            isActive = false
            setCallback(null)
            release()
        }
        mediaSession = null
        isForegroundStarted = false
        hasPendingForegroundStart = false
        if (activeService === this) {
            activeService = null
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun syncWithCurrentState() {
        when (desiredStatus) {
            PlaybackStatus.STOPPED -> stopAndTearDown()
            PlaybackStatus.PLAYING -> {
                updateMediaSessionMetadata()
                updateMediaSessionStateOnly()
                acquireWakeLock()
                registerNoisyReceiver()
                val notification = buildNotification(isPlaying = true)
                publishForegroundNotification(notification)
            }
            PlaybackStatus.PAUSED -> {
                updateMediaSessionMetadata()
                updateMediaSessionStateOnly()
                releaseWakeLock()
                unregisterNoisyReceiver()
                val notification = buildNotification(isPlaying = false)
                publishForegroundNotification(notification)
            }
        }
    }

    fun stopAndTearDown() {
        releaseWakeLock()
        unregisterNoisyReceiver()
        updateMediaSessionStateOnly()
        if (isForegroundStarted) {
            runCatching {
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
            isForegroundStarted = false
        } else {
            runCatching {
                notificationManager?.cancel(NOTIFICATION_ID)
            }
        }
        runCatching {
            stopSelf()
        }
    }

    private fun publishForegroundNotification(notification: Notification) {
        if (!isForegroundStarted) {
            startForegroundCompat(notification)
        } else {
            runCatching {
                notificationManager?.notify(NOTIFICATION_ID, notification)
            }
        }
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isForegroundStarted = true
        } catch (e: Exception) {
            isForegroundStarted = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                e is ForegroundServiceStartNotAllowedException
            ) {
                return
            }
            if (e is SecurityException || e is IllegalStateException) {
                return
            }
            throw e
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager ?: return
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "PureRead 后台听书播放控制与锁屏媒体通知"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun updateMediaSessionMetadata() {
        val session = mediaSession ?: return
        val title = currentChapterTitle.ifBlank {
            currentBookTitle.ifBlank { "PureRead 听书" }
        }
        val subtitle = currentBookTitle.ifBlank { "PureRead" }
        val metadata = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, subtitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, subtitle)
            .build()
        session.setMetadata(metadata)
    }

    private fun updateMediaSessionStateOnly() {
        val session = mediaSession ?: return
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_STOP

        val stateCode = when (desiredStatus) {
            PlaybackStatus.PLAYING -> PlaybackState.STATE_PLAYING
            PlaybackStatus.PAUSED -> PlaybackState.STATE_PAUSED
            PlaybackStatus.STOPPED -> PlaybackState.STATE_STOPPED
        }
        val playbackSpeed = if (desiredStatus == PlaybackStatus.PLAYING) {
            currentSpeechRate
        } else {
            0f
        }
        val playbackState = PlaybackState.Builder()
            .setActions(actions)
            .setState(stateCode, PlaybackState.PLAYBACK_POSITION_UNKNOWN, playbackSpeed)
            .build()
        session.setPlaybackState(playbackState)
        session.isActive = desiredStatus != PlaybackStatus.STOPPED
    }

    private fun buildNotification(isPlaying: Boolean): Notification {
        val contentTitle = currentChapterTitle.ifBlank {
            currentBookTitle.ifBlank { "PureRead 听书" }
        }
        val contentText = if (currentChapterTitle.isNotBlank() && currentBookTitle.isNotBlank()) {
            currentBookTitle
        } else if (isPlaying) {
            "正在朗读"
        } else {
            "已暂停"
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val prevAction = buildServiceAction(
            iconRes = android.R.drawable.ic_media_previous,
            title = "上一句",
            action = ACTION_PREV,
            requestCode = REQ_PREV,
        )
        val playPauseAction = buildServiceAction(
            iconRes = if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            },
            title = if (isPlaying) "暂停" else "继续",
            action = if (isPlaying) ACTION_PAUSE else ACTION_PLAY,
            requestCode = REQ_PLAY_PAUSE,
        )
        val nextAction = buildServiceAction(
            iconRes = android.R.drawable.ic_media_next,
            title = "下一句",
            action = ACTION_NEXT,
            requestCode = REQ_NEXT,
        )
        val stopAction = buildServiceAction(
            iconRes = android.R.drawable.ic_menu_close_clear_cancel,
            title = "停止",
            action = ACTION_STOP,
            requestCode = REQ_STOP,
        )

        val mediaStyle = Notification.MediaStyle().apply {
            mediaSession?.sessionToken?.let { setMediaSession(it) }
            setShowActionsInCompactView(0, 1, 2)
        }

        return builder
            .setSmallIcon(android.R.drawable.stat_sys_headset)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setContentIntent(createMainActivityPendingIntent())
            .setDeleteIntent(createServicePendingIntent(ACTION_STOP, REQ_STOP))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(prevAction)
            .addAction(playPauseAction)
            .addAction(nextAction)
            .addAction(stopAction)
            .setStyle(mediaStyle)
            .build()
    }

    private fun buildServiceAction(
        iconRes: Int,
        title: String,
        action: String,
        requestCode: Int,
    ): Notification.Action {
        val pendingIntent = createServicePendingIntent(action, requestCode)
        return Notification.Action.Builder(
            Icon.createWithResource(this, iconRes),
            title,
            pendingIntent,
        ).build()
    }

    private fun createMainActivityPendingIntent(): PendingIntent {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            REQ_CONTENT,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createServicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, TtsPlaybackService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun acquireWakeLock() {
        runCatching {
            val wl = wakeLock ?: return
            wl.acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        runCatching {
            val wl = wakeLock ?: return
            if (wl.isHeld) {
                wl.release()
            }
        }
    }

    private fun registerNoisyReceiver() {
        if (isNoisyReceiverRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(becomingNoisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(becomingNoisyReceiver, filter)
            }
            isNoisyReceiverRegistered = true
        }
    }

    private fun unregisterNoisyReceiver() {
        if (!isNoisyReceiverRegistered) return
        runCatching {
            unregisterReceiver(becomingNoisyReceiver)
        }
        isNoisyReceiverRegistered = false
    }
}
