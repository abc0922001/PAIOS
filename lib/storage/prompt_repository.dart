import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'file_access_service.dart';

class PromptRepository {
  final VoidCallback notifyEngine;
  final Future<void> Function(String, String, String)? logEvent;
  bool newPromptsAvailable = false;
  
  Map<String, dynamic> defaultPrompts = {};
  Map<String, dynamic> userPrompts = {};
  
  PromptRepository({required this.notifyEngine, this.logEvent});

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');
    
    // ── Load User Prompts from Hive ─────────────────────────────────────────
    String? storedUserPrompts = box.get("user_prompts");
    if (storedUserPrompts != null) {
      userPrompts = jsonDecode(storedUserPrompts);
    }
    
    // ── Load Default Prompts: cache → bundle ────────────────────────────────
    String? cachedIndex = box.get("cached_prompts_index");
    if (cachedIndex != null) {
      try {
        final decoded = jsonDecode(cachedIndex);
        if (decoded is List) {
          defaultPrompts = { for (var item in decoded) item['id'] : item };
        } else {
          defaultPrompts = decoded;
        }
      } catch (e) {
        if (kDebugMode) print("Error parsing cached prompts: $e");
      }
    } else {
      try {
        String assetIndex = await rootBundle.loadString('assets/prompts/prompts_index.json');
        final decoded = jsonDecode(assetIndex);
        if (decoded is List) {
          defaultPrompts = { for (var item in decoded) item['id'] : item };
        } else {
          defaultPrompts = decoded;
        }
      } catch (e) {
         if (kDebugMode) print("Error parsing asset prompts: $e");
      }
    }
    
    // ── Network refresh (release only) ──────────────────────────────────────
    if (!kDebugMode) {
      try {
        if (logEvent != null) await logEvent!("prompt_repo", "info", "Fetching prompts from $url/assets/prompts/prompts_index.json");
        // NOTE: path includes assets/ prefix — matches the repo directory layout
        final response = await http.get(Uri.parse("$url/assets/prompts/prompts_index.json"));
        if (response.statusCode == 200) {
          if (logEvent != null) await logEvent!("prompt_repo", "info", "Index fetched successfully");
          final onlineData = jsonDecode(response.body);
          Map<String, dynamic> onlineIndex = {};
          
          if (onlineData is List) {
            onlineIndex = { for (var item in onlineData) item['id'] : item };
          } else {
            onlineIndex = onlineData;
          }
          
          if (cachedIndex != response.body) {
            newPromptsAvailable = true;
            notifyEngine();
          }
          
          defaultPrompts = onlineIndex;
          box.put("cached_prompts_index", response.body);
          
          // Download individual .md files for all default prompts
          for (String key in defaultPrompts.keys) {
            final promptGet = await http.get(Uri.parse("$url/assets/prompts/$key.md"));
            if (promptGet.statusCode == 200) {
              defaultPrompts[key]["content"] = promptGet.body;
              box.put("cached_prompt_$key", promptGet.body);
              if (logEvent != null) await logEvent!("prompt_repo", "info", "Downloaded $key.md");
            } else {
              if (logEvent != null) await logEvent!("prompt_repo", "warning", "Failed to download $key.md: ${promptGet.statusCode}");
            }
          }
        } else {
          if (logEvent != null) await logEvent!("prompt_repo", "error", "Failed to fetch prompt index: ${response.statusCode}");
        }
      } catch (e) {
        if (kDebugMode) print("Network failed for prompts, using local. Error: $e");
        if (logEvent != null) await logEvent!("prompt_repo", "error", "Network error: $e");
      }
    }
    
    // ── Ensure all default prompts have content loaded ──────────────────────
    for (String key in defaultPrompts.keys) {
      if (defaultPrompts[key]["content"] == null || defaultPrompts[key]["content"] == "") {
        defaultPrompts[key]["content"] = box.get("cached_prompt_$key");
        if (defaultPrompts[key]["content"] == null) {
          try {
            defaultPrompts[key]["content"] = await rootBundle.loadString('assets/prompts/$key.md');
          } catch (e) {
            defaultPrompts[key]["content"] = "";
          }
        }
      }
    }

    // ── Scan SAF directory for new .md files to import ─────────────────────
    await _importFromDirectory();
  }

  // ── Import: scan the SAF folder for unknown .md files ────────────────────

  Future<void> _importFromDirectory() async {
    try {
      final hasDir = await FileAccessService.hasDirectory();
      if (!hasDir) return;

      final files = await FileAccessService.listFiles();
      for (final filename in files) {
        final name = FileAccessService.filenameToName(filename);
        // Check if a prompt with this filename is already tracked
        final alreadyTracked = userPrompts.values.any(
          (p) => p["filename"] == filename,
        );
        if (!alreadyTracked) {
          final content = await FileAccessService.readFile(filename);
          if (content != null) {
            final id = "user_file_${DateTime.now().millisecondsSinceEpoch}";
            userPrompts[id] = {
              "id": id,
              "name": name,
              "content": content,
              "author": "User",
              "filename": filename,
              "updated": DateTime.now().millisecondsSinceEpoch.toString(),
            };
            if (kDebugMode) print('[PromptRepository] Imported prompt from file: $filename');
          }
        }
      }
      // Persist any newly-imported prompts
      await _saveUserPrompts();
    } catch (e) {
      if (kDebugMode) print('[PromptRepository] _importFromDirectory error: $e');
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String getPromptContent(String id) {
    if (id.isEmpty) return "";
    if (userPrompts.containsKey(id)) return userPrompts[id]["content"] ?? "";
    if (defaultPrompts.containsKey(id)) return defaultPrompts[id]["content"] ?? "";
    return "";
  }

  String getPromptName(String id) {
    if (userPrompts.containsKey(id)) return userPrompts[id]["name"] ?? "Custom Prompt";
    if (defaultPrompts.containsKey(id)) return defaultPrompts[id]["name"] ?? "System Default";
    return "Unknown Prompt";
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> addUserPrompt(
    String id,
    String name,
    String content,
    String author,
  ) async {
    final oldFilename = userPrompts[id]?["filename"] as String?;
    final newFilename = FileAccessService.nameToFilename(name);

    userPrompts[id] = {
      "id": id,
      "name": name,
      "content": content,
      "author": author,
      "filename": newFilename,
      "updated": DateTime.now().millisecondsSinceEpoch.toString(),
    };
    await _saveUserPrompts();

    // ── Sync to SAF directory ───────────────────────────────────────────────
    try {
      final hasDir = await FileAccessService.hasDirectory();
      if (hasDir) {
        // Rename the old file if the name changed
        if (oldFilename != null && oldFilename != newFilename) {
          await FileAccessService.renameFile(oldFilename, newFilename);
        }
        await FileAccessService.writeFile(newFilename, content);
      }
    } catch (e) {
      if (kDebugMode) print('[PromptRepository] SAF write error: $e');
    }
  }

  Future<void> deleteUserPrompt(String id) async {
    if (!userPrompts.containsKey(id)) return;
    final filename = userPrompts[id]["filename"] as String?;
    userPrompts.remove(id);
    await _saveUserPrompts();

    // ── Remove from SAF directory ───────────────────────────────────────────
    if (filename != null) {
      try {
        final hasDir = await FileAccessService.hasDirectory();
        if (hasDir) await FileAccessService.deleteFile(filename);
      } catch (e) {
        if (kDebugMode) print('[PromptRepository] SAF delete error: $e');
      }
    }
  }

  Future<void> cloneDefaultPrompt(String defaultId) async {
    if (!defaultPrompts.containsKey(defaultId)) return;
    final newId = "user_${DateTime.now().millisecondsSinceEpoch}";
    final name = "${defaultPrompts[defaultId]["name"]} (Copy)";
    final content = defaultPrompts[defaultId]["content"] ?? "";
    await addUserPrompt(newId, name, content, "User");
  }

  Future<void> _saveUserPrompts() async {
    final box = Hive.box('paios_storage');
    await box.put("user_prompts", jsonEncode(userPrompts));
    notifyEngine();
  }
}
