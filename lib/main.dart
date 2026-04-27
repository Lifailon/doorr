import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Map<String, dynamic> _labels = {}; 

void main() => runApp(const DoorrApp());

class DoorrApp extends StatefulWidget {
  const DoorrApp({super.key});

  @override
  State<DoorrApp> createState() => _DoorrAppState();
}

class _DoorrAppState extends State<DoorrApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String _lang = 'ru';
  double _fontSize = 14.0;

  void updateFontSize(double size) {
    setState(() => _fontSize = size);
  }

  void updateTheme(bool isDark) {
    setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void updateLang(String lang) {
    setState(() => _lang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_fontSize / 14.0),
          ),
          child: child!,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
      ),
      home: SearchScreen(
        onThemeChanged: updateTheme,
        onLangChanged: updateLang,
        currentLang: _lang,
        isDark: _themeMode == ThemeMode.dark,
        currentFontSize: _fontSize,
        onFontSizeChanged: updateFontSize,
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final Function(String) onLangChanged;
  final String currentLang;
  final bool isDark;
  final double currentFontSize;
  final Function(double) onFontSizeChanged;

  const SearchScreen({
    super.key, 
    required this.onThemeChanged, 
    required this.onLangChanged, 
    required this.currentLang,
    required this.isDark,
    required this.currentFontSize,
    required this.onFontSizeChanged,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  
  List<dynamic> _allResults = [];
  List<dynamic> _filteredResults = [];
  bool _isLoading = false;
  bool _isFuzzy = false;

  String get L => widget.currentLang;

  @override
  void initState() {
    super.initState();
    _setupApp();
    _filterController.addListener(_applyFilter);
  }

  Future<void> _setupApp() async {
    await _loadLangFile();
    await _loadSettings();
  }

  Future<void> _loadLangFile() async {
    String jsonString = await DefaultAssetBundle.of(context).loadString('assets/lang.json');
    setState(() {
      _labels = jsonDecode(jsonString);
    });
  }

  bool _fuzzyMatch(String query, String text) {
    if (query.isEmpty) return true;
    query = query.toLowerCase();
    text = text.toLowerCase();
    int i = 0; int j = 0;
    while (i < query.length && j < text.length) {
      if (query[i] == text[j]) i++;
      j++;
    }
    return i == query.length;
  }

  void _applyFilter() {
    final query = _filterController.text.toLowerCase();
    setState(() {
      _filteredResults = _allResults.where((item) {
        final title = (item['title'] ?? '').toString().toLowerCase();
        return _isFuzzy ? _fuzzyMatch(query, title) : title.contains(query);
      }).toList();
    });
  }

  Widget _highlightText(String text, String query) {
    TextStyle baseStyle = TextStyle(
      fontSize: 14, 
      fontWeight: FontWeight.bold, 
      color: Theme.of(context).textTheme.bodyLarge?.color
    );
    
    if (query.isEmpty) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: baseStyle);

    List<TextSpan> spans = [];
    if (!_isFuzzy) {
      final escapedQuery = RegExp.escape(query);
      if (!text.toLowerCase().contains(query.toLowerCase())) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: baseStyle);
      final parts = text.split(RegExp(escapedQuery, caseSensitive: false));
      int currentIndex = 0;
      for (var i = 0; i < parts.length; i++) {
        spans.add(TextSpan(text: parts[i]));
        if (i < parts.length - 1) {
          int start = text.toLowerCase().indexOf(query.toLowerCase(), currentIndex);
          if (start != -1) {
            spans.add(TextSpan(text: text.substring(start, start + query.length), style: TextStyle(backgroundColor: Colors.blue.withOpacity(0.3))));
            currentIndex = start + query.length;
          }
        }
      }
    } else {
      String lowText = text.toLowerCase(); String lowQuery = query.toLowerCase();
      int qIdx = 0;
      for (int i = 0; i < text.length; i++) {
        if (qIdx < query.length && lowText[i] == lowQuery[qIdx]) {
          spans.add(TextSpan(text: text[i], style: TextStyle(backgroundColor: Colors.blue.withOpacity(0.3))));
          qIdx++;
        } else { spans.add(TextSpan(text: text[i])); }
      }
    }
    return RichText(maxLines: 2, overflow: TextOverflow.ellipsis, text: TextSpan(style: baseStyle, children: spans));
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('baseUrl') ?? '';
      _keyController.text = prefs.getString('apiKey') ?? '';
      String lang = prefs.getString('lang') ?? 'ru';
      widget.onLangChanged(lang);
      widget.onFontSizeChanged(prefs.getDouble('fontSize') ?? 14.0);
      _isFuzzy = prefs.getBool('isFuzzy') ?? false;
      bool isDark = prefs.getBool('isDark') ?? false;
      widget.onThemeChanged(isDark);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', _urlController.text);
    await prefs.setString('apiKey', _keyController.text);    
    await prefs.setString('lang', widget.currentLang);
    await prefs.setDouble('fontSize', widget.currentFontSize);
    await prefs.setBool('isFuzzy', _isFuzzy);
    await prefs.setBool('isDark', widget.isDark);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_labels[L]!['saved']!))
    );
  }

  Future<void> _search(String query) async {
    if (_urlController.text.isEmpty || _keyController.text.isEmpty) { _showSettingsDialog(); return; }
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('${_urlController.text}/api/v1/search?query=$query&type=search&limit=100');
      final response = await http.get(url, headers: {'X-Api-Key': _keyController.text});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() { _allResults = data; _applyFilter(); _filterController.clear(); });
      }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_labels[L]!['error']}: $e')));
    } finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      title: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            width: 24,
            height: 28,
          ),
          const SizedBox(width: 10),
          const Text('Doorr'),
        ],
      ),
      actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsDialog)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(flex: 2, child: TextField(controller: _searchController, decoration: InputDecoration(labelText: _labels[L]!['search'], isDense: true, suffixIcon: IconButton(icon: const Icon(Icons.search, size: 20), onPressed: () => _search(_searchController.text)), border: const OutlineInputBorder()), onSubmitted: _search)),
                const SizedBox(width: 8),
                Expanded(flex: 1, child: TextField(controller: _filterController, decoration: InputDecoration(labelText: _labels[L]!['filter'], isDense: true, suffixIcon: const Icon(Icons.filter_alt, size: 18), border: const OutlineInputBorder()))),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredResults.length,
              itemBuilder: (context, index) {
                final item = _filteredResults[index];
                String cat = '—';
                if (item['categories'] != null && item['categories'] is List && item['categories'].isNotEmpty) { cat = item['categories'][0]['name'] ?? '—'; }
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: _highlightText(item['title'] ?? _labels[L]!['no_title']!, _filterController.text),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('${_labels[L]!['indexer']}: ${item['indexer']}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        Text('${_labels[L]!['category']}: $cat', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        Text('${_labels[L]!['age']}: ${item['age'] ?? '?'} ${_labels[L]!['days_ago']}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        Text('${_labels[L]!['size']}: ${(item['size'] / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${item['seeders']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        Text('${item['leechers']}', style: const TextStyle(color: Colors.red, fontSize: 11)),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: Text(_labels[L]!['settings']!),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(labelText: _labels[L]!['url'])
                ),
                TextField(
                  controller: _keyController,
                  decoration: InputDecoration(labelText: _labels[L]!['apiKey'])
                ),
                const Divider(),
                DropdownButtonListTile(L: L, current: L, onChanged: (v) { widget.onLangChanged(v!); setDS((){}); }),
                ListTile(
                  title: Text(_labels[L]!['size']!, style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () {
                          if (widget.currentFontSize > 10) {
                            widget.onFontSizeChanged(widget.currentFontSize - 1);
                            setDS(() {});
                          }
                        },
                      ),
                      Text(
                        widget.currentFontSize.round().toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () {
                          if (widget.currentFontSize < 24) {
                            widget.onFontSizeChanged(widget.currentFontSize + 1);
                            setDS(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SwitchListTile(title: Text(_labels[L]!['fuzzy']!, style: const TextStyle(fontSize: 13)), value: _isFuzzy, onChanged: (v) { setState(() => _isFuzzy = v); setDS(() {}); _applyFilter(); }),
                SwitchListTile(title: Text(_labels[L]!['dark_mode']!, style: const TextStyle(fontSize: 13)), value: widget.isDark, onChanged: (v) { widget.onThemeChanged(v); setDS(() {}); }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_labels[L]!['cancel']!)),
            ElevatedButton(onPressed: () { _saveSettings(); Navigator.pop(context); }, child: Text(_labels[L]!['save']!)),
          ],
        ),
      ),
    );
  }
}

class DropdownButtonListTile extends StatelessWidget {
  final String L; final String current; final ValueChanged<String?> onChanged;
  const DropdownButtonListTile({super.key, required this.L, required this.current, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(L == 'ru' ? 'Язык' : 'Language', style: const TextStyle(fontSize: 13)),
      trailing: DropdownButton<String>(
        value: current,
        items: const [DropdownMenuItem(value: 'ru', child: Text('RU')), DropdownMenuItem(value: 'en', child: Text('EN'))],
        onChanged: onChanged,
      ),
    );
  }
}
