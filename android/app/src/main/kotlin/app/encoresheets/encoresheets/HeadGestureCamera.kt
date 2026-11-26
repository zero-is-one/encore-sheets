package app.encoresheets.encoresheets

import android.app.Activity
import android.graphics.SurfaceTexture
import android.hardware.Camera
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlin.math.abs

@Suppress("DEPRECATION")
internal class HeadGestureCamera(private val activity: Activity, private val sample: (Double?) -> Unit) {
    private var camera: Camera? = null
    private var texture: SurfaceTexture? = null
    private var stopDetector: (() -> Unit)? = null

    fun start() {
        stop()
        val info = Camera.CameraInfo()
        val index = (0 until Camera.getNumberOfCameras()).firstOrNull {
            Camera.getCameraInfo(it, info)
            info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT
        } ?: error("No front camera")
        val opened = Camera.open(index)
        camera = opened
        try {
            val parameters = opened.parameters
            val size = parameters.supportedPreviewSizes.minByOrNull {
                abs(it.width * it.height - 640 * 480)
            } ?: parameters.previewSize
            parameters.setPreviewSize(size.width, size.height)
            parameters.previewFormat = android.graphics.ImageFormat.NV21
            opened.parameters = parameters
            val surface = SurfaceTexture(0)
            texture = surface
            opened.setPreviewTexture(surface)
            val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST).build())
            stopDetector = { detector.close() }
            var busy = false
            var last = 0L
            opened.setPreviewCallback { data, source ->
                val now = android.os.SystemClock.elapsedRealtime()
                if (source != camera || busy || data == null || now - last < 85) return@setPreviewCallback
                busy = true
                last = now
                val rotation = (info.orientation + activity.windowManager.defaultDisplay.rotation * 90) % 360
                val image = InputImage.fromByteArray(data, size.width, size.height, rotation, InputImage.IMAGE_FORMAT_NV21)
                detector.process(image)
                    .addOnSuccessListener { faces ->
                        if (camera == opened) sample(faces.singleOrNull()?.headEulerAngleY?.toDouble())
                    }
                    .addOnFailureListener { if (camera == opened) sample(null) }
                    .addOnCompleteListener { busy = false }
            }
            opened.startPreview()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    fun stop() {
        val opened = camera
        camera = null
        opened?.setPreviewCallback(null)
        opened?.release()
        texture?.release()
        texture = null
        stopDetector?.invoke()
        stopDetector = null
    }
}
