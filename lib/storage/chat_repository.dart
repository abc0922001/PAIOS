import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ChatRepository {
  final VoidCallback notifyEngine;
  final Future<String> Function(String) requestTitle;
  final Future<void> Function(String, String, String) logEvent;

  List context = [];
  int contextSize = 0;
  Map chats = {};
  String currentChat = "0";
  String lastPrompt = "";
  String Function() getDefaultPromptId;
  
  bool isLoadingTitle = false;

  ChatRepository({
    required this.notifyEngine,
    required this.requestTitle,
    required this.logEvent,
    required this.getDefaultPromptId,
  });

  Future<void> initFromHive() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("context")) {
      context = jsonDecode(box.get("context", defaultValue: "[]"));
      contextSize = box.get("contextSize", defaultValue: 0);
    }
    if (box.containsKey("chats")) {
      chats = jsonDecode(box.get("chats", defaultValue: "{}"));
    }
    await logEvent("init", "info", chats.isEmpty ? "No chats found" : "Found chats: ${chats.length}");
  }

  Future<void> addToContext(String responseText) async {
    final box = Hive.box('paios_storage');
    
    contextSize = contextSize + responseText.split(' ').length + lastPrompt.split(' ').length;
    context.add({
      "user": "User",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": lastPrompt,
    });
    context.add({
      "user": "Gemini",
      "time": DateTime.now().millisecondsSinceEpoch.toString(),
      "message": responseText,
    });
    
    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);
    
    if (currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }
    
    await saveChat(context, chatID: currentChat);
    
    lastPrompt = "";
    notifyEngine();
  }

  Future<void> deleteChat(String chatID) async {
    if (chats.containsKey(chatID) && !(chatID == "0")) {
      chats.remove(chatID);
      final box = Hive.box('paios_storage');
      await box.put("chats", jsonEncode(chats));
      notifyEngine();
      await logEvent("application", "info", "Deleting chat");
    }
  }

  Future<void> saveChats() async {
    final box = Hive.box('paios_storage');
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
  }

  Future<void> saveChat(List conversation, {String chatID = "0"}) async {
    final box = Hive.box('paios_storage');
    if (chatID == "0") {
      chatID = DateTime.now().millisecondsSinceEpoch.toString();
    }
    
    if (conversation.isNotEmpty) {
      if (chats.containsKey(chatID)) {
        if (!chats[chatID]!.containsKey("name")) {
          await Future.delayed(const Duration(milliseconds: 500));
          await requestTitle(conversation[0]["message"]).then((newTitle) {
            chats[chatID]!["name"] = newTitle;
          });
        }
        chats[chatID]!["history"] = jsonEncode(conversation).toString();
        chats[chatID]!["updated"] = DateTime.now().millisecondsSinceEpoch.toString();
        chats[chatID]!["tokens"] = contextSize.toString();
        await logEvent("application", "info", "Saving chat. Length: ${contextSize.toString()}");
      } else {
        isLoadingTitle = true;
        notifyEngine();
        
        await Future.delayed(const Duration(milliseconds: 500));
        String newTitle = "Still loading";
        String composeConversation = "";
        for (var line in conversation) {
          composeConversation = "$composeConversation\n - ${line["message"]}";
        }
        await requestTitle(composeConversation).then((result) {
          newTitle = result;
        });

        isLoadingTitle = false;
        
        chats[chatID] = {
          "name": newTitle,
          "tokens": contextSize.toString(),
          "pinned": false,
          "promptId": getDefaultPromptId(),
          "history": jsonEncode(conversation).toString(),
          "created": DateTime.now().millisecondsSinceEpoch.toString(),
          "updated": DateTime.now().millisecondsSinceEpoch.toString(),
        };
        await logEvent("application", "info", "Saving new chat");
      }
    }
    await box.put("chats", jsonEncode(chats));
    notifyEngine();
  }

  Future<void> clearContext() async {
    final box = Hive.box('paios_storage');
    context.clear();
    contextSize = 0;
    lastPrompt = "";
    chats.remove(currentChat);
    await box.put("chats", jsonEncode(chats));
    await box.put("context", jsonEncode(context));
    await box.put("contextSize", contextSize);
    notifyEngine();
  }
}
