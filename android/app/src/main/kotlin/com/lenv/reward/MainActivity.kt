package com.lenv.reward

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterActivity() {
	private val channelName = "lenv/app_usage_tracker"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"isUsagePermissionGranted" -> {
						result.success(isUsagePermissionGranted())
					}

					"openUsageAccessSettings" -> {
						openUsageAccessSettings()
						result.success(true)
					}

					"getTopAppsToday" -> {
						if (!isUsagePermissionGranted()) {
							result.error(
								"PERMISSION_DENIED",
								"PACKAGE_USAGE_STATS permission not granted",
								null,
							)
							return@setMethodCallHandler
						}

						val topN = call.argument<Int>("topN") ?: 5
						result.success(getTopUsedAppsToday(topN))
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun isUsagePermissionGranted(): Boolean {
		val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
		val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			appOps.unsafeCheckOpNoThrow(
				AppOpsManager.OPSTR_GET_USAGE_STATS,
				android.os.Process.myUid(),
				packageName,
			)
		} else {
			@Suppress("DEPRECATION")
			appOps.checkOpNoThrow(
				AppOpsManager.OPSTR_GET_USAGE_STATS,
				android.os.Process.myUid(),
				packageName,
			)
		}

		return mode == AppOpsManager.MODE_ALLOWED
	}

	private fun openUsageAccessSettings() {
		val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		startActivity(intent)
	}

	private fun getTopUsedAppsToday(topN: Int): List<Map<String, Any?>> {
		val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

		val now = System.currentTimeMillis()
		val cal = Calendar.getInstance().apply {
			set(Calendar.HOUR_OF_DAY, 0)
			set(Calendar.MINUTE, 0)
			set(Calendar.SECOND, 0)
			set(Calendar.MILLISECOND, 0)
		}
		val startOfDay = cal.timeInMillis

		val stats = usageStatsManager.queryUsageStats(
			UsageStatsManager.INTERVAL_DAILY,
			startOfDay,
			now,
		) ?: emptyList()

		val usageByPackage = mutableMapOf<String, Long>()
		for (entry in stats) {
			val pkg = entry.packageName ?: continue
			if (pkg == packageName) continue
			val foregroundMs = entry.totalTimeInForeground
			if (foregroundMs > 0L) {
				usageByPackage[pkg] = (usageByPackage[pkg] ?: 0L) + foregroundMs
			}
		}

		val pm = packageManager
		val launchableApps = pm.getInstalledApplications(0)
			.asSequence()
			.filter { app ->
				app.packageName != packageName
					&& pm.getLaunchIntentForPackage(app.packageName) != null
			}
			.map { app ->
				val pkg = app.packageName
				val usage = usageByPackage[pkg] ?: 0L
				val isPureSystem =
					(app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
						&& (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
				Triple(pkg, usage, isPureSystem)
			}
			.toList()

		val preferredPool = run {
			val userApps = launchableApps.filter { !it.third }
			val usedUserApps = userApps.filter { it.second > 0L }

			when {
				usedUserApps.isNotEmpty() -> usedUserApps
				userApps.isNotEmpty() -> userApps
				else -> {
					val usedAnyApps = launchableApps.filter { it.second > 0L }
					if (usedAnyApps.isNotEmpty()) usedAnyApps else launchableApps
				}
			}
		}

		return preferredPool
			.map { pair -> pair.first to pair.second }
			.sortedWith(
				compareByDescending<Pair<String, Long>> { it.second }
					.thenBy { pair ->
						runCatching {
							val appInfo = pm.getApplicationInfo(pair.first, 0)
							pm.getApplicationLabel(appInfo).toString().lowercase()
						}.getOrElse { pair.first.lowercase() }
					}
			)
			.take(topN)
			.map { (pkg, millis) ->
				val appName = runCatching {
					val appInfo = pm.getApplicationInfo(pkg, 0)
					pm.getApplicationLabel(appInfo).toString()
				}.getOrElse { pkg }

				val iconBase64 = runCatching {
					val appInfo: ApplicationInfo = pm.getApplicationInfo(pkg, 0)
					val drawable = pm.getApplicationIcon(appInfo)
					drawableToBase64(drawable)
				}.getOrNull()

				mapOf(
					"appName" to appName,
					"packageName" to pkg,
					"usageMinutes" to (millis / 60000L).toInt(),
					"appIcon" to iconBase64,
				)
			}
	}

	private fun drawableToBase64(drawable: Drawable): String? {
		val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
			drawable.bitmap
		} else {
			val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
			val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
			val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
			val canvas = Canvas(bmp)
			drawable.setBounds(0, 0, canvas.width, canvas.height)
			drawable.draw(canvas)
			bmp
		}

		val output = ByteArrayOutputStream()
		return try {
			bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
			Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
		} catch (_: Exception) {
			null
		} finally {
			output.close()
		}
	}
}
