package com.ecohub.ecohub

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.ecohub.ecohub/pip"
    private val SETTINGS_CHANNEL = "com.ecohub.ecohub/settings"
    private val MULTICAST_CHANNEL = "com.ecohub.ecohub/multicast"
    private val EXTERNAL_PLAYER_CHANNEL = "com.ecohub.ecohub/external_player"
    private val ACTION_PIP_CONTROL = "com.ecohub.ecohub.PIP_CONTROL"
    private val EXTRA_CONTROL_TYPE = "control_type"

    private var pipChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var autoPipEnabled = false
    private var aspectNum = 16
    private var aspectDen = 9
    private var isPlaying = false
    private var hasPrev = false
    private var hasNext = false
    private var receiverRegistered = false

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_CONTROL) {
                val controlType = intent.getStringExtra(EXTRA_CONTROL_TYPE) ?: return
                pipChannel?.invokeMethod("onPipAction", controlType)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        val filter = IntentFilter(ACTION_PIP_CONTROL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (_: Exception) {}
            receiverRegistered = false
        }
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val actions = mutableListOf<RemoteAction>()
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // 上一集
        if (hasPrev) {
            val prevIntent = Intent(ACTION_PIP_CONTROL).putExtra(EXTRA_CONTROL_TYPE, "prev")
            val pendingIntent = PendingIntent.getBroadcast(this, 1, prevIntent, flags)
            val icon = Icon.createWithResource(this, android.R.drawable.ic_media_previous)
            actions.add(RemoteAction(icon, "上一集", "上一集", pendingIntent))
        }

        // 播放 / 暂停
        val playPauseType = if (isPlaying) "pause" else "play"
        val playPauseIntent = Intent(ACTION_PIP_CONTROL).putExtra(EXTRA_CONTROL_TYPE, playPauseType)
        val playPausePendingIntent = PendingIntent.getBroadcast(this, 2, playPauseIntent, flags)
        val playPauseIcon = Icon.createWithResource(
            this,
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        )
        val playPauseTitle = if (isPlaying) "暂停" else "播放"
        actions.add(RemoteAction(playPauseIcon, playPauseTitle, playPauseTitle, playPausePendingIntent))

        // 下一集
        if (hasNext) {
            val nextIntent = Intent(ACTION_PIP_CONTROL).putExtra(EXTRA_CONTROL_TYPE, "next")
            val pendingIntent = PendingIntent.getBroadcast(this, 3, nextIntent, flags)
            val icon = Icon.createWithResource(this, android.R.drawable.ic_media_next)
            actions.add(RemoteAction(icon, "下一集", "下一集", pendingIntent))
        }

        return actions
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val clampedRational = clampRational(aspectNum, aspectDen)
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(clampedRational)
                    .setActions(buildPipActions())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(autoPipEnabled)
                }
                setPictureInPictureParams(builder.build())
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    } else {
                        false
                    }
                    result.success(supported)
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val num = (call.argument<Int>("numerator") ?: aspectNum).coerceAtLeast(1)
                        val den = (call.argument<Int>("denominator") ?: aspectDen).coerceAtLeast(1)
                        aspectNum = num
                        aspectDen = den
                        val clampedRational = clampRational(num, den)
                        val builder = PictureInPictureParams.Builder()
                            .setAspectRatio(clampedRational)
                            .setActions(buildPipActions())
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            builder.setAutoEnterEnabled(autoPipEnabled)
                        }
                        val success = enterPictureInPictureMode(builder.build())
                        result.success(success)
                    } else {
                        result.success(false)
                    }
                }
                "setAutoPip" -> {
                    autoPipEnabled = call.argument<Boolean>("enabled") ?: false
                    val num = (call.argument<Int>("numerator") ?: aspectNum).coerceAtLeast(1)
                    val den = (call.argument<Int>("denominator") ?: aspectDen).coerceAtLeast(1)
                    aspectNum = num
                    aspectDen = den
                    updatePipParams()
                    result.success(true)
                }
                "updatePipActions" -> {
                    isPlaying = call.argument<Boolean>("isPlaying") ?: isPlaying
                    hasPrev = call.argument<Boolean>("hasPrev") ?: hasPrev
                    hasNext = call.argument<Boolean>("hasNext") ?: hasNext
                    updatePipParams()
                    result.success(true)
                }
                "updateAspectRatio" -> {
                    val num = (call.argument<Int>("numerator") ?: aspectNum).coerceAtLeast(1)
                    val den = (call.argument<Int>("denominator") ?: aspectDen).coerceAtLeast(1)
                    aspectNum = num
                    aspectDen = den
                    updatePipParams()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheSize" -> {
                    var total = getDirSize(cacheDir)
                    externalCacheDir?.let { total += getDirSize(it) }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codeCacheDir?.let { total += getDirSize(it) }
                    }
                    result.success(formatBytes(total))
                }
                "clearCache" -> {
                    deleteDirContents(cacheDir)
                    externalCacheDir?.let { deleteDirContents(it) }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codeCacheDir?.let { deleteDirContents(it) }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "listPlayers" -> {
                    try {
                        result.success(queryExternalVideoPlayers())
                    } catch (_: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "open" -> {
                    val url = call.argument<String>("url") ?: ""
                    val pkg = call.argument<String>("package") ?: ""
                    result.success(openExternalVideo(url, pkg))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MULTICAST_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        if (multicastLock == null) {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            multicastLock = wifiManager?.createMulticastLock("ecohub_dlna_multicast")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (multicastLock?.isHeld != true) {
                            multicastLock?.acquire()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun queryExternalVideoPlayers(): List<Map<String, String>> {
        val pm = packageManager
        val seen = linkedSetOf<String>()
        val out = mutableListOf<Map<String, String>>()
        val probes = listOf(
            Pair("http://example.com/video.mp4", "video/*"),
            Pair("http://example.com/stream.m3u8", "application/vnd.apple.mpegurl"),
            Pair("http://example.com/stream.m3u8", "video/*"),
            Pair("https://example.com/video.mp4", "video/*"),
        )
        for ((sample, mime) in probes) {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(sample), mime)
            }
            val matches = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            for (resolve in matches) {
                val info = resolve.activityInfo ?: continue
                val pkg = info.packageName ?: continue
                if (pkg == applicationContext.packageName) continue
                if (!seen.add(pkg)) continue
                val label = resolve.loadLabel(pm)?.toString()?.trim().orEmpty()
                out.add(mapOf("package" to pkg, "label" to (label.ifEmpty { pkg })))
            }
        }
        out.sortBy { it["label"]?.lowercase(Locale.getDefault()) }
        return out
    }

    private fun openExternalVideo(url: String, packageName: String): Boolean {
        if (url.isBlank()) return false
        val uri = Uri.parse(url)
        val mime = guessVideoMime(url)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (packageName.isNotBlank()) {
                setPackage(packageName)
            }
        }
        return try {
            if (packageName.isBlank()) {
                val chooser = Intent.createChooser(intent, "选择播放器")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(chooser)
            } else {
                startActivity(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun guessVideoMime(url: String): String {
        val lower = url.lowercase(Locale.getDefault())
        return when {
            lower.contains(".m3u8") -> "application/vnd.apple.mpegurl"
            lower.contains(".mpd") -> "application/dash+xml"
            else -> "video/*"
        }
    }

    private fun getDirSize(dir: File?): Long {
        if (dir == null || !dir.exists()) return 0L
        var size = 0L
        val files = dir.listFiles() ?: return 0L
        for (f in files) {
            size += if (f.isDirectory) getDirSize(f) else f.length()
        }
        return size
    }

    private fun deleteDirContents(dir: File?): Boolean {
        if (dir == null || !dir.exists()) return true
        val files = dir.listFiles() ?: return true
        var success = true
        for (f in files) {
            if (f.isDirectory) {
                deleteDirContents(f)
                f.delete()
            } else {
                f.delete()
            }
        }
        return success
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes <= 0) return "0.0 MB"
        if (bytes < 1024 * 1024) {
            val kb = bytes / 1024.0
            return String.format(Locale.US, "%.1f KB", kb)
        }
        val mb = bytes / (1024.0 * 1024.0)
        return String.format(Locale.US, "%.1f MB", mb)
    }

    private fun clampRational(numerator: Int, denominator: Int): Rational {
        // Android requires aspect ratio between 1:2.39 (0.418) and 2.39:1 (2.39)
        var ratio = numerator.toFloat() / denominator.toFloat()
        return if (ratio > 2.38f) {
            Rational(238, 100)
        } else if (ratio < 0.42f) {
            Rational(42, 100)
        } else {
            Rational(numerator, denominator)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                val clampedRational = clampRational(aspectNum, aspectDen)
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(clampedRational)
                    .setActions(buildPipActions())
                enterPictureInPictureMode(builder.build())
            } catch (_: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
