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
 *   bytesDownloaded, bytesTotal, localUri}.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "tj_pro/updater"

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
                        val downloadId = call.argument<Long>("downloadId")
                            ?: call.argument<Int>("downloadId")?.toLong()
                        if (downloadId == null) {
                            result.error("NO_ID", "Missing download ID", null)
                            return@setMethodCallHandler
                        }
                        try {
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
                    else -> result.notImplemented()
                }
            }
    }
}
