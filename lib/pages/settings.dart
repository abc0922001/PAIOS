import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/logs.dart';
import 'package:geminilocal/pages/settings/prompts.dart';
import 'package:geminilocal/pages/settings/resources.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import 'support/elements.dart';
import 'package:intl/intl.dart';
import 'package:geminilocal/pages/settings/model.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Consumer<AIEngine>(builder: (context, engine, child) {
                Cards cards = engine.cards;
                return Scaffold(
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SliverAppBar.large(
                        surfaceTintColor: Colors.transparent,
                        leading: Padding(
                          padding: EdgeInsetsGeometry.only(left: 5),
                          child: IconButton(
                              onPressed: (){
                                Navigator.pop(context);
                              },
                              icon: Icon(Icons.arrow_back_rounded)
                          ),
                        ),
                        title: Text(engine.dict.value("settings")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Category.settings(
                                title: engine.dict.value("settings_app"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.doubleTap(
                                  title: engine.dict.value("select_language"),
                                  subtitle: engine.dict.value("select_language_auto_long"),
                                  icon: Icons.app_settings_alt_rounded,
                                  action: () {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (BuildContext dialogContext) =>
                                          AlertDialog(
                                            contentPadding: EdgeInsets.only(
                                              top: 10,
                                              bottom: 15,
                                            ),
                                            titlePadding: EdgeInsets.only(
                                                top: 20,
                                                right: 20,
                                                left: 20
                                            ),
                                            title: Text(engine.dict.value("select_language")),
                                            content: SingleChildScrollView(
                                                child: cards.cardGroup(
                                                    engine.dict.languages.map((language) {
                                                      return CardContents.halfTap(
                                                          title: language["origin"],
                                                          subtitle: language["name"] == language["origin"] ? "" : language["name"],
                                                          action: () async {
                                                            setState(() {
                                                              engine.dict.saveLanguage(language["id"]);
                                                            });
                                                            Navigator.of(dialogContext).pop();
                                                          }
                                                      );
                                                    }).toList().cast<Widget>()
                                                )
                                            ),
                                          ),
                                    );
                                  },
                                  secondAction: (){
                                    setState(() {
                                      engine.dict.setSystemLanguage();
                                    });
                                  }
                              ),
                              CardContents.turn(
                                  title: engine.dict.value("error_retry"),
                                  subtitle: engine.dict.value("error_retry_desc"),
                                  action: (){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  switcher: (value){
                                    setState(() {
                                      engine.errorRetry = !engine.errorRetry;
                                    });
                                    engine.saveSettings();
                                  },
                                  value: engine.errorRetry
                              ),
                              CardContents.tap(
                                  title: engine.dict.value("open_aicore_settings"),
                                  subtitle: engine.dict.value("in_play_store"),
                                  action: () async {
                                    engine.gemini.openAICorePlayStore();
                                  }
                              ),
                            ]),
                            Category.settings(
                                title: engine.dict.value("settings_ai"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tapIcon(
                                  title: engine.dict.value("settings_ai"),
                                  subtitle: engine.dict.value("settings_ai_desc"),
                                  icon: Icons.auto_awesome_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => ModelSettings(),
                                          settings: const RouteSettings(name: 'ModelSettings')),
                                    );
                                  }
                              ),
                              CardContents.tapIcon(
                                  title: engine.dict.value("prompt_manager_title"),
                                  subtitle: engine.dict.value("system_prompt_desc"),
                                  icon: Icons.edit_note_rounded,
                                  colorBG: Theme.of(context).colorScheme.tertiaryFixedDim,
                                  color: Theme.of(context).colorScheme.onTertiaryFixed,
                                  action: () async {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => PromptsPage(),
                                          settings: const RouteSettings(name: 'PromptsPage')),
                                    );
                                  }
                              ),
                              CardContents.tap(
                                title: engine.dict.value("default_prompt_picker"),
                                subtitle: engine.promptData.getPromptName(engine.config.defaultPromptId),
                                action: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext dialogContext) => AlertDialog(
                                      title: Text(engine.dict.value("select_prompt")),
                                      content: Container(
                                        constraints: BoxConstraints(maxHeight: 300),
                                        child: SingleChildScrollView(
                                          child: cards.cardGroup([
                                            ...engine.promptData.defaultPrompts.keys.map((key) {
                                              return CardContents.halfTap(
                                                title: engine.promptData.defaultPrompts[key]["name"] ?? "Default",
                                                subtitle: "System",
                                                action: () {
                                                  setState(() {
                                                    engine.config.defaultPromptId = key;
                                                  });
                                                  engine.saveSettings();
                                                  Navigator.pop(dialogContext);
                                                }
                                              );
                                            }).toList().cast<Widget>(),
                                            ...engine.promptData.userPrompts.keys.map((key) {
                                              return CardContents.halfTap(
                                                title: engine.promptData.userPrompts[key]["name"] ?? "Custom",
                                                subtitle: "User",
                                                action: () {
                                                  setState(() {
                                                    engine.config.defaultPromptId = key;
                                                  });
                                                  engine.saveSettings();
                                                  Navigator.pop(dialogContext);
                                                }
                                              );
                                            }).toList().cast<Widget>(),
                                          ])
                                        )
                                      )
                                    )
                                  );
                                }
                              )
                            ]),
                            Category.settings(
                                title: engine.dict.value("settings_resources"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tapIcon(
                                  title: engine.dict.value("settings_resources"),
                                  subtitle: engine.dict.value("settings_resources_desc"),
                                  icon: Icons.dataset_linked_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    engine.resources.clear();
                                    for(var resource in engine.promptEngine.resources){
                                      if(resource["type"] == "link"){
                                        if(engine.resources.containsKey(resource["collection"])){
                                          engine.resources[resource["collection"]].add(resource);
                                        }else{
                                          engine.resources[resource["collection"]] = [resource];
                                        }
                                      }
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => SettingsResources(),
                                          settings: const RouteSettings(name: 'SettingsResources')),
                                    );
                                  }
                              )
                            ]),
                            Category.settings(
                                title: engine.dict.value(engine.analytics?"logs_with_analytics":"logs_no_analytics"),
                                context: context
                            ),
                            cards.cardGroup([
                              CardContents.tapIcon(
                                  title: engine.dict.value(engine.analytics?"logs_with_analytics":"logs_no_analytics"),
                                  subtitle: "",
                                  icon: Icons.checklist_rounded,
                                  colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                                  action: (){
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => LogsPage(),
                                          settings: const RouteSettings(name: 'LogsPage')),
                                    );
                                  }
                              )
                            ]),
                            text.info(
                              title: engine.dict.value("settings_info").replaceAll("%year%", DateFormat('yyyy').format(DateTime.now())),
                              context: context,
                              subtitle: engine.dict.value("gh_repo"),
                              action: () async {
                                await launchUrl(
                                Uri.parse('https://github.com/Puzzaks/geminilocal'),
                                mode: LaunchMode.externalApplication
                                );
                              }
                            )
                          ],
                        ),
                      ),
                    ],

                  ),
                );
              });
            }
        )
    );
  }
}