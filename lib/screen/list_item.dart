import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// アイテムを表すモデルクラス
class Item {
  final String title;      // タイトル
  final String expiryDate; // 賞味期限
  final List<String> badges; // バッジのリスト
  final String status;

  Item({
    required this.title,
    required this.expiryDate,
    required this.badges,
    required this.status,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      title: json['display_name'],
      expiryDate: json['expiry_date'],
      badges: List<String>.from(json['category_names']),
      status: json['status'],
    );
  }
}

class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  Future<List<Item>> fetchItems() async {
    final response = await http.get(Uri.parse(baseUrl));

    if (response.statusCode == 200) {
      List<dynamic> jsonResponse = json.decode(response.body);
      return jsonResponse.map((data) => Item.fromJson(data)).toList();
    } else {
      throw Exception('Failed to load items');
    }
  }
}

class ListPage extends StatefulWidget {
  const ListPage({super.key});

  @override
  _ListPageState createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  late Future<List<Item>> futureItems;

  @override
  void initState() {
    super.initState();
    // APIからアイテムを取得する
    // TODO: User識別
    final apiService = ApiService('http://${dotenv.get("SERVER_HOST")}:${dotenv.get("SERVER_PORT")}/items?user_id=1'); // 実際のAPI URLを指定
    futureItems = apiService.fetchItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('リストページ'),
      ),
      body: FutureBuilder<List<Item>>(
        future: futureItems,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('アイテムがありません'));
          }

          final items = snapshot.data!;

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: const Icon(Icons.chat),
                title: Text(item.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('賞味期限: ${item.expiryDate}'),
                    Text('ステータス: ${item.status}'),
                    Wrap(
                      children: item.badges.map((badge) => Chip(label: Text(badge))).toList(),
                    ),
                  ],
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${item.title} がタップされました')),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}