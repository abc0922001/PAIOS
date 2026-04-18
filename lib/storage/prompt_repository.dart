import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

class PromptRepository {
  final VoidCallback notifyEngine;
  bool newPromptsAvailable = false;
  
  Map<String, dynamic> defaultPrompts = {};
  Map<String, dynamic> userPrompts = {};
  
  PromptRepository({required this.notifyEngine});

  Future<void> initFromHive(String url) async {
    final box = Hive.box('paios_storage');
    
    // Load User Prompts
    String? storedUserPrompts = box.get("user_prompts");
    if (storedUserPrompts != null) {
      userPrompts = jsonDecode(storedUserPrompts);
    }
    
    // Load Default Prompts Cache
    String? cachedIndex = box.get("cached_prompts_index");
    if (cachedIndex != null) {
      defaultPrompts = jsonDecode(cachedIndex);
    } else {
      try {
        String assetIndex = await rootBundle.loadString('assets/prompts/prompts_index.json');
        defaultPrompts = jsonDecode(assetIndex);
      } catch (e) {}
    }
    
    // Check Network for Updates
    if (!kDebugMode) {
      try {
        final response = await http.get(Uri.parse("$url/prompts/prompts_index.json"));
        if (response.statusCode == 200) {
          Map<String, dynamic> onlineIndex = jsonDecode(response.body);
          
          // Check for newer timestamps (simple version: different string length/content or checking individual timestamps later)
          if (cachedIndex != response.body && cachedIndex != null) {
            newPromptsAvailable = true;
            notifyEngine();
          }
          
          defaultPrompts = onlineIndex;
          box.put("cached_prompts_index", response.body);
          
          // Download individual md files for all default prompts
          for (String key in defaultPrompts.keys) {
            final promptGet = await http.get(Uri.parse("$url/prompts/$key.md"));
            if (promptGet.statusCode == 200) {
              defaultPrompts[key]["content"] = promptGet.body;
              box.put("cached_prompt_$key", defaultPrompts[key]["content"]);
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print("Network failed, trying local fallback! Error: $e");
      }
    }
    
    // Always ensure content is loaded (fallback loop) for anything missing
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
  }

  String getPromptContent(String id) {
    if (id == "system_default" || id.isEmpty) {
      return "";
    }
    if (userPrompts.containsKey(id)) {
      return userPrompts[id]["content"] ?? "";
    }
    if (defaultPrompts.containsKey(id)) {
      return defaultPrompts[id]["content"] ?? "";
    }
    return ""; // Fallback
  }

  String getPromptName(String id) {
    if (userPrompts.containsKey(id)) {
      return userPrompts[id]["name"] ?? "Custom Prompt";
    }
    if (defaultPrompts.containsKey(id)) {
      return defaultPrompts[id]["name"] ?? "System Default";
    }
    return "Unknown Prompt";
  }

  Future<void> addUserPrompt(String id, String name, String content, String author) async {
    userPrompts[id] = {
      "id": id,
      "name": name,
      "content": content,
      "author": author,
      "updated": DateTime.now().millisecondsSinceEpoch.toString()
    };
    await _saveUserPrompts();
  }

  Future<void> deleteUserPrompt(String id) async {
    if (userPrompts.containsKey(id)) {
      userPrompts.remove(id);
      await _saveUserPrompts();
    }
  }

  Future<void> cloneDefaultPrompt(String defaultId) async {
    if (defaultPrompts.containsKey(defaultId)) {
      String newId = "user_${DateTime.now().millisecondsSinceEpoch}";
      String name = "${defaultPrompts[defaultId]["name"]} (Copy)";
      String content = defaultPrompts[defaultId]["content"] ?? "";
      await addUserPrompt(newId, name, content, "You");
    }
  }

  Future<void> _saveUserPrompts() async {
    final box = Hive.box('paios_storage');
    await box.put("user_prompts", jsonEncode(userPrompts));
    notifyEngine();
  }
}
