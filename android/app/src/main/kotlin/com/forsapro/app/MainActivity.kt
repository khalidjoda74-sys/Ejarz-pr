package com.forsapro.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val shellArgs = super.getFlutterShellArgs()
        val needsStableRenderer =
            Build.MANUFACTURER.equals("HUAWEI", ignoreCase = true) &&
                Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q

        if (needsStableRenderer) {
            shellArgs.remove(FlutterShellArgs.ARG_ENABLE_IMPELLER)
            shellArgs.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        }

        return shellArgs
    }
}
