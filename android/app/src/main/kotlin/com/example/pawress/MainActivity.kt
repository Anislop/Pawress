package com.example.pawress

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.Executors

/**
 * Hosts the `pawress/updater` channel used by lib/core/app_update.dart: the
 * installed version, and downloading a GitHub release APK into the package
 * installer once it is checked to be a newer build of this app signed with
 * the same key. It also opens the app's page in Android's notification
 * settings for lib/core/updates.dart.
 *
 * The `pawress/intents` channel (lib/core/intents.dart) hands pawchive.pw
 * links opened or shared into the app to Dart, shares an image or offers it
 * to "Set as", opens a downloaded file or its folder, and says whether the
 * network is metered.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var intents: MethodChannel? = null

    /** The link that launched the app, until Dart asks for it. */
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // A recreated activity's intent was already handled.
        if (savedInstanceState == null) pendingLink = linkOf(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkOf(intent) ?: return
        val channel = intents
        if (channel == null) pendingLink = link else channel.invokeMethod("link", link)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(::handle)
        }
        intents = MethodChannel(messenger, INTENTS_CHANNEL).apply {
            setMethodCallHandler(::handleIntents)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        intents?.setMethodCallHandler(null)
        intents = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleIntents(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialLink" -> {
                result.success(pendingLink)
                pendingLink = null
            }
            "shareFile" -> result.success(sendFile(call, Intent.ACTION_SEND, "Share image"))
            "setAs" -> result.success(sendFile(call, Intent.ACTION_ATTACH_DATA, "Set as"))
            "viewFile" -> result.success(viewFile(call))
            "viewFolder" -> result.success(viewFolder(call))
            "isMetered" -> {
                val connectivity = getSystemService(ConnectivityManager::class.java)
                result.success(connectivity?.isActiveNetworkMetered ?: false)
            }
            else -> result.notImplemented()
        }
    }

    /** A link opened on pawchive.pw or text shared into the app. */
    private fun linkOf(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.dataString
        Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
        else -> null
    }

    /** Offers a file from the cache's `shared` folder to other apps. */
    private fun sendFile(call: MethodCall, action: String, title: String): Boolean {
        val path = call.argument<String>("path") ?: return false
        val mime = call.argument<String>("mime") ?: "image/*"
        val folder = File(cacheDir, SHARED_FOLDER).canonicalFile
        val file = File(path).canonicalFile
        if (file.parentFile != folder || !file.isFile) return false
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        val intent = Intent(action).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (action == Intent.ACTION_SEND) {
            intent.setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
        } else {
            intent.setDataAndType(uri, mime).putExtra("mimeType", mime)
        }
        intent.clipData = ClipData.newRawUri(file.name, uri)
        return try {
            startActivity(Intent.createChooser(intent, title))
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Opens a downloaded file, a document in a folder the user picked. */
    private fun viewFile(call: MethodCall): Boolean {
        val uri = call.argument<String>("uri")?.let(Uri::parse) ?: return false
        if (uri.scheme != "content") return false
        val mime = call.argument<String>("mime") ?: contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return tryStart(Intent.createChooser(intent, "Open with"))
    }

    /**
     * Shows a picked download folder in the system file browser. Viewing a
     * directory document is handled by Files on Android 8+; otherwise the
     * folder picker opens there, which still lists the folder's files.
     */
    private fun viewFolder(call: MethodCall): Boolean {
        val tree = call.argument<String>("uri")?.let(Uri::parse) ?: return false
        if (tree.scheme != "content") return false
        val folder = try {
            DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        } catch (_: Exception) {
            return false
        }
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (tryStart(view)) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return tryStart(
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).putExtra(DocumentsContract.EXTRA_INITIAL_URI, folder),
        )
    }

    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appVersion" -> {
                val info = installedPackage()
                result.success(mapOf("name" to (info.versionName ?: ""), "build" to versionCode(info)))
            }
            "installUpdate" -> installUpdate(call, result)
            "notificationSettings" -> result.success(openNotificationSettings())
            else -> result.notImplemented()
        }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installUpdate(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url == null || !isUpdateUrl(url)) {
            result.error("UPDATE_INVALID", "Updates come from GitHub releases only", null)
            return
        }
        executor.execute {
            // Its own folder, emptied first, so only this download is offered.
            val folder = File(cacheDir, UPDATE_FOLDER).apply { deleteRecursively(); mkdirs() }
            val file = File(folder, UPDATE_FILE)
            try {
                download(url, file)
                checkUpdate(file)
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(FileProvider.getUriForFile(this, "$packageName.updates", file), APK_MIME_TYPE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                runOnUiThread {
                    try {
                        startActivity(intent)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("UPDATE_INVALID", "No package installer", null)
                    }
                }
            } catch (error: UpdateRejected) {
                folder.deleteRecursively()
                runOnUiThread { result.error(error.code, error.message, null) }
            } catch (error: Exception) {
                folder.deleteRecursively()
                runOnUiThread { result.error("UPDATE_DOWNLOAD", error.message, null) }
            }
        }
    }

    /** Follows HTTPS redirects within GitHub's hosts and saves the body. */
    private fun download(url: String, file: File) {
        var current = URI(url)
        repeat(MAX_REDIRECTS) {
            if (!isUpdateUrl(current.toString())) throw IOException("Unexpected host")
            val connection = current.toURL().openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.setRequestProperty("User-Agent", "Pawress updater")
                val code = connection.responseCode
                if (code in 300..399) {
                    val location = connection.getHeaderField("Location") ?: throw IOException("Invalid redirect")
                    current = current.resolve(location)
                    return@repeat
                }
                if (code !in 200..299) throw IOException("HTTP $code")
                val total = connection.contentLengthLong.takeIf { it > 0 }
                if (total != null && total > MAX_UPDATE_BYTES) throw IOException("Update too large")
                connection.inputStream.use { input ->
                    file.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        var received = 0L
                        var reported = -1L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            received += count
                            if (received > MAX_UPDATE_BYTES) throw IOException("Update too large")
                            output.write(buffer, 0, count)
                            val step = if (total != null) received * 100 / total else received / (512L * 1024L)
                            if (step != reported) {
                                reported = step
                                val progress = mapOf("received" to received, "total" to total)
                                runOnUiThread { channel?.invokeMethod("progress", progress) }
                            }
                        }
                    }
                }
                return
            } finally {
                connection.disconnect()
            }
        }
        throw IOException("Too many redirects")
    }

    /** Rejects an APK that is not a newer build of this app signed with the same key. */
    private fun checkUpdate(file: File) {
        @Suppress("DEPRECATION")
        val archive = packageManager.getPackageArchiveInfo(file.path, signerFlags())
            ?: throw UpdateRejected("UPDATE_INVALID", "Not an app package")
        val installed = installedPackage()
        if (archive.packageName != packageName) throw UpdateRejected("UPDATE_INVALID", "A different app")
        if (versionCode(archive) <= versionCode(installed)) {
            throw UpdateRejected("UPDATE_NOT_NEWER", "Not newer than the installed build")
        }
        // Some archives report no signers; the installer still compares keys then.
        val incoming = signers(archive)
        val current = signers(installed)
        if (incoming.isNotEmpty() && current.isNotEmpty() && incoming.none(current::contains)) {
            throw UpdateRejected("UPDATE_SIGNATURE", "Signed with a different key")
        }
    }

    @Suppress("DEPRECATION")
    private fun installedPackage(): PackageInfo = packageManager.getPackageInfo(packageName, signerFlags())

    @Suppress("DEPRECATION")
    private fun signerFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    /** Signing certificates, including earlier ones the current key was rotated from. */
    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.let { if (it.hasMultipleSigners()) it.apkContentsSigners else it.signingCertificateHistory }
        } else {
            info.signatures
        }
        return signatures.orEmpty().map { it.toCharsString() }.toSet()
    }

    private class UpdateRejected(val code: String, message: String) : Exception(message)

    companion object {
        private const val CHANNEL = "pawress/updater"
        private const val INTENTS_CHANNEL = "pawress/intents"
        private const val SHARED_FOLDER = "shared"
        private const val UPDATE_FOLDER = "updates"
        private const val UPDATE_FILE = "pawress-update.apk"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val MAX_UPDATE_BYTES = 300L * 1024L * 1024L
        private const val MAX_REDIRECTS = 6

        /** Release assets redirect from github.com to GitHub's download host. */
        private fun isUpdateUrl(value: String): Boolean {
            val uri = try { URI(value) } catch (_: Exception) { return false }
            val host = uri.host ?: return false
            return uri.scheme == "https" &&
                (host == "github.com" || host.endsWith(".githubusercontent.com"))
        }
    }
}
