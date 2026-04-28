import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

Map<String, dynamic> _labels = {};

void main() => runApp(const DoorrApp());

class DoorrApp extends StatefulWidget {
  const DoorrApp({super.key});

  @override
  State<DoorrApp> createState() => _DoorrAppState();
}

class _DoorrAppState extends State<DoorrApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String _lang = 'en';
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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_fontSize / 14.0)),
          child: child!,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFECEEF4),
          surfaceTintColor: Colors.transparent,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF212830),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF212830),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF30363D)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: 0,
        ),
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

  String _provider = 'prowlarr';
  List<dynamic> _allResults = [];
  List<dynamic> _filteredResults = [];
  bool _isLoading = false;
  bool _isFuzzy = false;
  String _sortBy = 'age';

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
    String jsonString = await DefaultAssetBundle.of(
      context,
    ).loadString('assets/lang.json');
    setState(() {
      _labels = jsonDecode(jsonString);
    });
  }

  bool _fuzzyMatch(String query, String text) {
    if (query.isEmpty) return true;
    query = query.toLowerCase();
    text = text.toLowerCase();
    int i = 0;
    int j = 0;
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

      _filteredResults.sort((a, b) {
        if (_sortBy == 'size') {
          return (a['size'] ?? 0).compareTo(b['size'] ?? 0);
        } else {
          return (a['age'] ?? 999).compareTo(b['age'] ?? 999);
        }
      });
    });
  }

  Widget _highlightText(String text, String query) {
    TextStyle baseStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).textTheme.bodyLarge?.color,
    );

    if (query.isEmpty)
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );

    List<TextSpan> spans = [];
    if (!_isFuzzy) {
      final escapedQuery = RegExp.escape(query);
      if (!text.toLowerCase().contains(query.toLowerCase()))
        return Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        );
      final parts = text.split(RegExp(escapedQuery, caseSensitive: false));
      int currentIndex = 0;
      for (var i = 0; i < parts.length; i++) {
        spans.add(TextSpan(text: parts[i]));
        if (i < parts.length - 1) {
          int start = text.toLowerCase().indexOf(
            query.toLowerCase(),
            currentIndex,
          );
          if (start != -1) {
            spans.add(
              TextSpan(
                text: text.substring(start, start + query.length),
                style: TextStyle(backgroundColor: Colors.blue.withOpacity(0.3)),
              ),
            );
            currentIndex = start + query.length;
          }
        }
      }
    } else {
      String lowText = text.toLowerCase();
      String lowQuery = query.toLowerCase();
      int qIdx = 0;
      for (int i = 0; i < text.length; i++) {
        if (qIdx < query.length && lowText[i] == lowQuery[qIdx]) {
          spans.add(
            TextSpan(
              text: text[i],
              style: TextStyle(backgroundColor: Colors.blue.withOpacity(0.3)),
            ),
          );
          qIdx++;
        } else {
          spans.add(TextSpan(text: text[i]));
        }
      }
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = prefs.getString('provider') ?? 'prowlarr';
    setState(() {
      _urlController.text = prefs.getString('baseUrl') ?? '';
      _keyController.text = prefs.getString('apiKey') ?? '';
      widget.onFontSizeChanged(prefs.getDouble('fontSize') ?? 14.0);
      String lang = prefs.getString('lang') ?? 'en';
      widget.onLangChanged(lang);
      _sortBy = prefs.getString('sortBy') ?? 'age';
      _isFuzzy = prefs.getBool('isFuzzy') ?? false;
      bool isDark = prefs.getBool('isDark') ?? false;
      widget.onThemeChanged(isDark);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', _provider);
    await prefs.setString('baseUrl', _urlController.text);
    await prefs.setString('apiKey', _keyController.text);
    await prefs.setDouble('fontSize', widget.currentFontSize);
    await prefs.setString('lang', widget.currentLang);
    await prefs.setString('sortBy', _sortBy);
    await prefs.setBool('isFuzzy', _isFuzzy);
    await prefs.setBool('isDark', widget.isDark);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_labels[L]!['saved']!)));
  }

  Future<void> _search(String query) async {
    if (_urlController.text.isEmpty ||
        (_keyController.text.isEmpty && _provider == 'prowlarr')) {
      _showSettingsDialog();
      return;
    }

    setState(() => _isLoading = true);
    try {
      Uri url;
      if (_provider == 'prowlarr') {
        url = Uri.parse(
          '${_urlController.text}/api/v1/search?query=$query&type=search&limit=100',
        );
      } else {
        url = Uri.parse(
          '${_urlController.text}/api/v2.0/indexers/all/results?apikey=${_keyController.text}&Query=$query',
        );
      }

      final response = await http.get(
        url,
        headers: _provider == 'prowlarr'
            ? {'X-Api-Key': _keyController.text}
            : {},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> rawList = [];
        if (_provider == 'jackett') {
          rawList = data['Results'] ?? [];
        } else {
          rawList = data is List
              ? data
              : [];
        }
        setState(() {
          _allResults = rawList.map((item) => _mapToUniversal(item)).toList();
          _applyFilter();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _mapToUniversal(dynamic item) {
    if (_provider == 'prowlarr') return item;
    int daysAge = 0;
    try {
      if (item['PublishDate'] != null) {
        DateTime pubDate = DateTime.parse(item['PublishDate']);
        daysAge = DateTime.now().difference(pubDate).inDays;
      }
    } catch (_) {}

    return {
      'title': item['Title']?.toString().trim() ?? 'No Title',
      'size': item['Size'] ?? 0,
      'indexer': item['Tracker'] ?? item['IndexerId'] ?? 'Unknown',
      'seeders': item['Seeders'] ?? 0,
      'leechers': item['Peers'] ?? 0,
      'age': daysAge,
      'downloadUrl': item['Link'] ?? item['DownloadUrl'],
      'magnetUrl': item['MagnetUri'],
      'infoUrl': item['Details'] ?? item['Guid'],
      'categories': [
        {'name': item['CategoryDesc'] ?? '—'},
      ],
    };
  }

  String _formatSize(dynamic sizeInBytes) {
    if (sizeInBytes == null) return '0 b';
    double bytes = double.tryParse(sizeInBytes.toString()) ?? 0;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Gb';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mb';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} Kb';
    } else {
      return '$bytes b';
    }
  }

  Future<void> _openUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_labels[L]!['error']}: Could not launch $urlString'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            Image.asset('assets/logo.png', width: 36, height: 40),
            const SizedBox(width: 5),
            Padding(
              padding: const EdgeInsets.only(top: 4), 
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(text: 'D', style: TextStyle(color: Colors.blue)),
                    TextSpan(text: 'o', style: TextStyle(color: Colors.blue)),
                    TextSpan(text: 'o', style: TextStyle(color: Colors.red)),
                    TextSpan(text: 'r', style: TextStyle(color: Colors.orange)),
                    TextSpan(text: 'r', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              iconSize: 30,
              color: Colors.grey,
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 8.0,
              right: 8.0,
              top: 16.0,
              bottom: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: _labels[widget.currentLang]?['search'],
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search, size: 20),
                        onPressed: () => _search(_searchController.text),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      labelText: _labels[widget.currentLang]?['filter'],
                      isDense: true,
                      suffixIcon: const Icon(Icons.filter_alt, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
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
                if (item['categories'] != null &&
                    item['categories'] is List &&
                    item['categories'].isNotEmpty) {
                  cat = item['categories'][0]['name'] ?? '—';
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _highlightText(
                          item['title'] ?? _labels[L]!['noTitle']!,
                          _filterController.text,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_labels[L]!['indexer']}: ${item['indexer']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  Text(
                                    '${_labels[L]!['category']}: $cat',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  Text(
                                    '${_labels[L]!['age']}: ${item['age'] ?? '?'} ${_labels[L]!['daysAgo']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  Text(
                                    '${_labels[L]!['size']}: ${_formatSize(item['size'])}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${item['seeders']}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${item['leechers']}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.download_for_offline,
                                    color: Colors.teal,
                                    size: 50,
                                  ),
                                  onPressed: () => _openUrl(
                                    item['downloadUrl'] ?? item['magnetUrl'],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.info,
                                    color: Colors.blue,
                                    size: 50,
                                  ),
                                  onPressed: () => _openUrl(item['infoUrl']),
                                ),
                              ],
                            ),
                          ],
                        ),
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
    String dialogLang = widget.currentLang;
    bool dialogIsDark = widget.isDark;
    double dialogFontSize = widget.currentFontSize;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: Text(_labels[dialogLang]!['settings']!),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    _labels[dialogLang]?['provider'],
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: DropdownButton<String>(
                    value: _provider,
                    items: const [
                      DropdownMenuItem(
                        value: 'prowlarr',
                        child: Text('Prowlarr'),
                      ),
                      DropdownMenuItem(
                        value: 'jackett',
                        child: Text('Jackett'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _provider = v);
                        setDS(() {});
                      }
                    },
                  ),
                ),
                ApiSettingsFields(
                  urlController: _urlController,
                  keyController: _keyController,
                ),
                FontSizeListTile(
                  labels: _labels,
                  L: dialogLang,
                  currentFontSize: dialogFontSize,
                  onChanged: (newSize) {
                    widget.onFontSizeChanged(newSize);
                    setDS(() => dialogFontSize = newSize);
                  },
                ),
                DropdownButtonListTile(
                  labels: _labels,
                  L: dialogLang,
                  current: dialogLang,
                  onChanged: (v) {
                    if (v != null) {
                      widget.onLangChanged(v);
                      setDS(() => dialogLang = v);
                    }
                  },
                ),
                SortListTile(
                  labels: _labels,
                  L: dialogLang,
                  sortBy: _sortBy,
                  onChanged: (v) {
                    setState(() => _sortBy = v!);
                    setDS(() {});
                    _applyFilter();
                  },
                ),
                FuzzySwitchTile(
                  labels: _labels,
                  L: dialogLang,
                  isFuzzy: _isFuzzy,
                  onChanged: (v) {
                    setState(() => _isFuzzy = v);
                    setDS(() {});
                    _applyFilter();
                  },
                ),
                ThemeSwitchTile(
                  labels: _labels,
                  L: dialogLang,
                  isDark: dialogIsDark,
                  onChanged: (v) {
                    widget.onThemeChanged(v);
                    setDS(() => dialogIsDark = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_labels[dialogLang]!['cancel']!),
            ),
            ElevatedButton(
              onPressed: () {
                _saveSettings();
                Navigator.pop(context);
              },
              child: Text(_labels[dialogLang]!['save']!),
            ),
          ],
        ),
      ),
    );
  }
}

class ApiSettingsFields extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController keyController;
  const ApiSettingsFields({
    super.key,
    required this.urlController,
    required this.keyController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: urlController,
          decoration: const InputDecoration(labelText: 'Url'),
        ),
        TextField(
          controller: keyController,
          decoration: const InputDecoration(labelText: 'API Key'),
        ),
      ],
    );
  }
}

class FontSizeListTile extends StatelessWidget {
  final Map labels;
  final String L;
  final double currentFontSize;
  final ValueChanged<double> onChanged;
  const FontSizeListTile({
    super.key,
    required this.labels,
    required this.L,
    required this.currentFontSize,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(labels[L]!['size']!, style: const TextStyle(fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: currentFontSize > 10
                ? () => onChanged(currentFontSize - 1)
                : null,
          ),
          Text(
            currentFontSize.round().toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: currentFontSize < 24
                ? () => onChanged(currentFontSize + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class SortListTile extends StatelessWidget {
  final Map labels;
  final String L;
  final String sortBy;
  final ValueChanged<String?> onChanged;
  const SortListTile({
    super.key,
    required this.labels,
    required this.L,
    required this.sortBy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        labels[L]!['sort'] ?? 'Сортировка',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: DropdownButton<String>(
        value: sortBy,
        items: [
          DropdownMenuItem(
            value: 'age',
            child: Text(labels[L]!['sortAge'] ?? 'По дате'),
          ),
          DropdownMenuItem(
            value: 'size',
            child: Text(labels[L]!['sortSize'] ?? 'По размеру'),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class FuzzySwitchTile extends StatelessWidget {
  final Map labels;
  final String L;
  final bool isFuzzy;
  final ValueChanged<bool> onChanged;
  const FuzzySwitchTile({
    super.key,
    required this.labels,
    required this.L,
    required this.isFuzzy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(labels[L]!['fuzzy']!, style: const TextStyle(fontSize: 13)),
      value: isFuzzy,
      onChanged: onChanged,
    );
  }
}

class ThemeSwitchTile extends StatelessWidget {
  final Map labels;
  final String L;
  final bool isDark;
  final ValueChanged<bool> onChanged;
  const ThemeSwitchTile({
    super.key,
    required this.labels,
    required this.L,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(
        labels[L]!['darkMode']!,
        style: const TextStyle(fontSize: 13),
      ),
      value: isDark,
      onChanged: onChanged,
    );
  }
}

class DropdownButtonListTile extends StatelessWidget {
  final Map labels;
  final String L;
  final String current;
  final ValueChanged<String?> onChanged;

  const DropdownButtonListTile({
    super.key,
    required this.labels,
    required this.L,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final availableLanguages = labels.keys.toList();
    return ListTile(
      title: Text(
        labels[L]?['lang'] ?? 'Language',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: DropdownButton<String>(
        value: current,
        items: availableLanguages.map((langCode) {
          return DropdownMenuItem(
            value: langCode.toString(),
            child: Text(langCode.toString().toUpperCase()),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
