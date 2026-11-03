package com.example.breederfinderapp

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.breederfinderapp/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToGallery") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    val success = saveImageToGallery(filePath)
                    if (success) {
                        result.success(true)
                    } else {
                        result.error("SAVE_FAILED", "Failed to save image to gallery", null)
                    }
                } else {
                    result.error("INVALID_PATH", "File path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveImageToGallery(filePath: String): Boolean {
        try {
            val srcFile = File(filePath)
            if (!srcFile.exists()) return false

            val currentTimeMillis = System.currentTimeMillis()
            val fileName = "BreederFinder_${currentTimeMillis}.jpg"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_DCIM + "/BreederFinder")
                    put(MediaStore.Images.Media.DATE_ADDED, currentTimeMillis / 1000)
                    put(MediaStore.Images.Media.DATE_TAKEN, currentTimeMillis)
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }

                val resolver = contentResolver
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return false

                resolver.openOutputStream(uri)?.use { out ->
                    srcFile.inputStream().use { input ->
                        input.copyTo(out)
                    }
                }

                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)

                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(uri.toString()),
                    arrayOf("image/jpeg")
                ) { _, _ -> }

                return true
            } else {
                val dcimDir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
                    "BreederFinder"
                )
                if (!dcimDir.exists()) {
                    dcimDir.mkdirs()
                }

                val destFile = File(dcimDir, fileName)
                srcFile.copyTo(destFile, overwrite = true)

                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(destFile.absolutePath),
                    arrayOf("image/jpeg")
                ) { _, _ -> }

                val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                    data = Uri.fromFile(destFile)
                }
                sendBroadcast(intent)
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}
