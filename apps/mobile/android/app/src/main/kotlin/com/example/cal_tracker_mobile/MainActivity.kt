package com.example.cal_tracker_mobile

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.SigningInfo
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "app.bettercalories/mobile_update_installer"
        private const val UPDATE_DIRECTORY = "mobile_updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> result.success(packageManager.canRequestPackageInstalls())
                "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                "installApk" -> installApk(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "permission_settings_unavailable",
                "Android could not open the install permission settings.",
                null,
            )
        }
    }

    private fun installApk(arguments: Any?, result: MethodChannel.Result) {
        if (!packageManager.canRequestPackageInstalls()) {
            result.error(
                "install_permission_required",
                "Install permission has not been granted.",
                null,
            )
            return
        }

        val values = arguments as? Map<*, *>
        val filePath = values?.get("filePath") as? String
        val expectedVersionCode =
            (values?.get("expectedVersionCode") as? Number)?.toLong()
        val expectedSha256 = values?.get("expectedSha256") as? String
        val expectedSizeBytes =
            (values?.get("expectedSizeBytes") as? Number)?.toLong()
        if (
            expectedVersionCode == null ||
            expectedVersionCode <= 0 ||
            expectedSha256 == null ||
            !expectedSha256.matches(Regex("^[a-f0-9]{64}$")) ||
            expectedSizeBytes == null ||
            expectedSizeBytes <= 0
        ) {
            result.error("invalid_arguments", "Invalid APK expectations.", null)
            return
        }

        val apkFile = trustedUpdateFile(filePath)
        if (apkFile == null) {
            result.error(
                "invalid_apk_path",
                "The APK is outside the private update directory.",
                null,
            )
            return
        }
        Thread {
            val validationError = try {
                validateApk(
                    apkFile,
                    expectedVersionCode,
                    expectedSha256,
                    expectedSizeBytes,
                )
            } catch (error: Exception) {
                "apk_invalid"
            }
            runOnUiThread {
                if (validationError != null) {
                    result.error(
                        validationError,
                        "The APK failed native validation.",
                        null,
                    )
                } else {
                    openPackageInstaller(apkFile, result)
                }
            }
        }.start()
    }

    private fun openPackageInstaller(apkFile: File, result: MethodChannel.Result) {
        if (isFinishing || isDestroyed) {
            result.error(
                "installer_unavailable",
                "The activity is no longer available.",
                null,
            )
            return
        }

        val contentUri = try {
            FileProvider.getUriForFile(
                this,
                "$packageName.mobile-update-files",
                apkFile,
            )
        } catch (error: IllegalArgumentException) {
            result.error("invalid_apk_path", "The APK path is not shareable.", null)
            return
        }

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri("BetterCalories update", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(installIntent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "installer_unavailable",
                "Android could not open the package installer.",
                null,
            )
        }
    }

    private fun trustedUpdateFile(filePath: String?): File? {
        if (filePath.isNullOrBlank()) return null
        return try {
            val updateDirectory = File(cacheDir, UPDATE_DIRECTORY).canonicalFile
            val candidate = File(filePath).canonicalFile
            val trustedParent = candidate.parentFile == updateDirectory
            val trustedName = candidate.name.matches(
                Regex("^bettercalories-update-[1-9][0-9]*\\.apk$"),
            )
            candidate.takeIf {
                trustedParent &&
                    trustedName &&
                    it.isFile &&
                    it.canRead() &&
                    it.length() > 0
            }
        } catch (error: IOException) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun validateApk(
        apkFile: File,
        expectedVersionCode: Long,
        expectedSha256: String,
        expectedSizeBytes: Long,
    ): String? {
        if (apkFile.length() != expectedSizeBytes) return "integrity_mismatch"
        val actualSha256 = apkFile.inputStream().use { stream ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
            digest.digest().joinToString("") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }
        }
        if (actualSha256 != expectedSha256) return "integrity_mismatch"

        val archiveInfo = packageManager.getPackageArchiveInfo(
            apkFile.path,
            PackageManager.GET_SIGNING_CERTIFICATES,
        ) ?: return "apk_invalid"
        val installedInfo = try {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        } catch (error: PackageManager.NameNotFoundException) {
            return "package_mismatch"
        }
        if (archiveInfo.packageName != packageName) return "package_mismatch"
        if (
            archiveInfo.longVersionCode != expectedVersionCode ||
            installedInfo.longVersionCode >= expectedVersionCode
        ) {
            return "version_mismatch"
        }
        if (!hasCompatibleSigningIdentity(installedInfo, archiveInfo)) {
            return "signature_mismatch"
        }
        return null
    }

    private fun hasCompatibleSigningIdentity(
        installedInfo: PackageInfo,
        archiveInfo: PackageInfo,
    ): Boolean {
        val installedSigningInfo = installedInfo.signingInfo ?: return false
        val archiveSigningInfo = archiveInfo.signingInfo ?: return false
        if (
            installedSigningInfo.hasMultipleSigners() ||
            archiveSigningInfo.hasMultipleSigners()
        ) {
            return signerDigests(installedSigningInfo, includeHistory = false) ==
                signerDigests(archiveSigningInfo, includeHistory = false)
        }
        val installedHistory = signerDigests(
            installedSigningInfo,
            includeHistory = true,
        )
        val archiveHistory = signerDigests(
            archiveSigningInfo,
            includeHistory = true,
        )
        return installedHistory.intersect(archiveHistory).isNotEmpty()
    }

    private fun signerDigests(
        signingInfo: SigningInfo,
        includeHistory: Boolean,
    ): Set<String> {
        val signers = if (includeHistory) {
            signingInfo.signingCertificateHistory
        } else {
            signingInfo.apkContentsSigners
        }
        return signers.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte ->
                    "%02x".format(byte.toInt() and 0xff)
                }
        }.toSet()
    }
}
