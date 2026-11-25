package com.tjpro.app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Updater channel for sideloaded installs ("tj_pro/updater").
 *
 * - canInstallPackages: whether the app may install unknown apps.
 * - openInstallSettings: opens the per-app unknown-sources settings page.
 * - installApk(path): fires ACTION_INSTALL_PACKAGE for a downloaded APK
 *   through FileProvider, so Android treats it as an update (same package,
 *   same key, higher versionCode) and keeps the app's data.
 * - downloadApk(url, fileName): enqueues via Android DownloadManager (system
 *   process — survives app background/kill, shows notification, auto-resumes).
 *   Returns the system download ID.
 * - downloadStatus(downloadId): polls DownloadManager for status/progress.
 *   Returns map: {status: "running"|"success"|"failed"|"pending"|"paused",
 *   bytesDownloaded, bytesTotal, localUri, reason} — reason is the
 *   DownloadManager COLUMN_REASON (PAUSED_*/ERROR_* code, -1 if none).
 * - removeDownload(downloadId): removes the entry and its file
 *   (Build 13 cleanup for the update-download reconciliation).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "tj_pro/updater"

    // Share & Earn referral links ("tj_pro/referral"): the https App
    // Link (nigraantv.xyz/apps/tj-pro?ref=CODE) and the custom scheme
    // (tjpro://ref/CODE), both declared in AndroidManifest.xml.
    // - getInitialLink: the VIEW intent that launched the activity.
    // - onLink (native -> Dart): a link that arrived via onNewIntent
    //   while the app was already running (singleTop).
    // - getInstallReferrer: intentionally NOT implemented yet
    //   (ready-to-add). Dart treats notImplemented as "no referrer".
    //   To add it: add `implementation("com.android.installreferrer:installreferrer:2.2")`
    //   to android/app/build.gradle.kts dependencies, then answer
    //   this method with InstallReferrerClient's getInstallReferrer()
    //   string (it carries `ref=CODE` from the Play Store URL).
    private val referralChannelName = "tj_pro/referral"
    private var referralChannel: MethodChannel? = null
    private var launchLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(canInstall)
                    }
                    "openInstallSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("NO_PATH", "Missing APK path", null)
                            return@setMethodCallHandler
                        }
                        val apkFile = File(path)
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileProvider",
                            apkFile,
                        )
                        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                            data = uri
                            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "downloadApk" -> {
                        val url = call.argument<String>("url")
                        val fileName = call.argument<String>("fileName") ?: "tj-pro-update.apk"
                        if (url == null) {
                            result.error("NO_URL", "Missing download URL", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            // Build 13 (point #18): destination
                            // hygiene — a stale partial/complete
                            // file at the fixed destination makes
                            // DownloadManager fail the NEW enqueue
                            // with ERROR_FILE_ALREADY_EXISTS. The
                            // Dart side reconciles first (a live
                            // download is never re-enqueued), so a
                            // file found here is an orphan: delete
                            // it before enqueueing.
                            try {
                                val destDir = getExternalFilesDir(
                                    Environment.DIRECTORY_DOWNLOADS
                                )
                                if (destDir != null) {
                                    val stale = File(destDir, fileName)
                                    if (stale.exists()) stale.delete()
                                }
                            } catch (_: Exception) {
                                // Hygiene is best-effort; the
                                // enqueue below surfaces real errors.
                            }
                            val request = DownloadManager.Request(Uri.parse(url)).apply {
                                setTitle("TJ Pro Update")
                                setDescription("Downloading update...")
                                setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                                setDestinationInExternalFilesDir(
                                    this@MainActivity,
                                    Environment.DIRECTORY_DOWNLOADS,
                                    fileName,
                                )
                                setAllowedOverMetered(true)
                                setAllowedOverRoaming(false)
                            }
                            val downloadId = dm.enqueue(request)
                            result.success(downloadId)
                        } catch (e: Exception) {
                            result.error("DOWNLOAD_FAILED", e.message, null)
                        }
                    }
                    "downloadStatus" -> {
                        try {
                            // Phase 0 (#34): Dart's StandardMessageCodec
                            // sends a realistic (small) download id as a
                            // Java Integer, NOT a Long. The old code read
                            // it as Long BEFORE this try block, so the
                            // checkcast threw ClassCastException on EVERY
                            // poll and the in-app update banner froze at
                            // 0.0 MB. Read it as a Number, INSIDE the try,
                            // so any parse failure becomes result.error
                            // instead of crashing the handler.
                            val downloadId =
                                (call.argument<Any>("downloadId") as? Number)?.toLong()
                            if (downloadId == null) {
                                result.error("NO_ID", "Missing download ID", null)
                                return@setMethodCallHandler
                            }
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val query = DownloadManager.Query().setFilterById(downloadId)
                            val cursor = dm.query(query)
                            if (cursor.moveToFirst()) {
                                val statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                                val downloadedIdx = cursor.getColumnIndex(
                                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                                )
                                val totalIdx = cursor.getColumnIndex(
                                    DownloadManager.COLUMN_TOTAL_SIZE_BYTES
                                )
                                val uriIdx = cursor.getColumnIndex(
                                    DownloadManager.COLUMN_LOCAL_URI
                                )
                                // Build 13 (point #18): the REASON
                                // column — why a download is paused
                                // (PAUSED_* codes) or failed
                                // (ERROR_* codes / HTTP status). The
                                // pre-Build-13 handler never read it,
                                // so a silently paused download (e.g.
                                // roaming disallowed) looked frozen
                                // forever. -1 when unavailable.
                                val reasonIdx = cursor.getColumnIndex(
                                    DownloadManager.COLUMN_REASON
                                )
                                val reason = if (reasonIdx >= 0) {
                                    cursor.getInt(reasonIdx)
                                } else {
                                    -1
                                }
                                val status = when (cursor.getInt(statusIdx)) {
                                    DownloadManager.STATUS_SUCCESSFUL -> "success"
                                    DownloadManager.STATUS_FAILED -> "failed"
                                    DownloadManager.STATUS_RUNNING -> "running"
                                    DownloadManager.STATUS_PENDING -> "pending"
                                    DownloadManager.STATUS_PAUSED -> "paused"
                                    else -> "unknown"
                                }
                                val map = mapOf(
                                    "status" to status,
                                    "bytesDownloaded" to cursor.getLong(downloadedIdx),
                                    "bytesTotal" to cursor.getLong(totalIdx),
                                    "localUri" to (cursor.getString(uriIdx) ?: ""),
                                    "reason" to reason,
                                )
                                cursor.close()
                                result.success(map)
                            } else {
                                cursor.close()
                                result.success(mapOf("status" to "not_found"))
                            }
                        } catch (e: Exception) {
                            result.error("QUERY_FAILED", e.message, null)
                        }
                    }
                    "removeDownload" -> {
                        // Build 13 (point #18): removes a
                        // DownloadManager entry AND its (partial)
                        // file — the cleanup half of the Dart
                        // side's enqueue-time reconciliation.
                        // Without it a failed entry + its file
                        // stayed forever and poisoned retries.
                        try {
                            val downloadId =
                                (call.argument<Any>("downloadId") as? Number)?.toLong()
                            if (downloadId == null) {
                                result.error("NO_ID", "Missing download ID", null)
                                return@setMethodCallHandler
                            }
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val removed = dm.remove(downloadId)
                            result.success(removed > 0)
                        } catch (e: Exception) {
                            result.error("REMOVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Share & Earn: referral deep-link channel (see field docs).
        launchLink = intent?.dataString
        referralChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            referralChannelName,
        )
        referralChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> result.success(launchLink)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = intent.dataString
        if (data != null) {
            launchLink = data
            referralChannel?.invokeMethod("onLink", data)
        }
    }
}
