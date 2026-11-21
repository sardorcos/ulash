package uz.sardor.file_transfer

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNetworkPermission: MethodChannel.Result? = null
    private val permissionCode = 8752
    private val lanPermission = "android.permission.ACCESS_LOCAL_NETWORK"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "uz.sardor.file_transfer/permissions").setMethodCallHandler { call, result ->
            if (call.method != "ensureLocalNetwork") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < 37 ||
                checkSelfPermission(lanPermission) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else if (pendingNetworkPermission != null) {
                result.error("REQUEST_IN_PROGRESS", "A permission request is active.", null)
            } else {
                pendingNetworkPermission = result
                requestPermissions(arrayOf(lanPermission), permissionCode)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int,
        permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            pendingNetworkPermission?.success(grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingNetworkPermission = null
        }
    }
}
