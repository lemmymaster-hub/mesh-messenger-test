package com.example.mesh_messenger_test

import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.Payload
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ba.noria.nrnmesh/transport")
            .setMethodCallHandler { call, result ->
                if (call.method != "submitBytes") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val endpoint = call.argument<String>("endpointId")
                val bytes = call.argument<ByteArray>("bytes")
                if (endpoint.isNullOrEmpty() || bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_PAYLOAD", "Endpoint and bytes are required.", null)
                    return@setMethodCallHandler
                }

                // Wait for Nearby to accept the submission. The remote app has not acknowledged it.
                try {
                    Nearby.getConnectionsClient(this).sendPayload(endpoint, Payload.fromBytes(bytes))
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { result.error("NEARBY_SEND", it.message, null) }
                        .addOnCanceledListener { result.error("NEARBY_SEND", "Submission canceled.", null) }
                } catch (exception: Exception) {
                    result.error("NEARBY_SEND", exception.message, null)
                }
            }
    }
}
