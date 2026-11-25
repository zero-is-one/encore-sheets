package app.encoresheets.encoresheets

import android.app.Presentation
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Display
import android.widget.ImageView
import java.io.File
import kotlin.math.roundToInt

internal class ScorePresentation(context: Context, display: Display) :
    Presentation(context, display) {
    private lateinit var image: ImageView
    private var source: String? = null
    private var renderer: PdfRenderer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        image = ImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.BLACK)
        }
        setContentView(image)
    }

    fun showPage(path: String, index: Int) {
        if (path != source) {
            renderer?.close()
            renderer = null
            source = null
            val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = try {
                PdfRenderer(descriptor)
            } catch (error: Exception) {
                descriptor.close()
                throw error
            }
            source = path
        }
        val document = checkNotNull(renderer)
        document.openPage(index.coerceIn(0, document.pageCount - 1)).use { page ->
            val scale = minOf(2400f / page.width, 2400f / page.height, 3f)
            val bitmap = Bitmap.createBitmap(
                (page.width * scale).roundToInt().coerceAtLeast(1),
                (page.height * scale).roundToInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, Matrix().apply { setScale(scale, scale) },
                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            image.setImageBitmap(bitmap)
        }
    }

    override fun onStop() {
        renderer?.close()
        renderer = null
        source = null
        super.onStop()
    }
}
