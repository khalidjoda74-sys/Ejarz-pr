package sa.ejarzpro.owner

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val downloadsChannel = "ejarzpro/downloads"

  private fun saveBytesToDownloads(bytes: ByteArray, name: String, mimeType: String): Uri {
    Log.d("PDF_TRACE", "saveToDownloads start name=$name bytes=${bytes.size} mime=$mimeType sdk=${Build.VERSION.SDK_INT}")
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, name)
      put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        put(MediaStore.MediaColumns.RELATIVE_PATH, "Download")
        put(MediaStore.MediaColumns.IS_PENDING, 1)
      }
    }
    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
      ?: throw IllegalStateException("Failed to create download entry")
    Log.d("PDF_TRACE", "saveToDownloads insert uri=$uri")

    try {
      contentResolver.openOutputStream(uri)?.use { stream ->
        stream.write(bytes)
        stream.flush()
        Log.d("PDF_TRACE", "saveToDownloads write success uri=$uri")
      } ?: throw IllegalStateException("Failed to open output stream")

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val readyValues = ContentValues().apply {
          put(MediaStore.MediaColumns.IS_PENDING, 0)
        }
        contentResolver.update(uri, readyValues, null, null)
      }
      Log.d("PDF_TRACE", "saveToDownloads success uri=$uri")
      return uri
    } catch (e: Exception) {
      try {
        contentResolver.delete(uri, null, null)
      } catch (_: Exception) {
      }
      throw e
    }
  }

  private fun safePdfFileName(name: String): String {
    val cleaned = name.trim().replace(Regex("""[\\/:*?"<>|]"""), "_")
    val withExtension = if (cleaned.lowercase().endsWith(".pdf")) cleaned else "$cleaned.pdf"
    return withExtension.ifBlank { "document.pdf" }
  }

  private fun writePdfToCache(bytes: ByteArray, name: String): Uri {
    val dir = File(cacheDir, "pdf_open")
    if (!dir.exists()) {
      dir.mkdirs()
    }
    dir.listFiles()?.forEach { file ->
      try {
        file.delete()
      } catch (_: Exception) {
      }
    }

    val file = File(dir, safePdfFileName(name))
    FileOutputStream(file).use { stream ->
      stream.write(bytes)
      stream.flush()
      stream.fd.sync()
    }
    Log.d("PDF_TRACE", "openPdf cache file=${file.absolutePath} bytes=${file.length()}")
    return FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
  }

  private fun openPdfUri(uri: Uri, name: String, mimeType: String) {
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, mimeType)
      clipData = ClipData.newUri(contentResolver, name, uri)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
    }

    val handlers = packageManager.queryIntentActivities(intent, 0)
    for (handler in handlers) {
      grantUriPermission(handler.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    val chooser = Intent.createChooser(intent, "فتح ملف PDF").apply {
      clipData = ClipData.newUri(contentResolver, name, uri)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    startActivity(chooser)
  }

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
              val uri = saveBytesToDownloads(bytes, name, mimeType)
              result.success(uri.toString())
            } catch (e: Exception) {
              Log.e("PDF_TRACE", "saveToDownloads failed: ${e.message}", e)
              result.error("save_failed", e.message, null)
            }
          }
          "openPdf" -> {
            val bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name")
            val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
            if (bytes == null || name.isNullOrBlank()) {
              Log.e("PDF_TRACE", "openPdf bad args name=$name bytesNull=${bytes == null}")
              result.error("bad_args", "Missing bytes or name", null)
              return@setMethodCallHandler
            }
            try {
              val uri = writePdfToCache(bytes, name)
              openPdfUri(uri, name, mimeType)
              Log.d("PDF_TRACE", "openPdf success uri=$uri")
              result.success(uri.toString())
            } catch (e: ActivityNotFoundException) {
              Log.e("PDF_TRACE", "openPdf no viewer: ${e.message}", e)
              result.error("no_viewer", "No PDF viewer app is installed", null)
            } catch (e: Exception) {
              Log.e("PDF_TRACE", "openPdf failed: ${e.message}", e)
              result.error("open_failed", e.message, null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }
}
