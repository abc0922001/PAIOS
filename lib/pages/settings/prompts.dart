import 'package:flutter/material.dart';
import 'package:geminilocal/pages/settings/prompt_editor.dart';
import 'package:provider/provider.dart';
import '../../engine.dart';
import '../support/elements.dart';
import 'package:intl/intl.dart';

class PromptsPage extends StatefulWidget {
  const PromptsPage({super.key});
  @override
  PromptsPageState createState() => PromptsPageState();
}

class PromptsPageState extends State<PromptsPage> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              Cards cards = Cards(context: context);
              return Consumer<AIEngine>(builder: (context, engine, child) {
                return Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    icon: Icon(Icons.add_rounded),
                    label: Text(engine.dict.value("create_prompt_custom")),
                    onPressed: () {
                       String customId = "user_${DateTime.now().millisecondsSinceEpoch}";
                       engine.promptData.addUserPrompt(customId, engine.dict.value("new_prompt_name"), "", "User");
                       Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PromptEditorPage(promptId: customId),
                          settings: const RouteSettings(name: 'PromptEditorPage')),
                       );
                    },
                  ),
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
                        title: Text(engine.dict.value("prompt_manager_title")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Category.settings(
                                title: engine.dict.value("default_prompts_title"),
                                context: context
                            ),
                            cards.cardGroup([
                              ...engine.promptData.defaultPrompts.keys.map((key) {
                                Map prompt = engine.promptData.defaultPrompts[key];
                                return CardContents.tap(
                                    title: prompt["name"] ?? "System Default",
                                    subtitle: engine.dict.value("by_author").replaceAll("%author%", prompt["author"] ?? "Google"),
                                    action: () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext dialogContext) => AlertDialog(
                                              title: Text(prompt["name"]),
                                              content: SingleChildScrollView(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(prompt["description"] ?? ""),
                                                    SizedBox(height: 10),
                                                    Text(engine.dict.value("last_updated") + ": " + DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(int.parse(prompt["updated"] ?? "0"))), style: TextStyle(color: Colors.grey)),
                                                  ],
                                                )
                                              ),
                                              actions: [
                                                TextButton(
                                                    onPressed: () => Navigator.pop(dialogContext),
                                                    child: Text(engine.dict.value("close"))
                                                ),
                                                FilledButton(
                                                    onPressed: () {
                                                        engine.promptData.cloneDefaultPrompt(prompt["id"]);
                                                        Navigator.pop(dialogContext);
                                                    },
                                                    child: Text(engine.dict.value("clone_prompt"))
                                                )
                                              ],
                                          )
                                      );
                                    }
                                );
                              }).toList().cast<Widget>(),
                            ]),

                            Category.settings(
                                title: engine.dict.value("user_prompts_title"),
                                context: context
                            ),
                            cards.cardGroup([
                              ...engine.promptData.userPrompts.keys.map((key) {
                                Map prompt = engine.promptData.userPrompts[key];
                                return CardContents.tap(
                                    title: prompt["name"] ?? "Custom",
                                    subtitle: "",
                                    action: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => PromptEditorPage(promptId: key),
                                            settings: const RouteSettings(name: 'PromptEditorPage')),
                                      );
                                    }
                                );
                              }).toList().cast<Widget>(),
                              if(engine.promptData.userPrompts.isEmpty)
                                CardContents.tapIcon(
                                    title: engine.dict.value("no_user_prompts"),
                                    subtitle: engine.dict.value("no_user_prompts_desc"),
                                    icon: Icons.edit_note_rounded,
                                    colorBG: Theme.of(context).colorScheme.primaryFixedDim,
                                    color: Theme.of(context).colorScheme.onPrimaryFixed,
                                    action: () {}
                                )
                            ]),
                            SizedBox(height: 75)
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
