package com.brewlog.app.ui.components

import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.RoastLevel

/** Background tint from light honey to roasted umber. Same colours as BeanPlaceholder on iOS. */
fun roastTint(roast: RoastLevel): Color = when (roast) {
    RoastLevel.LIGHT -> Color(0.86f, 0.67f, 0.40f)
    RoastLevel.MEDIUM_LIGHT -> Color(0.76f, 0.53f, 0.29f)
    RoastLevel.MEDIUM -> Color(0.64f, 0.42f, 0.22f)
    RoastLevel.MEDIUM_DARK -> Color(0.47f, 0.30f, 0.17f)
    RoastLevel.DARK -> Color(0.31f, 0.20f, 0.13f)
}

/** The bean's photo, or a drawn bean tinted by the roast level when there is none. */
@Composable
fun BeanThumbnail(beanId: String?, roast: RoastLevel, size: Dp = 44.dp, photo: ByteArray? = null, zoomable: Boolean = false) {
    val repo = LocalContainer.current.repository
    val version by repo.photoVersion.collectAsStateWithLifecycle()
    val bytes = photo ?: remember(beanId, version) { beanId?.let(repo::beanPhoto) }
    val image = remember(bytes) { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val shape = RoundedCornerShape(size * 0.22f)
    var showFull by remember { mutableStateOf(false) }
    if (image != null) {
        val click = if (zoomable) Modifier.clickable(onClickLabel = "Show photo") { showFull = true } else Modifier
        Image(image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(size).clip(shape).then(click))
        if (showFull) BeanPhotoViewer(image) { showFull = false }
    } else {
        BeanPlaceholder(roast, Modifier.size(size).clip(shape))
    }
}

/** A bean's photo full screen: pinch to zoom, drag when zoomed, double tap to reset, tap or back to close. */
@Composable
fun BeanPhotoViewer(image: ImageBitmap, onClose: () -> Unit) {
    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            Image(
                image, contentDescription = "Bean photo", contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onDoubleTap = { scale = 1f; offset = Offset.Zero },
                            onTap = { if (scale == 1f) onClose() },
                        )
                    }
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 6f)
                            offset = if (scale == 1f) Offset.Zero else offset + pan
                        }
                    }
                    .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y),
            )
            IconButton(onClick = onClose, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp)) {
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = Color.White)
            }
        }
    }
}

@Composable
fun BeanPlaceholder(roast: RoastLevel, modifier: Modifier = Modifier) {
    val tint = roastTint(roast)
    Box(modifier.background(tint.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(28.dp).rotate(28f)) {
            val w = size.width * 0.6f
            val h = size.height * 0.85f
            val left = (size.width - w) / 2
            val top = (size.height - h) / 2
            drawOval(Brush.verticalGradient(listOf(tint, tint.copy(alpha = 0.8f))), Offset(left, top), androidx.compose.ui.geometry.Size(w, h))
            // The bean's crease.
            val path = androidx.compose.ui.graphics.Path().apply {
                moveTo(size.width / 2, top + h * 0.08f)
                cubicTo(left + w * 0.3f, top + h * 0.4f, left + w * 0.7f, top + h * 0.6f, size.width / 2, top + h * 0.92f)
            }
            drawPath(path, Color.Black.copy(alpha = 0.35f), style = Stroke(width = size.minDimension * 0.06f, cap = StrokeCap.Round))
        }
    }
}
