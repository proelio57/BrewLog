package com.brewlog.app.tools

import android.content.Context
import android.graphics.Bitmap
import com.brewlog.app.domain.LabelParser
import com.googlecode.tesseract.android.TessBaseAPI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Recognizes the text on a coffee bag with Tesseract on the device (English + German models from tessdata_fast,
 * bundled in assets) and hands the lines to [LabelParser]. Nothing is uploaded. Counterpart of LabelScanner.swift.
 */
object LabelScanner {
    private const val LANGUAGES = "eng+deu"

    suspend fun scan(context: Context, bitmap: Bitmap): LabelParser.Result = withContext(Dispatchers.Default) {
        val lines = recognize(context, bitmap)
        LabelParser.parse(lines)
    }

    /** Text lines with their size and position relative to the photo. */
    fun recognize(context: Context, bitmap: Bitmap): List<LabelParser.Line> {
        val dataDir = installModels(context) ?: return emptyList()
        val api = TessBaseAPI()
        try {
            if (!api.init(dataDir.absolutePath + "/", LANGUAGES)) return emptyList()
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            api.setImage(bitmap)
            api.getUTF8Text() // runs the recognition
            val height = bitmap.height.coerceAtLeast(1).toDouble()
            val lines = mutableListOf<LabelParser.Line>()
            val iterator = api.resultIterator ?: return emptyList()
            try {
                iterator.begin()
                do {
                    val text = iterator.getUTF8Text(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE)?.trim().orEmpty()
                    val box = iterator.getBoundingRect(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE)
                    if (text.isNotEmpty() && box != null) lines += LabelParser.Line(text, box.height() / height, box.top / height)
                } while (iterator.next(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE) && lines.size < 300)
            } finally {
                iterator.delete()
            }
            return lines
        } catch (e: Exception) {
            return emptyList()
        } finally {
            api.recycle()
        }
    }

    /** Tesseract reads its models from files: copy them out of the APK once (and again after an update changed them). */
    private fun installModels(context: Context): File? = runCatching {
        val root = File(context.noBackupFilesDir, "ocr")
        val tessdata = File(root, "tessdata").apply { mkdirs() }
        for (language in LANGUAGES.split("+")) {
            val name = "$language.traineddata"
            val target = File(tessdata, name)
            val size = context.assets.openFd("tessdata/$name").use { it.length }.takeIf { it > 0 }
            if (target.exists() && (size == null || target.length() == size)) continue
            val temp = File(tessdata, "$name.tmp")
            context.assets.open("tessdata/$name").use { input -> temp.outputStream().use { input.copyTo(it) } }
            temp.renameTo(target)
        }
        root
    }.getOrNull()
}
