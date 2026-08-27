package com.mizwala.mizwala

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val WIDGET_CHANNEL = "com.mizwala.mizwala/widget"
    private val COMPASS_CHANNEL = "com.mizwala.mizwala/compass"

    private var sensorManager: SensorManager? = null
    private var rotationSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var magSensor: Sensor? = null

    private var lastAccelerometer = FloatArray(3)
    private var lastMagnetometer = FloatArray(3)
    private var lastAccelerometerSet = false
    private var lastMagnetometerSet = false

    private val rMat = FloatArray(9)
    private val remappedRMat = FloatArray(9)
    private val orientation = FloatArray(3)

    private var sensorEventListener: SensorEventListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal de mise à jour du Widget Android
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                try {
                    val intent = Intent(this, MizwalaWidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        val ids = AppWidgetManager.getInstance(applicationContext).getAppWidgetIds(
                            ComponentName(applicationContext, MizwalaWidgetProvider::class.java)
                        )
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("UPDATE_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Flux haute précision de la boussole et de l'orientation en temps réel (60 FPS)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                    rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                    accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                    magSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

                    sensorEventListener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event == null) return

                            var azimuth = -1.0

                            if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR) {
                                SensorManager.getRotationMatrixFromVector(rMat, event.values)
                                SensorManager.getOrientation(rMat, orientation)
                                
                                // Compensation de l'inclinaison si le téléphone est tenu verticalement
                                if (abs(orientation[1]) > Math.PI / 4) {
                                    SensorManager.remapCoordinateSystem(
                                        rMat,
                                        SensorManager.AXIS_X,
                                        SensorManager.AXIS_Z,
                                        remappedRMat
                                    )
                                    SensorManager.getOrientation(remappedRMat, orientation)
                                }
                                
                                azimuth = Math.toDegrees(orientation[0].toDouble())
                            } else {
                                if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                                    System.arraycopy(event.values, 0, lastAccelerometer, 0, event.values.size)
                                    lastAccelerometerSet = true
                                } else if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
                                    System.arraycopy(event.values, 0, lastMagnetometer, 0, event.values.size)
                                    lastMagnetometerSet = true
                                }
                                if (lastAccelerometerSet && lastMagnetometerSet) {
                                    if (SensorManager.getRotationMatrix(rMat, null, lastAccelerometer, lastMagnetometer)) {
                                        SensorManager.getOrientation(rMat, orientation)
                                        if (abs(orientation[1]) > Math.PI / 4) {
                                            SensorManager.remapCoordinateSystem(
                                                rMat,
                                                SensorManager.AXIS_X,
                                                SensorManager.AXIS_Z,
                                                remappedRMat
                                            )
                                            SensorManager.getOrientation(remappedRMat, orientation)
                                        }
                                        azimuth = Math.toDegrees(orientation[0].toDouble())
                                    }
                                }
                            }

                            if (azimuth >= -180.0) {
                                if (azimuth < 0) azimuth += 360.0
                                val finalAzimuth = azimuth % 360.0
                                mainHandler.post {
                                    events?.success(finalAzimuth)
                                }
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }

                    if (rotationSensor != null) {
                        sensorManager?.registerListener(sensorEventListener, rotationSensor, SensorManager.SENSOR_DELAY_GAME)
                    }
                    if (accelSensor != null && magSensor != null) {
                        sensorManager?.registerListener(sensorEventListener, accelSensor, SensorManager.SENSOR_DELAY_GAME)
                        sensorManager?.registerListener(sensorEventListener, magSensor, SensorManager.SENSOR_DELAY_GAME)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    sensorEventListener?.let { sensorManager?.unregisterListener(it) }
                    sensorEventListener = null
                }
            }
        )
    }

    override fun onDestroy() {
        sensorEventListener?.let { sensorManager?.unregisterListener(it) }
        super.onDestroy()
    }
}
