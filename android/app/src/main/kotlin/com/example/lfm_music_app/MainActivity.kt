package com.example.lfm_music_app

import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.lfm_music_app/external_player"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playWithSystemPlayer") {
                val filePath = call.argument<String>("filePath")
                val isVideo = call.argument<Boolean>("isVideo") ?: false

                if (filePath != null) {
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "Dosya bulunamadı: $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri: Uri = FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            file
                        )

                        val mimeType = if (isVideo) "video/*" else "audio/*"
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        val chooser = Intent.createChooser(intent, if (isVideo) "Videoyu Oynat" else "Müziği Çal")
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                } else {
                    result.error("INVALID_PATH", "Dosya yolu boş olamaz", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
