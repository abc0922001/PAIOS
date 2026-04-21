package page.puzzak.geminilocal

import android.app.Activity
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import androidx.core.content.edit
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class FileAccessPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null
    private lateinit var prefs: SharedPreferences

    companion object {
        private const val CHANNEL = "page.puzzak.geminilocal/file_access"
        private const val REQUEST_PICK_DIR = 4201
        private const val PREF_NAME = "file_access_prefs"
        private const val PREF_TREE_URI = "prompt_dir_uri"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        prefs = binding.applicationContext.getSharedPreferences(PREF_NAME, Activity.MODE_PRIVATE)
        channel.setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    // ── ActivityResultListener ────────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_DIR) return false
        val result = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = data.data!!
        // Take persistent read+write permission so access survives restarts
        activity?.contentResolver?.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        prefs.edit { putString(PREF_TREE_URI, treeUri.toString()) }
        result.success(getDisplayPath(treeUri))
        return true
    }

    // ── Method dispatch ───────────────────────────────────────────────────────

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "getDirectoryDisplayPath" -> getDirectoryDisplayPath(result)
            "hasDirectory" -> result.success(savedTreeUri() != null)
            "writeFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                val content = call.argument<String>("content") ?: ""
                writeFile(name, content, result)
            }
            "readFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                readFile(name, result)
            }
            "listFiles" -> listFiles(result)
            "deleteFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                deleteFile(name, result)
            }
            "renameFile" -> {
                val oldName = call.argument<String>("oldName") ?: return result.error("BAD_ARGS", "oldName missing", null)
                val newName = call.argument<String>("newName") ?: return result.error("BAD_ARGS", "newName missing", null)
                renameFile(oldName, newName, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── SAF operations ────────────────────────────────────────────────────────

    private fun pickDirectory(result: MethodChannel.Result) {
        val act = activity ?: return result.error("NO_ACTIVITY", "No activity attached", null)
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        act.startActivityForResult(intent, REQUEST_PICK_DIR)
    }

    private fun getDirectoryDisplayPath(result: MethodChannel.Result) {
        val uri = savedTreeUri()
        if (uri == null) { result.success(null); return }
        result.success(getDisplayPath(uri))
    }

    private fun writeFile(filename: String, content: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.error("NO_DIR", "No directory selected", null)
        val ctx = activity ?: return result.error("NO_ACTIVITY", "No activity attached", null)
        try {
            val dir = DocumentFile.fromTreeUri(ctx, uri) ?: return result.error("BAD_URI", "Cannot open directory", null)
            // Find existing or create new
            val existing = dir.findFile(filename)
            val file = if (existing != null && !existing.isDirectory) {
                existing
            } else {
                dir.createFile("text/markdown", filename)
                    ?: return result.error("CREATE_FAILED", "Cannot create $filename", null)
            }
            ctx.contentResolver.openOutputStream(file.uri, "wt")?.use { stream ->
                stream.write(content.toByteArray(Charsets.UTF_8))
            } ?: return result.error("WRITE_FAILED", "Cannot open output stream", null)
            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_ERROR", e.message, null)
        }
    }

    private fun readFile(filename: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.error("NO_DIR", "No directory selected", null)
        val ctx = activity ?: return result.error("NO_ACTIVITY", "No activity attached", null)
        try {
            val dir = DocumentFile.fromTreeUri(ctx, uri) ?: return result.error("BAD_URI", "Cannot open directory", null)
            val file = dir.findFile(filename) ?: return result.success(null)
            val content = ctx.contentResolver.openInputStream(file.uri)?.use { stream ->
                stream.bufferedReader(Charsets.UTF_8).readText()
            }
            result.success(content)
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun listFiles(result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(emptyList<String>())
        val ctx = activity ?: return result.success(emptyList<String>())
        try {
            val dir = DocumentFile.fromTreeUri(ctx, uri) ?: return result.success(emptyList<String>())
            val names = dir.listFiles()
                .filter { it.isFile && (it.name?.endsWith(".md", ignoreCase = true) == true) }
                .mapNotNull { it.name }
            result.success(names)
        } catch (e: Exception) {
            result.success(emptyList<String>())
        }
    }

    private fun deleteFile(filename: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(false)
        val ctx = activity ?: return result.success(false)
        try {
            val dir = DocumentFile.fromTreeUri(ctx, uri) ?: return result.success(false)
            val file = dir.findFile(filename) ?: return result.success(false)
            result.success(file.delete())
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun renameFile(oldName: String, newName: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(false)
        val ctx = activity ?: return result.success(false)
        try {
            val dir = DocumentFile.fromTreeUri(ctx, uri) ?: return result.success(false)
            val file = dir.findFile(oldName) ?: return result.success(false)
            result.success(file.renameTo(newName))
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun savedTreeUri(): Uri? {
        val s = prefs.getString(PREF_TREE_URI, null) ?: return null
        return Uri.parse(s)
    }

    private fun getDisplayPath(treeUri: Uri): String {
        // Decode SAF tree URI into a human-readable path, e.g. "Internal Storage › Documents › Prompts"
        val path = treeUri.lastPathSegment ?: return treeUri.toString()
        return path.replace("primary:", "/sdcard/").replace(":", "/")
    }
}
