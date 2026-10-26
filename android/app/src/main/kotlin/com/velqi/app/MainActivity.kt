package com.velqi.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val STORAGE_CHANNEL = "com.velqi.app/storage_settings"
    private val NOTIFICATION_CHANNEL = "com.velqi.app/notification_channel"
    private val VISUALIZER_CHANNEL = "com.velqi.app/visualizer"

    // ── REAL audio waveform capture ────────────────────────────────────────────
    // Android's [Visualizer] peers into the audio output mix (session 0) and
    // delivers real waveform bytes of the music that is actually playing — the
    // Android equivalent of the desktop WASAPI loopback. The Flutter side runs
    // the same RMS + energy-flux beat detector, so the wave ring / play button
    // pulse to the REAL beat on both platforms.
    private var visualizer: Visualizer? = null
    private var visualizerSink: EventChannel.EventSink? = null
    private var visualizerRunning = false

    private fun startVisualizerCapture(sessionId: Int) {
        if (visualizerRunning) return
        visualizerRunning = true
        try {
            // Bind to the app's own audio session (the ExoPlayer that is
            // actually playing the music). Session 0 (output mix) fails on
            // emulators like BlueStacks with initCheck -3; the player's own
            // session works everywhere.
            val viz = Visualizer(sessionId)
            val maxSize = Visualizer.getCaptureSizeRange()[1]
            viz.captureSize = minOf(1024, maxSize)
            viz.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer,
                        waveform: ByteArray,
                        samplingRate: Int
                    ) {
                        // Deliver raw 8-bit waveform bytes ~40/s. Convert to
                        // UNSIGNED (0..255, 128 = silence) so the Dart side
                        // computes RMS with a single convention.
                        val ui8 = ByteArray(waveform.size)
                        for (i in waveform.indices) {
                            ui8[i] = (waveform[i].toInt() and 0xff).toByte()
                        }
                        visualizerSink?.success(ui8)
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer,
                        fft: ByteArray,
                        samplingRate: Int
                    ) {
                        // Not used — waveform carries the real RMS.
                    }
                },
                Visualizer.getMaxCaptureRate() / 2,
                true, // waveform
                false // fft
            )
            viz.enabled = true
            visualizer = viz
        } catch (e: Exception) {
            visualizerSink?.error("VZ_START", e.message ?: "visualizer failed", null)
            visualizerRunning = false
        }
    }

    private fun stopVisualizerCapture() {
        visualizerRunning = false
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        }
        visualizer = null
        visualizerSink = null
    }

    companion object {
        // Must match AudioServiceConfig.androidNotificationChannelId /
        // androidNotificationChannelName in lib/services/audio_handler.dart
        const val MEDIA_CHANNEL_ID = "com.velqi.app.audio"
        const val MEDIA_CHANNEL_NAME = "Velqi Notification"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VISUALIZER_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    visualizerSink = events
                    val sessionId = (arguments as? Number)?.toInt() ?: 0
                    startVisualizerCapture(sessionId)
                }

                override fun onCancel(arguments: Any?) {
                    stopVisualizerCapture()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openStorageSettings") {
                    openStorageSettings()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "configureChannel") {
                    configureMediaNotificationChannel()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Ensures the media-control notification channel exists with HIGH
     * importance and is not stuck in a disabled state.
     *
     * audio_service creates its channel with IMPORTANCE_LOW (no status-bar
     * icon, silent section of the shade — easy to miss) and ONLY when the
     * channel is null, so if we create it first with HIGH importance ours
     * wins. On Android 13+ a channel created while POST_NOTIFICATIONS was
     * denied stays blocked even after the user grants the permission
     * (known Android 13 gotcha) — deleting and recreating it after the
     * grant clears that state. Must therefore run AFTER the permission is
     * granted.
     */
    private fun configureMediaNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(MEDIA_CHANNEL_ID)
        if (existing == null || existing.importance < NotificationManager.IMPORTANCE_DEFAULT) {
            nm.deleteNotificationChannel(MEDIA_CHANNEL_ID)
            val channel = NotificationChannel(
                MEDIA_CHANNEL_ID,
                MEDIA_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.setShowBadge(true)
            channel.description = "Controles de reproducción de música"
            nm.createNotificationChannel(channel)
        }
    }

    private fun openStorageSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+: Open "All files access" settings for this app
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } else {
            // Android 10 and below: Open app settings
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }
}
