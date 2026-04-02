package com.lenv.reward

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterActivity() {
	private val channelName = "lenv/app_usage_tracker"
	private val tag = "AppUsageTracker"

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
						val includeIcons = call.argument<Boolean>("includeIcons") ?: true
						result.success(getTopUsedAppsToday(topN, includeIcons))
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

	private fun getTopUsedAppsToday(topN: Int, includeIcons: Boolean): List<Map<String, Any?>> {
		val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
		val debugPackages = listOf(
			"com.instagram.android",
			"com.google.android.youtube",
			"com.whatsapp",
			"com.spotify.music",
		)

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
			val foregroundMs = entry.totalTimeInForeground
			if (foregroundMs > 0L) {
				usageByPackage[pkg] = (usageByPackage[pkg] ?: 0L) + foregroundMs
			}
		}

		val pm = packageManager
		val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
			addCategory(Intent.CATEGORY_LAUNCHER)
		}
		val launcherActivities = pm.queryIntentActivities(launcherIntent, 0)
		Log.d(tag, "Launcher activities discovered: ${launcherActivities.size}")

		val appsByPackage = linkedMapOf<String, Pair<String, Long>>()
		for (activity in launcherActivities) {
			val pkg = activity.activityInfo?.packageName ?: continue
			if (appsByPackage.containsKey(pkg)) continue
			val appName = activity.loadLabel(pm)?.toString()?.ifBlank { pkg } ?: pkg
			val usage = usageByPackage[pkg] ?: 0L
			appsByPackage[pkg] = appName to usage
		}

		for (pkg in debugPackages) {
			val visibleInLauncher = appsByPackage.containsKey(pkg)
			val launchIntentExists = pm.getLaunchIntentForPackage(pkg) != null
			val installed = runCatching {
				pm.getPackageInfo(pkg, 0)
				true
			}.getOrElse { false }
			val usageMinutes = ((usageByPackage[pkg] ?: 0L) / 60000L).toInt()
			Log.d(
				tag,
				"Debug package=$pkg installed=$installed launchIntent=$launchIntentExists " +
					"visibleInLauncher=$visibleInLauncher usageMinutes=$usageMinutes",
			)
		}

		Log.d(tag, "Unique launcher packages after dedupe: ${appsByPackage.size}")

		val sortedApps = appsByPackage
			.asSequence()
			.map { entry -> Triple(entry.key, entry.value.first, entry.value.second) }
			.sortedWith(
				compareByDescending<Triple<String, String, Long>> { it.third }
					.thenBy { it.second.lowercase() }
			)
			.take(topN)
			.toList()

		// Encoding icons for every installed app can stall UI thread on some OEM ROMs.
		// Keep icons for top visible subset and use placeholders for remaining apps.
		val iconBudget = if (includeIcons) {
			when {
				topN <= 10 -> topN
				topN <= 100 -> 40
				else -> 60
			}
		} else {
			0
		}

		return sortedApps
			.mapIndexed { index, (pkg, appName, millis) ->
				val iconBase64 = if (includeIcons && index < iconBudget) {
					runCatching {
						val drawable = pm.getApplicationIcon(pkg)
						drawableToBase64(drawable)
					}.getOrNull()
				} else {
					null
				}

				mapOf(
					"appName" to appName,
					"packageName" to pkg,
					"usageMinutes" to (millis / 60000L).toInt(),
					"appIcon" to iconBase64,
				)
			}
			.toList()
	}

	private fun drawableToBase64(drawable: Drawable): String? {
		val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
		val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
		val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
		val canvas = Canvas(bitmap)
		drawable.setBounds(0, 0, canvas.width, canvas.height)
		drawable.draw(canvas)

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
