package com.encoresheets.app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import kotlin.math.roundToInt

class ScoreWindowActivity : Activity() {
    private var document: PdfRenderer? = null
    private var index = 0
    private lateinit var score: ImageView
    private lateinit var position: TextView
    private lateinit var previous: Button
    private lateinit var next: Button
    private var renderedWidth = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = intent.getStringExtra("title") ?: "Score"
        score = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.WHITE)
            contentDescription = title
        }
        position = TextView(this).apply { gravity = Gravity.CENTER }
        previous = Button(this).apply {
            text = "Previous"
            setOnClickListener { showPage(index - 1) }
        }
        next = Button(this).apply {
            text = "Next"
            setOnClickListener { showPage(index + 1) }
        }
        val close = Button(this).apply {
            text = "Close"
            setOnClickListener { finish() }
        }
        val controls = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(previous)
            addView(position, LinearLayout.LayoutParams(0, -2, 1f))
            addView(next)
            addView(close)
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(score, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(controls, LinearLayout.LayoutParams(-1, -2))
        })
        try {
            val file = File(requireNotNull(intent.getStringExtra("path"))).canonicalFile
            val data = File(applicationInfo.dataDir).canonicalPath
            require(file.path.startsWith("$data/"))
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            document = try {
                PdfRenderer(descriptor)
            } catch (error: Exception) {
                descriptor.close()
                throw error
            }
            index = savedInstanceState?.getInt("page")
                ?: (intent.getIntExtra("page", 1) - 1)
            score.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
                if (view.width > 0 && view.width != renderedWidth) showPage(index)
            }
        } catch (_: Exception) {
            position.text = "Score unavailable"
            previous.isEnabled = false
            next.isEnabled = false
        }
    }

    private fun showPage(target: Int) {
        val renderer = document ?: return
        if (renderer.pageCount == 0 || score.width == 0) return
        index = target.coerceIn(0, renderer.pageCount - 1)
        renderedWidth = score.width
        try {
            renderer.openPage(index).use { page ->
                val scale = minOf(2f, 2200f / page.width, 2200f / page.height,
                    score.width.toFloat() / page.width)
                val bitmap = Bitmap.createBitmap(
                    (page.width * scale).roundToInt().coerceAtLeast(1),
                    (page.height * scale).roundToInt().coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888,
                )
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, Matrix().apply { setScale(scale, scale) },
                    PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                score.setImageBitmap(bitmap)
            }
            position.text = "${index + 1} / ${renderer.pageCount}"
            previous.isEnabled = index > 0
            next.isEnabled = index + 1 < renderer.pageCount
        } catch (_: Exception) {
            position.text = "Page unavailable"
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("page", index)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        document?.close()
        super.onDestroy()
    }
}
