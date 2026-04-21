package page.puzzak.geminilocal

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            flutterEngine.plugins.add(FlutterLocalAiPlugin())
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error registering plugin flutter_local_ai", e)
        }

        try {
            flutterEngine.plugins.add(FileAccessPlugin())
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error registering FileAccessPlugin", e)
        }
    }
}
