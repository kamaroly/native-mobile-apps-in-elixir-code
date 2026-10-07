// mob_ocr plugin — Android bridge: receipt photo processing + OCR.
//
// One call does everything off the main thread:
//   1. decode the camera photo, downsampled, and apply its EXIF rotation;
//   2. scale it to max_dim and save it as a JPEG at `dest` (the copy the app
//      keeps — the camera's own file is a temp file in cacheDir);
//   3. run ML Kit text recognition (bundled Latin model — offline);
//   4. run ML Kit barcode scanning for a QR code (eTIMS receipts carry one);
//   5. deliver {:ocr, :result, json} or {:ocr, :error, json} to the caller.
//
// Registered by the generated MobPluginBootstrap (register() + setActivity).
// The native thunks are exported from the sibling zig NIF mob_ocr_nif.zig.
package io.mob.ocr

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object MobOcrBridge : io.mob.plugin.MobActivityAware {
    private var activityRef: WeakReference<Activity>? = null

    // One worker: photos are processed in the order they were taken, and a
    // second full-size bitmap never competes for memory with the first.
    private val worker = Executors.newSingleThreadExecutor()

    @JvmStatic external fun nativeRegister()

    @JvmStatic external fun nativeDeliverResult(pid: Long, json: String)

    @JvmStatic external fun nativeDeliverError(pid: Long, json: String)

    @JvmStatic fun register() = nativeRegister()

    override fun setActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    // Signature matches the zig NIF call: (JLjava/lang/String;)V.
    @JvmStatic
    fun ocr_process(pid: Long, argsJson: String) {
        worker.execute { run(pid, argsJson) }
    }

    private fun run(pid: Long, argsJson: String) {
        var savedPath: String? = null
        try {
            val args = JSONObject(argsJson)
            val src = args.getString("src")
            val dest = args.getString("dest")
            val maxDim = args.optInt("max_dim", 2048)
            val quality = args.optInt("quality", 85)

            val bitmap = loadUpright(src, maxDim)
            File(dest).parentFile?.mkdirs()
            FileOutputStream(dest).use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
            savedPath = dest
            // The camera's temp file has served its purpose.
            File(src).delete()

            val image = InputImage.fromBitmap(bitmap, 0)
            val text = Tasks.await(TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).process(image))
            val qr = findQr(image)

            val out = JSONObject()
            out.put("text", rows(text))
            out.put("qr", qr ?: JSONObject.NULL)
            out.put("path", dest)
            out.put("width", bitmap.width)
            out.put("height", bitmap.height)
            bitmap.recycle()
            nativeDeliverResult(pid, out.toString())
        } catch (e: Throwable) {
            val out = JSONObject()
            out.put("message", e.message ?: e.javaClass.simpleName)
            out.put("path", savedPath ?: JSONObject.NULL)
            nativeDeliverError(pid, out.toString())
        }
    }

    // Decodes with inSampleSize so a 12 MP photo never lands in memory at
    // full size, then rotates per EXIF (camera apps store portrait shots
    // sideways and set the orientation tag instead) and scales to maxDim.
    private fun loadUpright(path: String, maxDim: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) error("not an image")

        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDim) sample *= 2
        val decoded =
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: error("could not decode image")

        val degrees =
            when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        val scale = min(1f, maxDim.toFloat() / max(decoded.width, decoded.height))
        if (degrees == 0f && scale == 1f) return decoded

        val matrix = Matrix().apply {
            postScale(scale, scale)
            postRotate(degrees)
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (upright !== decoded) decoded.recycle()
        return upright
    }

    private fun findQr(image: InputImage): String? {
        val options = BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        val scanner = BarcodeScanning.getClient(options)
        return try {
            Tasks.await(scanner.process(image)).firstOrNull { it.rawValue != null }?.rawValue
        } finally {
            scanner.close()
        }
    }

    // ML Kit groups text into blocks by layout, so on a receipt the item
    // names end up in one block and the prices in another. Rebuild visual
    // rows instead: lines whose vertical centres are close are one row,
    // read left to right. "TOTAL" and "2,450.00" then share a line again,
    // which is what the receipt parser relies on.
    private fun rows(text: Text): String {
        data class Piece(val text: String, val box: Rect)

        val pieces =
            text.textBlocks
                .flatMap { it.lines }
                .mapNotNull { line -> line.boundingBox?.let { Piece(line.text, it) } }
                .sortedBy { it.box.centerY() }

        val rows = mutableListOf<MutableList<Piece>>()
        for (piece in pieces) {
            val row = rows.lastOrNull()
            val fits =
                row != null &&
                    abs(piece.box.centerY() - row.map { it.box.centerY() }.average()) <
                    0.5 * min(piece.box.height(), row.maxOf { it.box.height() })
            if (fits) row!!.add(piece) else rows.add(mutableListOf(piece))
        }

        return rows.joinToString("\n") { row ->
            row.sortedBy { it.box.left }.joinToString("  ") { it.text }
        }
    }
}
