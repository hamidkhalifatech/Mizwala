package com.mizwala.mizwala

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.*
import kotlin.math.*

class MizwalaWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TICK = "com.mizwala.mizwala.ACTION_WIDGET_TICK"

        // Constantes astronomiques Marrakech (100% identiques à prayer_times.dart)
        const val LAT = 31.6295
        const val LNG = -7.9811
        const val TZ = 1.0 // UTC+1 fixe
        const val FAJR_ANGLE = 19.0
        const val ISHA_ANGLE = 17.0
        const val ASR_FACTOR = 1.0

        fun toRad(d: Double): Double = d * Math.PI / 180.0
        fun toDeg(r: Double): Double = r * 180.0 / Math.PI
        fun fixAngle(a: Double): Double {
            var res = a % 360.0
            if (res < 0) res += 360.0
            return res
        }
        fun fixHour(h: Double): Double {
            var res = h % 24.0
            if (res < 0) res += 24.0
            return res
        }

        fun julianDate(year: Int, month: Int, day: Int): Double {
            var y = year
            var m = month
            if (m <= 2) {
                y -= 1
                m += 12
            }
            val a = y / 100
            val b = 2 - a + (a / 4)
            return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + day + b - 1524.5
        }

        data class SunPos(val decl: Double, val eqt: Double)

        fun sunPosition(jd: Double): SunPos {
            val d = jd - 2451545.0
            val g = fixAngle(357.529 + 0.98560028 * d)
            val q = fixAngle(280.459 + 0.98564736 * d)
            val l = fixAngle(q + 1.915 * sin(toRad(g)) + 0.020 * sin(toRad(2 * g)))
            val e = 23.439 - 0.00000036 * d
            var ra = toDeg(atan2(cos(toRad(e)) * sin(toRad(l)), cos(toRad(l)))) / 15.0
            ra = fixHour(ra)
            val eqt = q / 15.0 - ra
            val decl = toDeg(asin(sin(toRad(e)) * sin(toRad(l))))
            return SunPos(decl, eqt)
        }

        fun hourAngle(angleDeg: Double, lat: Double, decl: Double): Double {
            val term = (-sin(toRad(angleDeg)) - sin(toRad(lat)) * sin(toRad(decl))) /
                    (cos(toRad(lat)) * cos(toRad(decl)))
            val c = max(-1.0, min(1.0, term))
            return toDeg(acos(c)) / 15.0
        }

        fun asrAngle(lat: Double, decl: Double, factor: Double): Double {
            val alt = toDeg(atan(1.0 / (factor + tan(toRad(abs(lat - decl))))))
            return -alt
        }

        data class PrayerTimesData(
            val fajr: Double,
            val sunrise: Double,
            val dhuhr: Double,
            val asr: Double,
            val maghrib: Double,
            val isha: Double
        )

        fun computePrayerTimes(year: Int, month: Int, day: Int): PrayerTimesData {
            val jd = julianDate(year, month, day)
            val (decl, eqt) = sunPosition(jd)
            val dhuhr = fixHour(12.0 + TZ - (LNG / 15.0) - eqt)
            val fajr = fixHour(dhuhr - hourAngle(FAJR_ANGLE, LAT, decl))
            val sunrise = fixHour(dhuhr - hourAngle(0.833, LAT, decl))
            val asr = fixHour(dhuhr + hourAngle(asrAngle(LAT, decl, ASR_FACTOR), LAT, decl))
            val maghrib = fixHour(dhuhr + hourAngle(0.833, LAT, decl))
            val isha = fixHour(dhuhr + hourAngle(ISHA_ANGLE, LAT, decl))
            return PrayerTimesData(fajr, sunrise, dhuhr, asr, maghrib, isha)
        }

        fun angleFromTop(t: Double, dhuhr: Double): Double {
            return fixAngle((t - dhuhr) * 15.0)
        }

        fun lerpColor(c1: Int, c2: Int, f: Float): Int {
            val a = (Color.alpha(c1) + (Color.alpha(c2) - Color.alpha(c1)) * f).toInt()
            val r = (Color.red(c1) + (Color.red(c2) - Color.red(c1)) * f).toInt()
            val g = (Color.green(c1) + (Color.green(c2) - Color.green(c1)) * f).toInt()
            val b = (Color.blue(c1) + (Color.blue(c2) - Color.blue(c1)) * f).toInt()
            return Color.argb(a, r, g, b)
        }

        fun getSkyColor(t: Double, times: PrayerTimesData, condition: String): Int {
            val night = Color.rgb(14, 17, 22)
            val day = Color.rgb(61, 138, 199)
            val sunset = Color.rgb(232, 130, 58)

            val base: Int = if (t >= times.isha || t < times.fajr) {
                night
            } else if (t < times.sunrise) {
                val f = ((t - times.fajr) / (times.sunrise - times.fajr)).coerceIn(0.0, 1.0).toFloat()
                lerpColor(night, day, f)
            } else {
                val preSunset = times.maghrib - 1.0
                if (t < preSunset) {
                    day
                } else if (t < times.maghrib) {
                    val f = ((t - preSunset) / (times.maghrib - preSunset)).coerceIn(0.0, 1.0).toFloat()
                    lerpColor(day, sunset, f)
                } else {
                    val f = ((t - times.maghrib) / (times.isha - times.maghrib)).coerceIn(0.0, 1.0).toFloat()
                    lerpColor(sunset, night, f)
                }
            }

            if (condition == "clear") return base

            val gray = Color.rgb(100, 110, 120)
            val storm = Color.rgb(60, 66, 78)
            val target = if (condition == "storm") storm else gray
            return lerpColor(base, target, 0.75f)
        }

        // Lecture ultra-sécurisée des SharedPreferences de Flutter (supporte Long, Int, Double, String)
        fun readPrefNumber(context: Context, keySuffix: String, defaultVal: Double): Double {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val fullKey = "flutter.$keySuffix"
            try {
                if (prefs.contains(fullKey)) {
                    val v = prefs.all[fullKey]
                    if (v is Number) return v.toDouble()
                    if (v is String) return v.toDoubleOrNull() ?: defaultVal
                }
            } catch (_: Exception) {}
            return defaultVal
        }

        fun readPrefBoolean(context: Context, keySuffix: String, defaultVal: Boolean): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val fullKey = "flutter.$keySuffix"
            try {
                if (prefs.contains(fullKey)) {
                    val v = prefs.all[fullKey]
                    if (v is Boolean) return v
                    if (v is String) return v.toBoolean()
                }
            } catch (_: Exception) {}
            return defaultVal
        }

        fun readPrefString(context: Context, keySuffix: String): String? {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val fullKey = "flutter.$keySuffix"
            try {
                if (prefs.contains(fullKey)) {
                    return prefs.all[fullKey]?.toString()
                }
            } catch (_: Exception) {}
            return null
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
        scheduleNextTick(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle?) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = android.content.ComponentName(context, MizwalaWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
        scheduleNextTick(context)
    }

    private fun scheduleNextTick(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, MizwalaWidgetProvider::class.java).apply { action = ACTION_TICK }
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            // Prochaine mise à jour à la minute suivante exacte
            val nextMinute = (System.currentTimeMillis() / 60000 + 1) * 60000
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC, nextMinute, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC, nextMinute, pendingIntent)
            }
        } catch (_: Exception) {}
    }

    private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 200
        val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 200

        val density = context.resources.displayMetrics.density
        val widthPx = max(200, (minWidth * density).toInt())
        val heightPx = max(200, (minHeight * density).toInt())
        val targetSize = min(widthPx, heightPx).coerceIn(300, 1000)

        val bitmap = renderMizwalaDial(context, targetSize, targetSize)

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val views = RemoteViews(context.packageName, R.layout.mizwala_widget_layout).apply {
            setImageViewBitmap(R.id.widget_dial_image, bitmap)
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            setOnClickPendingIntent(R.id.widget_dial_image, pendingIntent)
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun renderMizwalaDial(context: Context, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val scale = width / 340f
        val cx = width / 2f
        val cy = height / 2f
        val r = 133f * scale
        val discRadius = 75f * scale

        // Date et heure Marrakech (UTC+1 fixe)
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        cal.add(Calendar.HOUR_OF_DAY, 1)

        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val day = cal.get(Calendar.DAY_OF_MONTH)
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)
        val second = cal.get(Calendar.SECOND)

        val currentHourDec = hour + minute / 60.0 + second / 3600.0
        val times = computePrayerTimes(year, month, day)

        // Récupération sécurisée des réglages utilisateur Flutter
        val sleepEnabled = readPrefBoolean(context, "sleep_enabled", true)
        val bH = readPrefNumber(context, "sleep_bedtime_hour", 23.0).toInt()
        val bM = readPrefNumber(context, "sleep_bedtime_minute", 0.0).toInt()
        val wH = readPrefNumber(context, "sleep_wakeup_hour", 6.0).toInt()
        val wM = readPrefNumber(context, "sleep_wakeup_minute", 30.0).toInt()

        val sleepBedtime = bH + bM / 60.0
        val sleepWakeup = wH + wM / 60.0

        var currentTemp = 24
        var maxTemp = 28
        var minTemp = 18
        var condition = "clear"

        val weatherJsonStr = readPrefString(context, "mizwala_cached_weather")
        if (weatherJsonStr != null) {
            try {
                val json = JSONObject(weatherJsonStr)
                currentTemp = json.optDouble("currentTemp", 24.0).roundToInt()
                maxTemp = json.optDouble("maxTemp", 28.0).roundToInt()
                minTemp = json.optDouble("minTemp", 18.0).roundToInt()
                condition = json.optString("conditionType", "clear")
            } catch (_: Exception) {}
        }

        // Fond sombre
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B0B0E")
            style = Paint.Style.FILL
        }
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), 32f * scale, 32f * scale, bgPaint)

        fun getPt(angleDeg: Double, currentR: Float = r): PointF {
            val rad = angleDeg * Math.PI / 180.0
            return PointF(
                (cx + currentR * sin(rad)).toFloat(),
                (cy - currentR * cos(rad)).toFloat()
            )
        }

        // 1. Cercle guide subtil
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1AFFFFFF")
            style = Paint.Style.STROKE
            strokeWidth = 1.0f * scale
        }
        canvas.drawCircle(cx, cy, r, ringPaint)

        // 2. Arc Diurne Fixe (Lever du Soleil -> Maghrib en Bleu Nuit #1E3A5F)
        val aSunrise = angleFromTop(times.sunrise, times.dhuhr)
        val aMaghrib = angleFromTop(times.maghrib, times.dhuhr)
        val daySweep = ((aMaghrib - aSunrise + 360.0) % 360.0).toFloat()
        val dayStartAngle = (aSunrise - 90.0).toFloat()

        val dayArcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1E3A5F")
            style = Paint.Style.STROKE
            strokeWidth = 6.5f * scale
            strokeCap = Paint.Cap.ROUND
        }
        val dayOval = RectF(cx - r, cy - r, cx + r, cy + r)
        canvas.drawArc(dayOval, dayStartAngle, daySweep, false, dayArcPaint)

        // 3. Arc de Sommeil Indigo (épaisseur diminuée de 50% : 6.5px)
        if (sleepEnabled) {
            val aStart = angleFromTop(sleepBedtime, times.dhuhr)
            val aEnd = angleFromTop(sleepWakeup, times.dhuhr)
            val sweep = ((aEnd - aStart + 360.0) % 360.0).toFloat()
            val startAngle = (aStart - 90.0).toFloat()

            val sleepArcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#5E5CE6")
                style = Paint.Style.STROKE
                strokeWidth = 6.5f * scale // 50% plus fin
                strokeCap = Paint.Cap.ROUND
            }
            val oval = RectF(cx - r, cy - r, cx + r, cy + r)
            canvas.drawArc(oval, startAngle, sweep, false, sleepArcPaint)

            // Poignées de Sommeil (proportionnelles : r=5.5px)
            val sPt = getPt(aStart)
            val ePt = getPt(aEnd)
            for (p in listOf(sPt, ePt)) {
                val fillP = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#0B0B0E"); style = Paint.Style.FILL }
                val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#5E5CE6")
                    style = Paint.Style.STROKE
                    strokeWidth = 1.8f * scale
                }
                canvas.drawCircle(p.x, p.y, 5.5f * scale, fillP)
                canvas.drawCircle(p.x, p.y, 5.5f * scale, strokeP)
            }

            // Durée de sommeil badge
            val durDec = (sleepWakeup - sleepBedtime + 24.0) % 24.0
            val durH = durDec.toInt()
            val durM = ((durDec - durH) * 60.0).roundToInt()
            val durStr = if (durM > 0) "${durH}h${durM.toString().padStart(2, '0')}" else "${durH}h"

            val aMid = (aStart + sweep / 2.0) % 360.0
            val badgePt = getPt(aMid, r - 18f * scale)

            val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = 9.5f * scale
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textAlign = Paint.Align.CENTER
            }
            val textBounds = Rect()
            badgeTextPaint.getTextBounds(durStr, 0, durStr.length, textBounds)

            val pillW = textBounds.width() + 12f * scale
            val pillH = textBounds.height() + 6f * scale
            val pillRect = RectF(badgePt.x - pillW / 2f, badgePt.y - pillH / 2f, badgePt.x + pillW / 2f, badgePt.y + pillH / 2f)

            val badgeBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#E65E5CE6")
                style = Paint.Style.FILL
            }
            canvas.drawRoundRect(pillRect, 100f, 100f, badgeBgPaint)
            canvas.drawText(durStr, badgePt.x, badgePt.y + textBounds.height() / 2f - 1f, badgeTextPaint)
        }

        // 3. Repères des 5 prières Teal (diminués de 50% : r=4.5px)
        val prayerList = listOf(times.fajr, times.sunrise, times.asr, times.maghrib, times.isha)
        val tealPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#30B0C7")
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * scale
        }
        val pFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B0B0E")
            style = Paint.Style.FILL
        }
        for (pTime in prayerList) {
            val a = angleFromTop(pTime, times.dhuhr)
            val pt = getPt(a)
            canvas.drawCircle(pt.x, pt.y, 4.5f * scale, pFillPaint)
            canvas.drawCircle(pt.x, pt.y, 4.5f * scale, tealPaint)
        }

        // 4. Dohr (Ambre au sommet diminué de 50% : r=4.5px)
        val aDohr = angleFromTop(times.dhuhr, times.dhuhr)
        val ptDohr = getPt(aDohr)
        val amberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FF9F0A")
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * scale
        }
        canvas.drawCircle(ptDohr.x, ptDohr.y, 4.5f * scale, pFillPaint)
        canvas.drawCircle(ptDohr.x, ptDohr.y, 4.5f * scale, amberPaint)

        // 5. Curseur Soleil / Lune (agrandi de 30% : r=12px, noyau=6.5px, halo lumineux)
        val aNow = angleFromTop(currentHourDec, times.dhuhr)
        val ptNow = getPt(aNow)
        val isDay = currentHourDec >= times.sunrise && currentHourDec < times.maghrib
        val curColor = if (isDay) Color.parseColor("#FF9F0A") else Color.parseColor("#C7D2E0")

        if (isDay) {
            val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#33FF9F0A")
                style = Paint.Style.FILL
            }
            canvas.drawCircle(ptNow.x, ptNow.y, 16f * scale, haloPaint)
        }

        val curRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = curColor
            style = Paint.Style.STROKE
            strokeWidth = 1.6f * scale
        }
        val curCorePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = curColor
            style = Paint.Style.FILL
        }
        canvas.drawCircle(ptNow.x, ptNow.y, 12f * scale, curRingPaint)
        canvas.drawCircle(ptNow.x, ptNow.y, 6.5f * scale, curCorePaint)

        // 6. Disque Central Dynamique (Ciel temps réel)
        val skyColor = getSkyColor(currentHourDec, times, condition)
        val discPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = skyColor
            style = Paint.Style.FILL
            setShadowLayer(18f * scale, 0f, 4f * scale, Color.parseColor("#80000000"))
        }
        canvas.drawCircle(cx, cy, discRadius, discPaint)

        // Contenu du disque central
        val isSunset = isDay && currentHourDec >= (times.maghrib - 1.0)

        // Symbole météo
        val wxSymbol = when {
            condition == "rain" -> "🌧"
            condition == "storm" -> "⚡"
            condition == "clouds" -> "☁"
            isSunset -> "🌅"
            isDay -> "☀️"
            else -> "🌙"
        }
        val wxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 20f * scale
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(wxSymbol, cx, cy - 28f * scale, wxPaint)

        // Horloge numérique HH:mm
        val clockStr = String.format("%02d:%02d", hour, minute)
        val clockPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 34f * scale
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(clockStr, cx, cy + 8f * scale, clockPaint)

        // Température actuelle
        val tempPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#E6FFFFFF")
            textSize = 14f * scale
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText("${currentTemp}°", cx, cy + 26f * scale, tempPaint)

        // Min / Max
        val hlPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#80FFFFFF")
            textSize = 9.5f * scale
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText("H:${maxTemp}°  L:${minTemp}°", cx, cy + 40f * scale, hlPaint)

        return bitmap
    }
}
