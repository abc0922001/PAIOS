import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

class Dictionary {
  List languages = [];
  bool systemLanguage = false;
  Map dictionary = {};
  String locale = "en";
  String path = "";
  String url = "";

  Dictionary._internal(this.path, this.url);
  factory Dictionary({required String path, required String url}){
    return Dictionary._internal(path, url);
  }

  decideLanguage() async {
    final box = Hive.box('paios_storage');
    if(box.containsKey("language")){
      locale = box.get("language", defaultValue: "en");
    }else{
      setSystemLanguage();
    }
  }
  
  setSystemLanguage() async {
    String deviceLocale = Platform.localeName.split("_")[0];
    for(int a = 0; a < languages.length;a++){
      if(languages[a]["id"] == deviceLocale){
        locale = deviceLocale;
      }
    }
  }
  
  saveLanguage(String variant) async {
    final box = Hive.box('paios_storage');
    for(int a = 0; a < languages.length;a++){
      if(languages[a]["id"] == variant){
        locale = variant;
        box.put("language", variant);
      }
    }
  }

  setup() async {
    final box = Hive.box('paios_storage');
    
    // 1. Triple-Tier System Step 1 & 2: Load Cache or Fallback Asset
    String? cachedLangList = box.get("cached_languages_json");
    if (cachedLangList != null) {
      languages = jsonDecode(cachedLangList);
    } else {
      String assetLangList = await rootBundle.loadString('$path/languages.json');
      languages = jsonDecode(assetLangList);
    }
    
    await decideLanguage();
    
    for(int i=0; i < languages.length; i++){
      String langId = languages[i]["id"];
      String? cachedDict = box.get("cached_dict_$langId");
      if (cachedDict != null) {
        dictionary[langId] = jsonDecode(cachedDict);
      } else {
        try {
          String assetDict = await rootBundle.loadString('$path/$langId.json');
          dictionary[langId] = jsonDecode(assetDict);
        } catch (e) {
          // Fails silently if rootBundle doesn't have it (e.g. newly added lang)
        }
      }
    }
    
    // 2. Triple-Tier System Step 3: Network Check & Cache Refresh
    if(!kDebugMode){
      try {
        final response = await http.get(Uri.parse("$url/$path/languages.json"));
        if(response.statusCode == 200) {
          languages = jsonDecode(response.body);
          box.put("cached_languages_json", response.body); // Update persistent cache
          await decideLanguage();
          
          for (int i = 0; i < languages.length; i++) {
            String langId = languages[i]["id"];
            final languageGet = await http.get(Uri.parse("$url/$path/$langId.json"));
            if (languageGet.statusCode == 200) {
              dictionary[langId] = jsonDecode(languageGet.body);
              box.put("cached_dict_$langId", languageGet.body); // Update persistent cache
            }
          }
        }
      }catch(e){
        if (kDebugMode) print("Falling back to strictly offline Languages! Error: $e");
      }
    }
  }

  String value (String entry){
    if(!dictionary.containsKey(locale)){
      return "Loading...";
    }
    if(!dictionary[locale].containsKey(entry)){
      if(!dictionary["en"].containsKey(entry)){
        return "!!! $entry";
      }
      return "!${dictionary["en"][entry].toString()}!";
    }
    return dictionary[locale][entry].toString();
  }
}
