import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as md;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:geminilocal/parts/prompt.dart';
import 'package:geminilocal/parts/translator.dart';
import 'parts/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geminilocal/storage/analytics_service.dart';
import 'package:geminilocal/storage/app_config.dart';
import 'package:geminilocal/storage/chat_repository.dart';
import 'package:geminilocal/storage/migration.dart';
import 'package:geminilocal/storage/prompt_repository.dart';

class AIEngine with md.ChangeNotifier {
  final gemini = GeminiNano();
  final prompt = md.TextEditingController();
  final instructions = md.TextEditingController();
  final chatName = md.TextEditingController();

  Dictionary dict = Dictionary(
    path: "assets/translations",
    url: "https://raw.githubusercontent.com/Puzzak/PAIOS-Dict/main",
  );
  Prompt promptEngine = Prompt(ghUrl: "https://github.com/Puzzak/PAIOS");
  AiResponse response = AiResponse(
    text: "Loading...",
    tokenCount: 1,
    chunk: "Loading...",
    generationTimeMs: 1,
    finishReason: "",
  );
  String responseText = "";
  bool isLoading = false;
  bool isAvailable = false;
  bool isInitialized = false;
  bool isInitializing = false;
  String status = "";
  bool isError = false;

  bool appStarted = false;
  String testPrompt = "";
  Map modelInfo = {};
  Map resources = {};
  List modelDownloadLog = [];
  bool ignoreContext = false;

  md.ScrollController scroller = md.ScrollController();

  late final AppConfig config;
  late final ChatRepository chatData;
  late final AnalyticsService logger;
  late final PromptRepository promptData;

  AIEngine() {
    config = AppConfig(notifyEngine: genericRefresh);
    logger = AnalyticsService(notifyEngine: genericRefresh);
    promptData = PromptRepository(notifyEngine: genericRefresh);
    chatData = ChatRepository(
      notifyEngine: genericRefresh,
      requestTitle: generateChatTitle,
      logEvent: logger.log,
      getDefaultPromptId: () => config.defaultPromptId,
    );
  }

  // Getters/Setters to maintain UI compatibility
  bool get firstLaunch => config.firstLaunch;
  int get tokens => config.tokens;
  set tokens(int value) => config.tokens = value;
  double get temperature => config.temperature;
  set temperature(double value) => config.temperature = value;
  int get usualModelSize => config.usualModelSize;
  bool get addCurrentTimeToRequests => config.addCurrentTimeToRequests;
  set addCurrentTimeToRequests(bool value) => config.addCurrentTimeToRequests = value;
  bool get shareLocale => config.shareLocale;
  set shareLocale(bool value) => config.shareLocale = value;
  bool get errorRetry => config.errorRetry;
  set errorRetry(bool value) => config.errorRetry = value;
  bool get ignoreInstructions => config.ignoreInstructions;
  set ignoreInstructions(bool value) => config.ignoreInstructions = value;

  Map get chats => chatData.chats;
  String get currentChat => chatData.currentChat;
  set currentChat(String value) => chatData.currentChat = value;
  List get context => chatData.context;
  set context(List value) => chatData.context = value;
  int get contextSize => chatData.contextSize;
  set contextSize(int value) => chatData.contextSize = value;
  String get lastPrompt => chatData.lastPrompt;
  set lastPrompt(String value) => chatData.lastPrompt = value;

  bool get analytics => logger.analyticsEnabled;
  set analytics(bool value) => logger.analyticsEnabled = value;
  bool get analyticsDone => logger.analyticsDone;
  List<Map> get logs => logger.logs;
  bool get isLoadingTitle => chatData.isLoadingTitle;
  
  List<Map<String, dynamic>> get logsList => logs.cast<Map<String, dynamic>>();

  /// Subscription to manage the active AI stream
  StreamSubscription<AiEvent>? _aiSubscription;

  late Cards cards;

  /// This junk is to update all pages in case we have a modal that is focused in which case setState will not update content underneath it
  void genericRefresh() {
    notifyListeners();
  }

  Future<void> endFirstLaunch() => config.endFirstLaunch();
  Future<void> saveSettings() => config.saveSettings(instructions.text);

  scrollChatlog(Duration speed) {
    scroller.animateTo(
      scroller.position.maxScrollExtent,
      duration: speed,
      curve: md.Curves.fastOutSlowIn,
    );
  }

  Future<void> startAnalytics() => logger.startAnalytics();
  Future<void> stopAnalytics() => logger.stopAnalytics();
  Future<void> log(String name, String type, String message) => logger.log(name, type, message);

  Future<void> start() async {
    await MigrationService.initiateMigration();
    await logger.initFromHive();
    await config.initFromHive();
    
    await log("init", "info", "Starting the app engine");
    await log("init", "info", "Starting the translations engine");
    dict = Dictionary(path: "assets/translations", url: "https://raw.githubusercontent.com/${config.repo}/main");
    await dict.setup();
    await log("init", "info", "Checking Gemini Nano status");
    await checkEngine();
    await log("init", "info", "Initializing the Prompt engine");
    promptEngine = Prompt(ghUrl: "https://github.com/${config.repo}");
    await promptData.initFromHive("https://raw.githubusercontent.com/${config.repo}/main");
    await promptEngine.initialize();
    
    await log(
      "init",
      "info",
      "Firebase analytics: ${analytics ? "Enabled" : "Disabled"}",
    );

    await chatData.initFromHive();
    await log(
      "init",
      "info",
      "Add DateTime to prompt: ${addCurrentTimeToRequests ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Add app locale to prompt: ${shareLocale ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Retry on error: ${errorRetry ? "Enabled" : "Disabled"}",
    );
    await log(
      "init",
      "info",
      "Ignore instructions: ${ignoreInstructions ? "Enabled" : "Disabled"}",
    );
    appStarted = true;
    await log("init", "info", "App initiation complete");
    notifyListeners();
  }

  void addDownloadLog(String log) {
    modelDownloadLog.add({
      "status": log.split("=")[0],
      "info": log.split("=")[1],
      "value": log.split("=")[2],
      "time": DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  lateNetCheck() async {
    while (firstLaunch) {
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        if (modelDownloadLog.isNotEmpty) {
          if (!(modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
              "waiting_network")) {
            if (modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
                "downloading_model") {
              addDownloadLog(
                "Download=waiting_network=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}",
              );
            }
          }
        }
      } else {
        if (modelDownloadLog.isNotEmpty) {
          if ((modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
              "waiting_network")) {
            addDownloadLog(
              "Download=downloading_model=${modelDownloadLog[modelDownloadLog.length - 1]["value"]}",
            );
          }
        }
      }
      await Future.delayed(Duration(seconds: 2));
    }
  }

  String convertSize(int size, bool isSpeed) {
    if (size < 1024) {
      return '$size B${isSpeed ? "/s" : ""}';
    } else if (size < 10240) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(2)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 1048576) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(1)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 10485760) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(2)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 104857600) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(1)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 1073741824) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(2)} GB${isSpeed ? "/s" : ""}';
    } else if (size < 10737418240) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(1)} GB${isSpeed ? "/s" : ""}';
    } else {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toInt()} GB${isSpeed ? "/s" : ""}';
    }
  }

  lateProgressCheck() async {
    Map lastUpdate = {};
    while (firstLaunch) {
      await Future.delayed(Duration(seconds: 15));
      if (lastUpdate == {}) {
        if (modelDownloadLog.isNotEmpty) {
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
      if (modelDownloadLog.isNotEmpty) {
        if (lastUpdate == modelDownloadLog[modelDownloadLog.length - 1]) {
          /// Nothing changed in the last 15 seconds, assume we have restarted and are not getting updates; We must restart the checkEngine. So...
          checkEngine();
          await log(
            "model",
            "warning",
            "Stopped getting model download events",
          );
        } else {
          lastUpdate = modelDownloadLog[modelDownloadLog.length - 1];
        }
      }
    }
  }

  Future<void> checkEngine() async {
    if (modelDownloadLog.isEmpty) {
      lateNetCheck();
      lateProgressCheck();
    }
    modelDownloadLog.clear();
    gemini.statusStream = gemini.downloadChannel.receiveBroadcastStream().map(
      (dynamic event) => event.toString(),
    );
    gemini.statusStream.listen(
      (String downloadStatus) async {
        switch (downloadStatus.split("=")[0]) {
          case "Available":
            modelInfo = await gemini.getModelInfo();
            if (modelInfo["version"] == null) {
              await log(
                "model",
                "warning",
                "Model version was not reported, trying again",
              );
              await Future.delayed(Duration(seconds: 2));
              checkEngine();
            } else {
              if (modelInfo["status"] == "Available") {
                addDownloadLog("Available=Available=0");
                await log("model", "info", "Model is ready");
                endFirstLaunch();
              } else {
                if (downloadStatus.split("=")[1] == "Download") {
                  if (!(modelDownloadLog[modelDownloadLog.length - 1]["info"] ==
                      "waiting_network")) {
                    addDownloadLog("Download=downloading_model=0");
                    await log("model", "info", "Downloading model");
                  }
                } else {
                  addDownloadLog(downloadStatus);
                }
              }
            }
            break;
          case "Download":
            if (modelDownloadLog.isEmpty) {
              addDownloadLog(downloadStatus);
            } else {
              if (!modelDownloadLog[modelDownloadLog.length - 1]["value"]
                  .contains("error")) {
                await log(
                  "model",
                  "info",
                  "Downloading, ${convertSize(int.parse(modelDownloadLog[modelDownloadLog.length - 1]["value"]), false)}",
                );
                if (int.parse(downloadStatus.split("=")[2]) >
                    int.parse(
                      modelDownloadLog[modelDownloadLog.length - 1]["value"],
                    )) {
                  addDownloadLog(downloadStatus);
                }
              }
            }
            break;
          case "Error":
            addDownloadLog(downloadStatus);
            await log("model", "error", downloadStatus.split("=")[2]);
            if (downloadStatus.split("=")[2].contains("1-DOWNLOAD_ERROR")) {
              checkEngine();
            } else {
              Fluttertoast.showToast(
                msg: "Gemini Nano ${dict.value("unavailable")}",
                toastLength: Toast.LENGTH_SHORT,
                fontSize: 16.0,
              );
            }
            break;
          default:
            addDownloadLog(downloadStatus);
        }
      },
      onError: (e) async {
        await log("model", "error", e);
        analyzeError("Received new status: ", e);
      },
      onDone: () {
        notifyListeners();
      },
    );
  }

  addToContext() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    contextSize =
        contextSize +
        responseText.split(' ').length +
        lastPrompt.split(' ').length;
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
    await prefs.setString("context", jsonEncode(context));
    await prefs.setInt("contextSize", contextSize);
    if (currentChat == "0") {
      currentChat = DateTime.now().millisecondsSinceEpoch.toString();
    }
    await saveChat(context, chatID: currentChat);
    lastPrompt = "";
    responseText = "";
    notifyListeners();
  }

  deleteChat(String chatID) async {
    if (chats.containsKey(chatID) && !(chatID == "0")) {
      chats.remove(chatID);
      notifyListeners();
      await log("application", "info", "Deleting chat");
    }
  }

  Future<String> generateChatTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await log("model", "info", "Generating new chat title");
    await generateTitle("Task: Create a short, 3-5 word title for this conversation.\n"
        "Rules:\n"
        "1. DO NOT use full sentences.\n"
        "2. DO NOT use phrases like \"The conversation is about\" or \"Summary of\".\n"
        "3. Be extremely concise.\n"
        "4. The title MUST be in the same language as the conversation.\n"
        "5. The title MUST be about whole conversation if there is more than one message.\n"
        "6. The title MUST NOT contain ANY name of any conversation party like \"Gemini\", \"Gemini's\", \"User\" or \"User's\".\n"
        "Examples:\n"
        "Conversation: \"Hello, how are you?\"\n"
        "Title: Greeting\n\n"
        "Conversation: \"Привіт, як справи?\"\n"
        "Title: Привітання\n\n"
        "Conversation: \"Write a python script to sort a list\"\n"
        "Title: Python sorting script\n\n"
        "Conversation: \"Why is the sky blue?\"\n"
        "Title: Sky color explanation\n\n"
        "Conversation: \"I need help with my printer\"\n"
        "Title: Printer troubleshooting\n\n"
        "Conversation: \"sdlkfjsdf\"\n"
        "Title: Random characters\n\n"
        "Conversation: \n\"$input\"\n"
        "Title: ")
        .then((title) {
      newTitle = title;
    });
    return newTitle;
  }

  Future<String> generatePromptTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await log("model", "info", "Generating new prompt title");
    await generateTitle("Task: Create a short, 3-5 word title for this prompt.\n"
        "Rules:\n"
        "1. DO NOT use full sentences.\n"
        "2. DO NOT use phrases like \"The prompt is about\" or \"Summary of\".\n"
        "3. Be extremely concise.\n"
        "4. The title MUST be in the same language as the prompt.\n"
        "5. The title MUST be about whole prompt.\n"
        "6. The title MUST NOT contain ANY name of any party like \"Gemini\", \"Gemini's\", \"User\" or \"User's\".\n"
        "7. The title must not be a word-for-word representation for small prompts.\n"
        "8. If the prompt is empty, title it like \"Empty prompt\" or \"No prompt\" or in similar way.\n"
        "Examples:\n"
        "Prompt: \"Speak only in pirate language, do not break character\"\n"
        "Title: Pirate speak\n\n"
        "Prompt: \"Розмовляй як науковець\"\n"
        "Title: Науковець\n\n"
        "Prompt: \"Be a coding assistant, do not try to do anything but fix, optimize or refactor the code\"\n"
        "Title: Coding assistant\n\n"
        "Prompt: \"sdlkfjsdf\"\n"
        "Title: Bad prompt (gibberish)\n\n"
        "Prompt: \"\"\n"
        "Title: Empty prompt\n\n"
        "Prompt: \n\"$input\"\n"
        "Title: ")
        .then((title) {
      newTitle = title;
    });
    return newTitle;
  }

  Future<String> generateTitle(String input) async {
    ignoreContext = true;
    String newTitle = "";
    await gemini.init().then((initStatus) async {
      ignoreContext = false;
      if (initStatus == null) {
        analyzeError(
          "Initialization",
          "Did not get response from AICore communication attempt",
        );
      } else {
        if (initStatus.contains("Error")) {
          analyzeError("Initialization", initStatus);
        } else {
          await gemini
              .generateText(
            prompt: input,
            config: GenerationConfig(maxTokens: 20, temperature: 0.7),
          )
              .then((title) {
            newTitle = title.split('\n').first;
            newTitle = newTitle.replaceAll(RegExp(r'[*#_`]'), '').trim();
            if (newTitle.length > 40) {
              newTitle = "${newTitle.substring(0, 40)}...";
            }
          });
        }
      }
    });
    return newTitle.trim().replaceAll(".", "");
  }

  saveChats() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("chats", jsonEncode(chats));
    genericRefresh();
  }

  saveChat(List conversation, {String chatID = "0"}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (chatID == "0") {
      chatID = DateTime.now().millisecondsSinceEpoch.toString();
    }
    if (conversation.isNotEmpty) {
      if (chats.containsKey(chatID)) {
        if (!chats[chatID]!.containsKey("name")) {
          await Future.delayed(Duration(milliseconds: 500));

          /// We have to wait some time because summarizing immediately will always result in overflowing the quota for some reason
          await generateChatTitle(conversation[0]["message"]).then((newTitle) {
            chats[chatID]!["name"] = newTitle;
          });
        }
        chats[chatID]!["history"] = jsonEncode(conversation).toString();
        chats[chatID]!["updated"] = DateTime.now().millisecondsSinceEpoch
            .toString();
        chats[chatID]!["tokens"] = contextSize.toString();
        await log(
          "application",
          "info",
          "Saving chat. Length: ${contextSize.toString()}",
        );
      } else {
        isLoading = true;
        await Future.delayed(Duration(milliseconds: 500));

        /// We have to wait some time because summarizing immediately will always result in overflowing the quota for some reason
        String newTitle = "Still loading";
        String composeConversation = "";
        for (var line in conversation) {
          composeConversation = "$composeConversation\n - ${line["message"]}";
        }
        await generateChatTitle(composeConversation).then((result) {
          newTitle = result;
        });

        isLoading = false;
        chats[chatID] = {
          "name": newTitle,
          "tokens": contextSize.toString(),
          "pinned": false,
          "history": jsonEncode(conversation).toString(),
          "created": DateTime.now().millisecondsSinceEpoch.toString(),
          "updated": DateTime.now().millisecondsSinceEpoch.toString(),
        };
        await log("application", "info", "Saving new chat");
      }
    }
    await prefs.setString("chats", jsonEncode(chats));
    genericRefresh();
  }

  Future<void> clearContext() async {
    await chatData.clearContext();
    responseText = "";
  }

  Future<void> initEngine() async {
    if (isInitializing) return;
    isInitializing = true;
    isError = false;
    notifyListeners();
    try {
      String currentPromptId = chatData.chats.containsKey(currentChat) ? chatData.chats[currentChat]["promptId"] ?? config.defaultPromptId : config.defaultPromptId;
      String specificPromptText = promptData.getPromptContent(currentPromptId);
      
      await promptEngine
          .generate(
            specificPromptText,
            context,
            modelInfo,
            currentLocale: dict.value("current_language"),
            addTime: addCurrentTimeToRequests,
            shareLocale: shareLocale,
            ignoreInstructions: ignoreInstructions,
            ignoreContext: ignoreContext,
          )
          .then((instruction) async {
            await gemini.init(instructions: instruction).then((
              initStatus,
            ) async {
              if (initStatus == null) {
                await log(
                  "model",
                  "error",
                  "Did not get response from AICore communication attempt",
                );
                analyzeError(
                  "Initialization",
                  "Did not get response from AICore communication attempt",
                );
              } else {
                if (initStatus.contains("Error")) {
                  await log("model", "error", initStatus);
                  analyzeError("Initialization", initStatus);
                } else {
                  await log("model", "info", "Model initialized successfully");
                  isAvailable = true;
                  isInitialized = true;
                }
              }
            });
          });
    } catch (e) {
      await log("model", "error", e.toString());
      analyzeError("Initialization", e);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  /// Sets the error state
  void analyzeError(String action, dynamic e) {
    isAvailable = false;
    isError = true;
    isInitialized = false;
    isInitializing = false;
    status = "Error during $action: ${e.toString()}";
    notifyListeners();
  }

  /// Cancels any ongoing generation
  Future<void> cancelGeneration() async {
    _aiSubscription?.cancel();
    isLoading = false;
    status = "Generation cancelled";
    notifyListeners();
    scrollChatlog(Duration(milliseconds: 250));
    await log("model", "error", "Cancelling generation");
  }

  Future<void> generateStream() async {
    if (prompt.text.isEmpty) {
      status = "Please enter your prompt";
      isError = true;
      notifyListeners();
      return;
    }
    if (isLoading) return; // Don't run if already generating

    // Ensure engine is ready
    if (!isInitializing) {
      await initEngine();
    }

    // Cancel any old streams
    await _aiSubscription?.cancel();

    // Set initial state for this new stream
    isLoading = true;
    isError = false;
    responseText = "";
    status = "Sending prompt...";
    notifyListeners();

    final stream = gemini.generateTextEvents(
      prompt: "User's request: ${prompt.text.trim()}",
      config: GenerationConfig(maxTokens: tokens, temperature: temperature),
      stream: true,
    );
    lastPrompt = prompt.text.trim();

    _aiSubscription = stream.listen(
      (AiEvent event) async {
        switch (event.status) {
          case AiEventStatus.loading:
            isLoading = true;
            responseText = "";
            status = dict.value("waiting_for_AI");
            await log("model", "info", "Waiting for model to initialize");
            notifyListeners();
            break;

          case AiEventStatus.streaming:
            isLoading = true;
            String? finishReason = event.response?.finishReason;
            if (!(event.response?.finishReason == "null")) {
              switch (finishReason ?? "null") {
                case "0":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (MAX_TOKENS): The maximum number of output tokens as specified in the request was reached.",
                    );
                  }
                  await log("model", "info", "Generation stopped (MAX_TOKENS)");
                  break;
                case "1":
                  if (kDebugMode) {
                    print("Generation stopped (OTHER): Generic stop reason.");
                  }
                  await log("model", "info", "Generation stopped (OTHER)");
                  break;
                case "-100":
                  if (kDebugMode) {
                    print(
                      "Generation stopped (STOP): Natural stop point of the model.",
                    );
                  }
                  await log("model", "info", "Generation stopped (STOP)");
                  break;
                default:
                  if (kDebugMode) {
                    print(
                      "Generation stopped (Code ${event.response?.finishReason}): Reason for stop was not specified",
                    );
                  }
                  await log(
                    "model",
                    "info",
                    "Generation stopped (Code ${event.response?.finishReason})",
                  );
                  break;
              }
            }
            status = "Streaming response...";
            if (event.response != null) {
              response = event.response!;
              responseText = event.response!.text;
            }
            try {
              scrollChatlog(Duration(milliseconds: 250));
              await Future.delayed(Duration(milliseconds: 500));
              scrollChatlog(Duration(milliseconds: 250));
            } catch (e) {
              if (kDebugMode) {
                print("Can't scroll: $e");
              }
              await Future.delayed(Duration(milliseconds: 500));
            }
            break;

          case AiEventStatus.done:
            if (responseText == "") {
              if (errorRetry) {
                if (event.response?.text == null) {
                  isLoading = false;
                  Fluttertoast.showToast(
                    msg: "Unable to generate response.",
                    toastLength: Toast.LENGTH_SHORT,
                    fontSize: 16.0,
                  );
                } else {
                  await Future.delayed(Duration(milliseconds: 500));
                  generateStream();
                }
              } else {
                isLoading = false;
                isError = true;
                status = "Error";
                responseText = event.error ?? "Unknown stream error";
                await log("model", "error", responseText);
              }
            } else {
              isLoading = false;
              status = "Done";
              addToContext();
              prompt.clear();
              await log(
                "model",
                "info",
                dict
                    .value("generated_hint")
                    .replaceAll(
                      "%seconds%",
                      ((response.generationTimeMs ?? 10) / 1000)
                          .toStringAsFixed(2),
                    )
                    .replaceAll(
                      "%tokens%",
                      response.text.split(" ").length.toString(),
                    )
                    .replaceAll(
                      "%tokenspersec%",
                      (response.tokenCount!.toInt() /
                              ((response.generationTimeMs ?? 10) / 1000))
                          .toStringAsFixed(2),
                    ),
              );
              try {
                scrollChatlog(Duration(milliseconds: 250));
              } catch (e) {
                if (kDebugMode) {
                  print("Can't scroll: $e");
                }
              }
            }
            break;

          case AiEventStatus.error:
            if (errorRetry) {
              await Future.delayed(Duration(milliseconds: 500));
              generateStream();
            } else {
              isLoading = false;
              isError = true;
              status = "Error";
              responseText = event.error ?? "Unknown stream error";
              await log("model", "error", responseText);
            }
            break;
        }
        genericRefresh();
      },
      onError: (e) async {
        if (errorRetry) {
          await Future.delayed(Duration(milliseconds: 500));
          generateStream();
        } else {
          await log("model", "error", e);
          analyzeError("Streaming", e);
        }
      },
      onDone: () {
        // Final state update when stream closes
        isLoading = false;
        if (!isError) {
          status = "Stream complete";
        }
        genericRefresh();
      },
    );
  }

  /// Clean up resources
  @override
  void dispose() {
    prompt.dispose();
    instructions.dispose();
    _aiSubscription?.cancel(); // Cancel stream
    gemini.dispose(); // Tell native code to clean up
    super.dispose();
  }
}
