package app.encoresheets.encoresheets

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

internal class LauncherIcons(private val context: Context) {
    private val components = mapOf(
        "classic" to ComponentName(context, "${context.packageName}.LauncherClassic"),
        "midnight" to ComponentName(context, "${context.packageName}.LauncherMidnight"),
        "paper" to ComponentName(context, "${context.packageName}.LauncherPaper"),
    )

    fun active(): String {
        val manager = context.packageManager
        return components.entries.firstOrNull { (id, component) ->
            val state = manager.getComponentEnabledSetting(component)
            state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (id == "classic" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
        }?.key ?: "classic"
    }

    fun setActive(id: String) {
        val selected = requireNotNull(components[id])
        val manager = context.packageManager
        val enabled = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val disabled = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        val flags = PackageManager.DONT_KILL_APP
        if (Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(components.values.map { component ->
                PackageManager.ComponentEnabledSetting(component, if (component == selected) enabled else disabled, flags)
            })
        } else {
            manager.setComponentEnabledSetting(selected, enabled, flags)
            for (component in components.values) {
                if (component != selected) manager.setComponentEnabledSetting(component, disabled, flags)
            }
        }
    }
}
