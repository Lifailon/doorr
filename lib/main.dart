import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const ProwlarrApp());

class ProwlarrApp extends StatelessWidget {
  const ProwlarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const SearchScreen(),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _filterController = TextEditingController(); // Контроллер фильтра
  
  List<dynamic> _allResults = []; // Все результаты от API
  List<dynamic> _filteredResults = []; // Отфильтрованные результаты
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Привязываем функцию фильтрации к полю ввода
    _filterController.addListener(_applyFilter);
  }

  // Мгновенный фильтр по списку
  void _applyFilter() {
    final query = _filterController.text.toLowerCase();
    setState(() {
      _filteredResults = _allResults.where((item) {
        final title = (item['title'] ?? '').toString().toLowerCase();
        return title.contains(query);
      }).toList();
    });
  }

  // Функция для расчета "возраста" раздачи
  String _calculateAge(String? dateStr) {
    if (dateStr == null) return '?';
    try {
      final publishDate = DateTime.parse(dateStr);
      final difference = DateTime.now().difference(publishDate);
      if (difference.inDays > 0) return '${difference.inDays}д';
      if (difference.inHours > 0) return '${difference.inHours}ч';
      return '${difference.inMinutes}м';
    } catch (e) {
      return '?';
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('baseUrl') ?? '';
      _keyController.text = prefs.getString('apiKey') ?? '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', _urlController.text);
    await prefs.setString('apiKey', _keyController.text);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
  }

  Future<void> _search(String query) async {
    if (_urlController.text.isEmpty || _keyController.text.isEmpty) {
      _showSettingsDialog(); 
      return;
    }

    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('${_urlController.text}/api/v1/search?query=$query&type=search&limit=100');
      final response = await http.get(url, headers: {'X-Api-Key': _keyController.text});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _allResults = data;
          _filteredResults = data; // При новом поиске сбрасываем фильтр
          _filterController.clear(); // Очищаем поле фильтра
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prowlarr Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Поиск торрентов',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: TextField(
              controller: _filterController,
              decoration: const InputDecoration(
                labelText: 'Фильтр по списку...',
                suffixIcon: Icon(Icons.filter_alt),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredResults.length,
              itemBuilder: (context, index) {
                final item = _filteredResults[index];
                // Извлекаем название категории из списка
                String categoryName = '—';
                if (item['categories'] != null && item['categories'] is List && item['categories'].isNotEmpty) {
                  categoryName = item['categories'][0]['name'] ?? '—';
                }
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(item['title'] ?? 'Без названия', 
                        maxLines: 2, overflow: TextOverflow.ellipsis, 
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Индексатор: ${item['indexer']}', style: const TextStyle(fontSize: 12)),
                        
                        // Категория и Возраст в столбик одним шрифтом
                        Text('Категория: $categoryName', 
                            style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        Text('Возраст: ${item['age'] ?? '?'} дн. назад', 
                            style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            
                        Text('Размер: ${(item['size'] / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB', 
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('S: ${item['seeders']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        Text('L: ${item['leechers']}', style: const TextStyle(color: Colors.red, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки API'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _urlController, decoration: const InputDecoration(labelText: 'Base URL')),
            TextField(controller: _keyController, decoration: const InputDecoration(labelText: 'API Key')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
