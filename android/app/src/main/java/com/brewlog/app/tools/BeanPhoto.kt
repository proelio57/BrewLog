package com.brewlog.app.tools

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/** Bean photos: downsampled to at most 1024 px and stored as JPEG (quality 80), like BeanPhoto in LabelScanner.swift. */
object BeanPhoto {
    const val MAX_PIXELS = 1024

    /** Loads a picked or captured image, upright and downsampled. */
    fun bitmap(context: Context, uri: Uri): Bitmap? = runCatching {
        if (Build.VERSION.SDK_INT >= 28) {
            // ImageDecoder applies the EXIF orientation and can scale while decoding.
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                val longest = max(info.size.width, info.size.height)
                if (longest > MAX_PIXELS) {
                    val scale = MAX_PIXELS.toDouble() / longest
                    decoder.setTargetSize((info.size.width * scale).roundToInt(), (info.size.height * scale).roundToInt())
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PIXELS) sample *= 2
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            }?.let(::downsampled)
        }
    }.getOrNull()

    fun downsampled(bitmap: Bitmap): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (longest <= MAX_PIXELS) return bitmap
        val scale = MAX_PIXELS.toDouble() / longest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).roundToInt(), (bitmap.height * scale).roundToInt(), true)
    }

    fun jpeg(bitmap: Bitmap): ByteArray = ByteArrayOutputStream().use { out ->
        downsampled(bitmap).compress(Bitmap.CompressFormat.JPEG, 80, out)
        out.toByteArray()
    }
}
