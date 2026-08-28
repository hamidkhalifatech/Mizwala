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

    private val lastAccelerometer = FloatArray(3)
    private val lastMagnetometer = FloatArray(3)
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

        // Flux boussole multi-capteurs haute compatibilité (Rotation Vector, Geomagnetic, Accel+Mag, Orientation)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

                    lastAccelerometerSet = false
                    lastMagnetometerSet = false

                    sensorEventListener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event == null) return

                            var hasAzimuth = false
                            var azimuthDeg = 0.0

                            val type = event.sensor.type

                            if (type == Sensor.TYPE_ROTATION_VECTOR || type == Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) {
                                try {
                                    SensorManager.getRotationMatrixFromVector(rMat, event.values)
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

                                    var deg = Math.toDegrees(orientation[0].toDouble())
                                    if (deg < 0) deg += 360.0
                                    azimuthDeg = deg % 360.0
                                    hasAzimuth = true
                                } catch (_: Exception) {}
                            } else if (type == Sensor.TYPE_ACCELEROMETER) {
                                lastAccelerometer[0] = lastAccelerometer[0] * 0.7f + event.values[0] * 0.3f
                                lastAccelerometer[1] = lastAccelerometer[1] * 0.7f + event.values[1] * 0.3f
                                lastAccelerometer[2] = lastAccelerometer[2] * 0.7f + event.values[2] * 0.3f
                                lastAccelerometerSet = true
                            } else if (type == Sensor.TYPE_MAGNETIC_FIELD) {
                                lastMagnetometer[0] = lastMagnetometer[0] * 0.7f + event.values[0] * 0.3f
                                lastMagnetometer[1] = lastMagnetometer[1] * 0.7f + event.values[1] * 0.3f
                                lastMagnetometer[2] = lastMagnetometer[2] * 0.7f + event.values[2] * 0.3f
                                lastMagnetometerSet = true
                            }

                            if (!hasAzimuth && lastAccelerometerSet && lastMagnetometerSet) {
                                try {
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
                                        var deg = Math.toDegrees(orientation[0].toDouble())
                                        if (deg < 0) deg += 360.0
                                        azimuthDeg = deg % 360.0
                                        hasAzimuth = true
                                    }
                                } catch (_: Exception) {}
                            }

                            if (hasAzimuth) {
                                mainHandler.post {
                                    try {
                                        events?.success(azimuthDeg)
                                    } catch (_: Exception) {}
                                }
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }

                    // Enregistrement exhaustif de tous les capteurs disponibles sur le smartphone
                    val sm = sensorManager
                    if (sm != null) {
                        sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let {
                            sm.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
                        }
                        sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)?.let {
                            sm.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
                        }
                        sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let {
                            sm.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
                        }
                        sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
                            sm.registerListener(sensorEventListener, it, SensorManager.SENSOR_DELAY_UI)
                        }
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
