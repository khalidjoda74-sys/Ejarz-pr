package com.darvoo.owner

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val downloadsChannel = "darvoo/downloads"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "saveToDownloads" -> {
            val bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name")
            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
            if (bytes == null || name.isNullOrBlank()) {
              Log.e("PDF_TRACE", "saveToDownloads bad args name=$name bytesNull=${bytes == null}")
              result.error("bad_args", "Missing bytes or name", null)
              return@setMethodCallHandler
            }
            try {
              Log.d("PDF_TRACE", "saveToDownloads start name=$name bytes=${bytes.size} mime=$mimeType sdk=${Build.VERSION.SDK_INT}")
              val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                  put(MediaStore.MediaColumns.RELATIVE_PATH, "Download")
                }
              }
              val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
              if (uri == null) {
                Log.e("PDF_TRACE", "saveToDownloads insert returned null")
                result.error("insert_failed", "Failed to create download entry", null)
                return@setMethodCallHandler
              }
              Log.d("PDF_TRACE", "saveToDownloads insert uri=$uri")
              contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
                Log.d("PDF_TRACE", "saveToDownloads write success uri=$uri")
              } ?: run {
                Log.e("PDF_TRACE", "saveToDownloads openOutputStream returned null uri=$uri")
                result.error("stream_failed", "Failed to open output stream", null)
                return@setMethodCallHandler
              }
              Log.d("PDF_TRACE", "saveToDownloads success uri=$uri")
              result.success(uri.toString())
            } catch (e: Exception) {
              Log.e("PDF_TRACE", "saveToDownloads failed: ${e.message}", e)
              result.error("save_failed", e.message, null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }
}
