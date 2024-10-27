import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:keep_screen_on/keep_screen_on.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:flutter/services.dart'; // アプリ終了用

import 'screen/list_item.dart'; 



final Logger _logger = Logger('MyApp');

void main() async {
  //環境変数を読み込む
  await dotenv.load(fileName: ".env");

  // スリープさせない
  KeepScreenOn.turnOn();

  //initializeDateFormatting();
  Intl.defaultLocale = 'ja_JP';

  //ロケール・言語設定（iOSはInfo.plistで直った）
  Intl.withLocale('ja', () => runApp(const MyApp()));
}

class SettingView extends StatefulWidget {
  const SettingView({super.key});

  @override
  State<SettingView> createState() => _SettingViewState();
}

class _SettingViewState extends State<SettingView> {
  String _selectedItemMy = "error";
  String _selectedItemBot = "error";
  final List<String> _items = ["error"];
  final FlutterTts tts = FlutterTts();
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();

    Future(() async {
      prefs = await SharedPreferences.getInstance();

      List voices = await tts.getVoices;

      _items.clear();
      for (var item in voices) {
        var map = item as Map<Object?, Object?>;
        if (map["locale"].toString().toLowerCase().contains("ja")) {
          _logger.info(map["name"]);
          _items.add(map["name"].toString());
        }
      }
      if (_items.isNotEmpty) {
        _selectedItemMy = prefs.getString("voice_わたし") ?? _items[0];
        _selectedItemBot = prefs.getString("voice_ロボット") ?? _items[0];
      }

      // プルダウンを反映
      setState(() {});
    });
  }

  Future<void> _changeVoice(String voiceName, String who, bool speak) async {
    prefs.setString("voice_$who", voiceName);

    if (!speak) {
      return;
    }

    await tts.stop();
    await tts.setVoice({'name': voiceName, 'locale': 'ja-JP'});

    await tts.speak("$whoの声が設定されました");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Setting"),
      ),
      body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('わたしの声'),
        DropdownButton<String>(
          value: _selectedItemMy,
          items: _items
              .map((String list) =>
                  DropdownMenuItem(value: list, child: Text(list)))
              .toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedItemMy = value!;
              _changeVoice(_selectedItemMy, "わたし", true);
            });
          },
        ),
        const Divider(height: 100),
        const Text('ロボットの声'),
        DropdownButton<String>(
          value: _selectedItemBot,
          items: _items
              .map((String list) =>
                  DropdownMenuItem(value: list, child: Text(list)))
              .toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedItemBot = value!;
              _changeVoice(_selectedItemBot, "OTA ボット", true);
            });
          },
        ),
      ])),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Speak Chat'),

      //ロケール・言語設定（iOSはInfo.plistで直った）
      localizationsDelegates: const [
        // localizations delegateを追加
        //AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      //ロケール・言語設定（iOSはInfo.plistで直った）
      supportedLocales: const [Locale('ja', 'JP')],
      locale: const Locale('ja', 'JP'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String lastWords = '';

  List<Object> chatMessages = [];
  final FlutterTts tts = FlutterTts();
  late SharedPreferences prefs;
  var inputTextcontroller = TextEditingController();
  ScrollController scrollController = ScrollController();

  // chatMessagesをサーバーに送信するメソッド
  Future<void> _sendMessagesToServer(List<Map<String, dynamic>> chatMessages) async {
    
    // chatMessagesをJSON形式に変換
    String body = json.encode(chatMessages);

    try {
      // POSTリクエストを送信
      final response = await http.post(
        Uri.parse("http://${dotenv.get("SERVER_HOST")}:${dotenv.get("SERVER_PORT")}/items"),
        body: jsonEncode(body), // bodyをJSON形式にエンコード
      );
      if (response.statusCode == 200) {
        // 成功時の処理
        print("メッセージをサーバーに送信しました: ${response.body}");
      } else {
        // エラーハンドリング
        print("リクエスト失敗: ${response.statusCode}");
      }
    } catch (e) {
      print("エラー: $e");
    }
  }
  
  
  
  
  Future<void> _exitAppWithAi() async {
    _logger.info("_exitAppWithAi");

    // チャットメッセージが無ければスキップ
    if (chatMessages.isEmpty) {
      return;
    }

    // API URLとヘッダー
    Uri url = Uri.parse("https://api.openai.com/v1/chat/completions");
    Map<String, String> headers = {
      'Content-type': 'application/json',
      "Authorization": "Bearer ${dotenv.get("OPEN_AI_API_KEY")}"
    };

    // APIリクエストのボディ（`_ai`メソッドに似た構造）
    String body = json.encode({
      "frequency_penalty": 0,
      "max_tokens": 512,
      "messages": [
        {
          "role": "system",
          "content": """
          あなたは入力された「何かを買った」のようなテキストを正確にJSON形式に変換します。以下の制約に従って変換してください:
          出力仕様:
          要求されるJSON形式は以下の通りです:
          request: {
          "item": {
              "display_name": "入力テキストに基づく表示名をそのまま使用します",
              "generic_name": "入力テキストの生成される一般名を助詞を含めずに使用",
              "status": "unpacked"  # 常に'unpacked'に設定
              "user_id": <送られてきたuser_idを使用>
          },
          "shelf_life_days": <一般的な賞味期限を日単位で推測して設定。該当しないものの場合はは空>,
          "category_names": <第一要素が 'Food', 'daily necessities', 'others'のいずれか。残りの要素には自由に追加情報を含めます>
          }

          具体的な変換例:
          - テキストから取得する名詞指示に基づき `display_name`と`generic_name`を定義します。
          - `user_id`は入力データに直接与えられます。
          - `shelf_life_days`は食品の一般的な賞味期限を推測して設定します。該当しない場合は空としておきます。
          - `category_names`は項目の大カテゴリーを最初の要素として設定し、その他の要素として追加情報を含みます。

          厳格な規則:
          - 余計な説明は一切付けない
          - 必ず有効なJSONとして解析可能な形式にする
          - すべてのフィールドは指定されたルールに従って埋めること

          例 
          入力: user_id: 4  "長野県産のキャベツを1玉買った"
          出力:
          request: {
          "item": {
              "display_name": "長野県産のキャベツ",
              "generic_name": "キャベツ",
              "status": "unpacked"  # 常に'unpacked'に設定
              "user_id": 4
          },
          "shelf_life_days": 7,
          "category_names": ["Food", "野菜", "長野県産"]
          }
          """
        },
        ...chatMessages
      ],
      "model": "gpt-4o-mini",
      "presence_penalty": 0,
      "stream": false, // 今回はストリームでなく通常の応答を取得
      "temperature": 0.7,
      "top_p": 1
    });

    try {
      // APIリクエストを送信
      // # item_create [POST] https:10.229.154.214:3000/items
      // # item_update_status [PATCH] https:10.229.154.214:3000/items/update_status
      var response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        // レスポンスを解析して出力を取得
        var jsonResponse = jsonDecode(response.body);
        String chatGPTResponse =
            jsonResponse['choices'][0]['message']['content'];

        // AIのレスポンスをchatMessagesに追加
        setState(() {
          chatMessages.add({
            "role": "AI",
            "content": chatGPTResponse,
          });
        });

        // サーバーにメッセージを送信
        await _sendMessagesToServer([jsonDecode(chatGPTResponse)]);

        _logger.info('ChatGPTの回答: $chatGPTResponse');
      } else {
        _logger.warning('リクエスト失敗: ${response.statusCode}');
      }
    } catch (e) {
      _logger.severe('エラー: $e');
    }

    // アプリを終了する
    // SystemNavigator.pop();
  }

  @override
  void initState() {
    super.initState();

    Future(() async {
      prefs = await SharedPreferences.getInstance();

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    Future(() async {
      // スピーカーから音を出すように設定
      await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker]);

      // 音声をキューに追加する(Androidのみ)
      if (Platform.isAndroid) {
        tts.setQueueMode(1);
      }

      // 話す速度の設定
      await tts.setPitch(0.9);
      await tts.setSpeechRate(0.6);
    });

    // 設定画面を開く
    Future(() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingView()),
      );
    });
  }

  String _getVoiceName(String type) {
    return (type == "user"
            ? prefs.getString("voice_わたし")
            : prefs.getString("voice_ロボット")) ??
        "";
  }

  // 読み上げ
  Future<void> _speach(dynamic item) async {
    // 停止して再生
    await tts.stop();
    await tts
        .setVoice({'name': _getVoiceName(item["role"]), 'locale': 'ja-JP'});

    await tts.speak(item["content"]);
  }

  // 音声入力開始
  _speak() {
    Future(() async {
      // 再生を停止し
      await tts.stop();
    });

    // 入力を空にする
    setState(() {
      lastWords = "";
    });

    showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return const SpeechDialog();
      },
    ).then((value) {
      _logger.info("end dialog!");

      setState(() {
        if (value != null) {
          lastWords = value;
        }
      });

      _ai();
    });
  }

  // メッセージを消去
  Future<void> _cleanMessage() async {
    setState(() {
      chatMessages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('メッセージ削除しました'),
    ));
  }

  // ChatGPT
  Future<void> _ai() async {
    _logger.info("_ai");

    // 入力が何も無ければスキップ
    if (lastWords == "") {
      return;
    }

    // 下までスクロール
    scrollController.jumpTo(scrollController.position.maxScrollExtent);

    // 停止して再生
    await tts.stop();
    await tts.setVoice({'name': _getVoiceName("user"), 'locale': 'ja-JP'});
    // ユーザーのチャットを音声出力
    // await tts.speak(
    //   lastWords
    // );

    // 送信するメッセージを追加
    chatMessages.add({"role": "user", "content": lastWords});

    setState(() {
      inputTextcontroller.clear();

      FocusScopeNode currentFocus = FocusScope.of(context);
      if (!currentFocus.hasPrimaryFocus) {
        currentFocus.unfocus();
      }
    });

    // 現在の日時を追加して複製
    List<Object> chatMessagesClone = [
      {
        "role": "user",
        "content": DateFormat('今は yyyy年MM月dd日 HH時mm分です').format(DateTime.now())
      },
      ...chatMessages
    ];

    Uri url = Uri.parse("https://api.openai.com/v1/chat/completions");
    Map<String, String> headers = {
      'Content-type': 'application/json',
      "Authorization": "Bearer ${dotenv.get("OPEN_AI_API_KEY")}"
    };
    String body = json.encode({
      "frequency_penalty": 0,
      "max_tokens": 512,
      "messages": [
        {
          "role": "system",
          "content": """
          あなたは簡単な日常会話を通じて家の食品や日用品の在庫管理データベースの管理を手助けする役割です。自然な会話の中で、今日は何を買ったの？とか以下のリストデータで管理されている今家にあるものについて「これはもうなくなった？」みたいな質問をしてください。
          後ほどその会話データからデータベースの編集を行うので、何が買われたとか何個買ったとかをしつこくならないようにしながら、何を買って、リストにあるもので何がなくなったかを自然に聞き出してください。

          期待される行動例:
          1. まず、「今日は何か買いましたか？」と聞いてみる。
                    そうして「今日は歯ブラシを買い替えました」みたいな出力を期待しながら、会話を続ける。
          2. 会話でストレスを与えないようにしましょう。同じ質問を3度以上繰り返したり、長すぎる返事は避けましょう。
          """
        },
        ...chatMessagesClone // 他のユーザーメッセージやAIメッセージ
      ],
      "model": "ft:gpt-4o-mini-2024-07-18:lab:chatota-v2:9xWWBGSy",
      "presence_penalty": 0,
      "stream": true,
      "temperature": 0.7,
      "top_p": 1
    });

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = body;
    request.followRedirects = false;

    final response = await request.send();

    if (response.statusCode != 200) {
      setState(() {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("通信エラーが発生しました ${response.statusCode}"),
        ));
      });

      return;
    }

    _logger.info(response.statusCode);

    // 受信メッセージを追加
    chatMessages.add({"role": "assistant", "content": ""});
    setState(() {
      chatMessages = chatMessages;
    });

    var receiveMsg = "";
    var receiveMsgSpeak = "";
    var receiveDone = false;

    await for (final message in response.stream.transform(utf8.decoder)) {
      message.split("\n").forEach((msg) {
        if (!msg.startsWith("data: ")) {
          return;
        }

        var jsonMsg = msg.replaceFirst(RegExp("^data: "), "");

        if (jsonMsg == "[DONE]") {
          return;
        }

        final data = json.decode(jsonMsg);

        var content = data["choices"][0]["delta"]["content"];
        if (content == null) {
          return;
        }

        receiveMsg += content;

        receiveMsgSpeak += content;

        // まだ終わっていない時
        if (!receiveDone) {
          // 少量のテキストで喋りださないように最小数チェック
          if (receiveMsgSpeak.length > 50) {
            var stopIndex = receiveMsgSpeak.indexOf(RegExp("、|。|\n"), 50);
            if (stopIndex > 0) {
              var speackMsg = receiveMsgSpeak.substring(0, stopIndex);
              receiveMsgSpeak = receiveMsgSpeak.substring(
                  stopIndex + 1, receiveMsgSpeak.length);

              () async {
                // 受信メッセージを話す
                await tts.setVoice(
                    {'name': _getVoiceName("robot"), 'locale': 'ja-JP'});
                await tts.speak(speackMsg);
              }();
            }
          }
        }

        // 最後に追加したデータにテキストを設定する
        dynamic item = chatMessages[chatMessages.length - 1];
        item["content"] = receiveMsg;
        chatMessages[chatMessages.length - 1] = item;

        setState(() {
          chatMessages = chatMessages;

          // 下までスクロール
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        });
      });
    }

    receiveDone = true;

    // 下までスクロール
    scrollController.jumpTo(scrollController.position.maxScrollExtent);

    // 残りの受信メッセージを話す
    await tts.setVoice({'name': _getVoiceName("robot"), 'locale': 'ja-JP'});
    await tts.speak(receiveMsgSpeak);
  }

  // テキスト入力変更
  void _handleText(String e) {
    setState(() {
      lastWords = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: Text(widget.title),
          actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ListPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingView()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _exitAppWithAi, // このメソッドをボタンにセット
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: chatMessages
                      .map((dynamic item) => (GestureDetector(
                            onTap: () {
                              _speach(item);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item["role"] == "user"
                                          ? "わたし :"
                                          : "OTA bot :",
                                      style: TextStyle(
                                        color: item["role"] == "user"
                                            ? Colors.blue
                                            : Colors.green,
                                      ),
                                    ),
                                    Expanded(
                                        child: Text(
                                      item["content"],
                                      softWrap: true,
                                    ))
                                  ]),
                            ),
                          )))
                      .toList(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color.fromARGB(255, 0, 149, 255),
                    child: IconButton(
                      onPressed: _cleanMessage,
                      icon: const Icon(Icons.cleaning_services),
                      iconSize: 18,
                      color: const Color.fromARGB(255, 255, 255, 255),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: inputTextcontroller,
                    enabled: true,
                    obscureText: false,
                    maxLines: null,
                    onChanged: _handleText,
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        onPressed: _speak,
                        icon: const Icon(Icons.mic),
                      ),
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color.fromARGB(255, 0, 149, 255),
                  child: IconButton(
                    onPressed: _ai,
                    icon: const Icon(Icons.send),
                    iconSize: 18,
                    color: const Color.fromARGB(255, 255, 255, 255),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}


class SpeechDialog extends StatefulWidget {
  const SpeechDialog({Key? key}) : super(key: key);

  @override
  SpeechDialogState createState() => SpeechDialogState();
}

class SpeechDialogState extends State<SpeechDialog> {
  String lastStatus = "";
  String lastError = "";
  String lastWords = "";
  stt.SpeechToText speech = stt.SpeechToText();
  ScrollController scrollController = ScrollController();
  double soundLevel = 0;

  @override
  void initState() {
    super.initState();

    Future(() async {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    Future(() async {
      // スピーチを初期化
      bool available =
          await speech.initialize(onError: (SpeechRecognitionError error) {
        if (!mounted) {
          return;
        }
        setState(() {
          lastError = '${error.errorMsg} - ${error.permanent}';
        });
      }, onStatus: (String status) {
        if (!mounted) {
          return;
        }
        setState(() {
          lastStatus = status;
          _logger.info(status);

          // 下までスクロール
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        });
      });

      if (available) {
        speech.listen(
            onResult: (SpeechRecognitionResult result) {
              if (!mounted) {
                return;
              }

              setState(() {
                lastWords = result.recognizedWords;
              });
            },
            onSoundLevelChange: (level) {
              if (!mounted) {
                return;
              }

              setState(() {
                if (lastStatus != "listening") {
                  // TODO:iOSの時には録音準備完了の音が鳴らないので鳴らしたいがspeech.listen状態では鳴らないようです(バイブレーションも駄目)
                }
                lastStatus = "listening";
                soundLevel = level * -1;
              });
            },
            localeId: "ja-JP");
      } else {
        _logger.info("The user has denied the use of speech recognition.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
          child: Text(lastStatus == "done"
              ? "終了"
              : lastStatus == "listening"
                  ? "聞き取り中"
                  : "準備中 $lastStatus")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Text(
                lastWords,
                style: const TextStyle(color: Colors.cyan),
              ),
            ),
          ),
          CircleAvatar(
            radius: 20 + soundLevel,
            backgroundColor: lastStatus == "listening"
                ? const Color.fromARGB(255, 0, 149, 255)
                : const Color.fromARGB(255, 128, 128, 128),
            child: IconButton(
              onPressed: () {
                Navigator.of(context).pop(lastWords);
              },
              icon: const Icon(Icons.mic),
              iconSize: 18 + soundLevel,
              color: const Color.fromARGB(255, 255, 255, 255),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 必要なクリーンアップ処理を実行
    super.dispose();

    speech.stop();
  }
}
