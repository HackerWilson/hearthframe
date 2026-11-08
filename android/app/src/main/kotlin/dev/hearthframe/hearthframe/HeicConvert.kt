package dev.hearthframe.hearthframe

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Converts HEIC/HEIF to a cached JPEG using the platform decoder.
 * Flutter's image codec (Skia) has no HEIC support, but Android's ImageDecoder
 * (API 28+) does. Runs off the main thread; writes atomically (.part + rename)
 * so a killed conversion never leaves a half-written "valid" cache file.
 */
object HeicConvert {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun convert(srcPath: String, dstPath: String, onDone: (String?, String?) -> Unit) {
        executor.execute {
            try {
                val src = File(srcPath)
                val decoded = if (Build.VERSION.SDK_INT >= 28) {
                    val source = ImageDecoder.createSource(src)
                    ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                        decoder.isMutableRequired = true
                    }
                } else {
                    BitmapFactory.decodeFile(srcPath)
                        ?: throw IllegalStateException("decode failed")
                }
                // ImageDecoder (API 28+) already applies EXIF orientation; the
                // BitmapFactory fallback does not. Rotating again on API 28+
                // would double-apply a 90° orientation (upside down).
                val oriented =
                    if (Build.VERSION.SDK_INT >= 28) decoded else applyExifRotation(srcPath, decoded)
                val dst = File(dstPath)
                dst.parentFile?.mkdirs()
                val tmp = File(dstPath + ".part")
                FileOutputStream(tmp).use { out ->
                    oriented.compress(Bitmap.CompressFormat.JPEG, 92, out)
                    out.fd.sync()
                }
                if (!tmp.renameTo(dst)) {
                    tmp.copyTo(dst, overwrite = true)
                    tmp.delete()
                }
                if (oriented !== decoded) oriented.recycle()
                decoded.recycle()
                main.post { onDone(dstPath, null) }
            } catch (t: Throwable) {
                main.post { onDone(null, t.message ?: "convert failed") }
            }
        }
    }

    private fun applyExifRotation(path: String, bmp: Bitmap): Bitmap {
        return try {
            val exif = ExifInterface(path)
            val o = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
            )
            val degrees = when (o) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (degrees == 0f) bmp else {
                val m = Matrix()
                m.postRotate(degrees)
                Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            }
        } catch (t: Throwable) {
            bmp
        }
    }
}