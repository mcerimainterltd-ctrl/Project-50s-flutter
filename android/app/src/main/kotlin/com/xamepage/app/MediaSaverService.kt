package com.xamepage.app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

object MediaSaverService {

    fun saveFromUrl(context: Context, url: String, fileName: String, mimeType: String): Boolean {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout    = 60_000
            connection.connect()
            val input: InputStream = connection.inputStream

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ — use MediaStore (no permissions needed)
                val collection = when {
                    mimeType.startsWith("image") -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    mimeType.startsWith("video") -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else                          -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }
                val folder = when {
                    mimeType.startsWith("image") -> "Pictures/XamePage"
                    mimeType.startsWith("video") -> "Movies/XamePage"
                    else                          -> "Download/XamePage"
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE,    mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                    put(MediaStore.MediaColumns.IS_PENDING,   1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(collection, values) ?: return false
                resolver.openOutputStream(uri)?.use { output ->
                    input.copyTo(output)
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } else {
                // Android 9 and below — write to external storage directly
                val dir = when {
                    mimeType.startsWith("image") -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                    mimeType.startsWith("video") -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                    else                          -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                }
                val xameDir = java.io.File(dir, "XamePage").apply { mkdirs() }
                val file = java.io.File(xameDir, fileName)
                file.outputStream().use { output -> input.copyTo(output) }
                // Notify media scanner
                android.media.MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf(mimeType), null)
            }
            input.close()
            connection.disconnect()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
