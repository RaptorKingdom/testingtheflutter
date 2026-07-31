import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:html/parser.dart' as html_parser;
import 'package:shamsi_date/shamsi_date.dart';
import 'package:persian_datepicker/persian_datepicker.dart';
import 'package:auto_size_text/auto_size_text.dart';

part 'main.g.dart'; // Hive generated file

// -------------------- Models --------------------
@HiveType(typeId: 0)
class GoldTransaction extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String type;
  @HiveField(2)
  DateTime purchaseDate;
  @HiveField(3)
  double purchasePricePerUnit;
  @HiveField(4)
  double quantity;
  @HiveField(5)
  String description;
  @HiveField(6)
  double remainingQuantity;

  GoldTransaction({
    required this.id,
    required this.type,
    required this.purchaseDate,
    required this.purchasePricePerUnit,
    required this.quantity,
    required this.description,
    double? remainingQuantity,
  }) : remainingQuantity = remainingQuantity ?? quantity;
}

@HiveType(typeId: 1)
class CoinTransaction extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String coinType;
  @HiveField(2)
  DateTime purchaseDate;
  @HiveField(3)
  double purchasePricePerUnit;
  @HiveField(4)
  int count;
  @HiveField(5)
  String description;
  @HiveField(6)
  int remainingCount;

  CoinTransaction({
    required this.id,
    required this.coinType,
    required this.purchaseDate,
    required this.purchasePricePerUnit,
    required this.count,
    required this.description,
    int? remainingCount,
  }) : remainingCount = remainingCount ?? count;
}

@HiveType(typeId: 2)
class SaleTransaction extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String lotId;
  @HiveField(2)
  DateTime saleDate;
  @HiveField(3)
  double salePricePerUnit;
  @HiveField(4)
  double quantity;
  @HiveField(5)
  bool isGold;
  @HiveField(6)
  String? coinType;

  SaleTransaction({
    required this.id,
    required this.lotId,
    required this.saleDate,
    required this.salePricePerUnit,
    required this.quantity,
    required this.isGold,
    this.coinType,
  });
}

// -------------------- Price Models --------------------
class PriceResponse {
  final String name;
  final double? currentPrice;
  final double? high;
  final double? low;
  final double? yesterdayAvg;
  final Change? change;

  PriceResponse({
    required this.name,
    this.currentPrice,
    this.high,
    this.low,
    this.yesterdayAvg,
    this.change,
  });

  factory PriceResponse.fromJson(Map<String, dynamic> json) {
    return PriceResponse(
      name: json['name'] ?? '',
      currentPrice: json['current_price'] != null ? (json['current_price'] as num).toDouble() : null,
      high: json['high'] != null ? (json['high'] as num).toDouble() : null,
      low: json['low'] != null ? (json['low'] as num).toDouble() : null,
      yesterdayAvg: json['yesterday_avg'] != null ? (json['yesterday_avg'] as num).toDouble() : null,
      change: json['change'] != null ? Change.fromJson(json['change']) : null,
    );
  }
}

class Change {
  final double? value;
  final double? percent;
  final String? direction;

  Change({this.value, this.percent, this.direction});

  factory Change.fromJson(Map<String, dynamic> json) {
    return Change(
      value: json['value'] != null ? (json['value'] as num).toDouble() : null,
      percent: json['percent'] != null ? (json['percent'] as num).toDouble() : null,
      direction: json['direction'],
    );
  }
}

// -------------------- API Service --------------------
class ApiService {
  static const String _pageUrl = 'https://www.estjt.ir/price/';
  static const Map<String, String> _nameToKey = {
    'انس طلا': 'gold_ons',
    'مظنه تهران': 'gold_mazneh',
    'طلای ۱۸ عیار': 'gold_18',
    'طلای ۲۴ عیار': 'gold_24',
    'سکه طرح قدیم': 'coin_old',
    'سکه طرح جدید': 'coin_new',
    'نیم سکه': 'coin_half',
    'ربع سکه': 'coin_quarter',
    'سکه یک گرمی': 'coin_1g',
  };

  static String _persianToEnglish(String s) {
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const englishDigits = '0123456789';
    final result = StringBuffer();
    for (final ch in s.runes) {
      final char = String.fromCharCode(ch);
      final idx = persianDigits.indexOf(char);
      if (idx != -1) {
        result.write(englishDigits[idx]);
      } else {
        result.write(char);
      }
    }
    return result.toString();
  }

  static double? _parsePrice(String text) {
    if (text.trim() == '—') return null;
    final cleaned = _persianToEnglish(text).replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static Map<String, double?>? _parseChange(String changeText) {
    final text = _persianToEnglish(changeText);
    final match = RegExp(r'([\d.]+)\s*\(([\d.]+)\)').firstMatch(text);
    if (match != null) {
      final value = double.tryParse(match.group(1)!);
      final percent = double.tryParse(match.group(2)!);
      return {'value': value, 'percent': percent};
    }
    return null;
  }

  static Future<Map<String, PriceResponse>> fetchAllPrices() async {
    try {
      final response = await http.get(
        Uri.parse(_pageUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );
      if (response.statusCode != 200) return {};
      final document = html_parser.parse(response.body);
      final rows = document.querySelectorAll('div.price-box table tbody tr');
      final Map<String, PriceResponse> prices = {};
      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 6) continue;
        final name = cells[0].text.trim();
        final key = _nameToKey[name];
        if (key == null) continue;
        var current = _parsePrice(cells[1].text.trim());
        var high = _parsePrice(cells[2].text.trim());
        var low = _parsePrice(cells[3].text.trim());
        var yesterdayAvg = _parsePrice(cells[4].text.trim());
        String? direction;
        double? changeVal;
        double? changePercent;
        final changeSpan = cells[5].querySelector('span');
        if (changeSpan != null) {
          if (changeSpan.classes.contains('asc')) {
            direction = 'up';
          } else if (changeSpan.classes.contains('desc')) {
            direction = 'down';
          }
          final changeData = _parseChange(changeSpan.text.trim());
          if (changeData != null) {
            changeVal = changeData['value'];
            changePercent = changeData['percent'];
          }
        }
        prices[key] = PriceResponse(
          name: name,
          currentPrice: current,
          high: high,
          low: low,
          yesterdayAvg: yesterdayAvg,
          change: Change(value: changeVal, percent: changePercent, direction: direction),
        );
      }
      return prices;
    } catch (e) {
      return {};
    }
  }
}

// -------------------- Utility functions --------------------
String formatRial(double amount) {
  final f = NumberFormat('#,###', 'fa');
  return f.format(amount);
}

String formatJalaliDate(DateTime dt) {
  final j = Jalali.fromDateTime(dt);
  return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
}

String coinName(String type) {
  switch (type) {
    case 'coin_new': return 'سکه تمام (امامی)';
    case 'coin_old': return 'سکه تمام (قدیم)';
    case 'coin_half': return 'نیم سکه';
    case 'coin_quarter': return 'ربع سکه';
    case 'coin_1g': return 'سکه یک گرمی';
    default: return type;
  }
}

String goldTypeName(String key) {
  switch (key) {
    case 'gold_18': return 'طلای ۱۸ عیار';
    case 'gold_24': return 'طلای ۲۴ عیار';
    case 'gold_ons': return 'انس طلا';
    case 'gold_mazneh': return 'مظنه تهران';
    default: return key;
  }
}

// -------------------- Providers --------------------
class PriceProvider extends ChangeNotifier {
  Map<String, PriceResponse> _prices = {};
  Map<String, PriceResponse> _lastSavedPrices = {};
  DateTime _lastUpdated = DateTime(2000);
  Timer? _timer;
  final SharedPreferences _prefs;

  static const List<String> _priceKeys = [
    'gold_18', 'gold_24', 'gold_ons', 'gold_mazneh',
    'coin_old', 'coin_new', 'coin_half', 'coin_quarter', 'coin_1g'
  ];

  Map<String, PriceResponse> get prices => UnmodifiableMapView(_prices);
  DateTime get lastUpdated => _lastUpdated;

  PriceProvider(this._prefs) {
    _loadSavedPrices();
    fetchPrices();
    startAutoUpdate();
  }

  void _loadSavedPrices() {
    _lastSavedPrices = {};
    for (var key in _priceKeys) {
      String? jsonStr = _prefs.getString('price_$key');
      if (jsonStr != null) {
        try {
          final json = jsonDecode(jsonStr);
          _lastSavedPrices[key] = PriceResponse.fromJson(json);
        } catch (e) {}
      }
    }
    if (_lastSavedPrices.isNotEmpty) {
      _prices = Map.from(_lastSavedPrices);
      int? savedTime = _prefs.getInt('last_update');
      if (savedTime != null) _lastUpdated = DateTime.fromMillisecondsSinceEpoch(savedTime);
    }
  }

  Future<void> _savePrices(Map<String, PriceResponse> prices) async {
    for (var entry in prices.entries) {
      final jsonStr = jsonEncode({
        'name': entry.value.name,
        'current_price': entry.value.currentPrice,
        'high': entry.value.high,
        'low': entry.value.low,
        'yesterday_avg': entry.value.yesterdayAvg,
        'change': entry.value.change != null
            ? {
                'value': entry.value.change!.value,
                'percent': entry.value.change!.percent,
                'direction': entry.value.change!.direction,
              }
            : null,
      });
      await _prefs.setString('price_${entry.key}', jsonStr);
    }
    await _prefs.setInt('last_update', DateTime.now().millisecondsSinceEpoch);
  }

  void startAutoUpdate({int intervalSeconds = 300}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => fetchPrices());
  }

  void setAutoUpdateInterval(int seconds) {
    startAutoUpdate(intervalSeconds: seconds);
  }

  Future<void> fetchPrices() async {
    final newPrices = await ApiService.fetchAllPrices();
    if (newPrices.isNotEmpty) {
      _prices = newPrices;
      _lastSavedPrices = Map.from(newPrices);
      _lastUpdated = DateTime.now();
      await _savePrices(newPrices);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class SettingsProvider extends ChangeNotifier {
  double _bankInterestRate = 26.0;
  int _autoUpdateInterval = 300;

  double get bankInterestRate => _bankInterestRate;
  int get autoUpdateInterval => _autoUpdateInterval;

  final SharedPreferences _prefs;
  SettingsProvider(this._prefs) { _loadSettings(); }

  void _loadSettings() {
    _bankInterestRate = _prefs.getDouble('bankInterestRate') ?? 26.0;
    _autoUpdateInterval = _prefs.getInt('autoUpdateInterval') ?? 300;
  }

  Future<void> setBankInterestRate(double value) async {
    _bankInterestRate = value;
    await _prefs.setDouble('bankInterestRate', value);
    notifyListeners();
  }

  Future<void> setAutoUpdateInterval(int seconds) async {
    _autoUpdateInterval = seconds;
    await _prefs.setInt('autoUpdateInterval', seconds);
    notifyListeners();
  }
}

class BasePriceProvider extends ChangeNotifier {
  Map<String, double> _basePrices = {};
  final SharedPreferences _prefs;

  BasePriceProvider(this._prefs) { _loadBasePrices(); }
  Map<String, double> get basePrices => UnmodifiableMapView(_basePrices);

  void _loadBasePrices() {
    final jsonStr = _prefs.getString('basePrices');
    if (jsonStr != null) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      _basePrices = map.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } else {
      _basePrices = {
        'gold_18': 0, 'gold_24': 0, 'gold_ons': 0, 'gold_mazneh': 0,
        'coin_old': 0, 'coin_new': 0, 'coin_half': 0, 'coin_quarter': 0, 'coin_1g': 0,
      };
    }
    notifyListeners();
  }

  Future<void> setBasePrice(String key, double value) async {
    _basePrices[key] = value;
    await _prefs.setString('basePrices', jsonEncode(_basePrices));
    notifyListeners();
  }
}

class DataProvider extends ChangeNotifier {
  final Box<GoldTransaction> goldBox;
  final Box<CoinTransaction> coinBox;
  final Box<SaleTransaction> saleBox;

  DataProvider({
    required this.goldBox,
    required this.coinBox,
    required this.saleBox,
  }) {
    if (goldBox.isEmpty && coinBox.isEmpty) _addDefaultData();
  }

  void _addDefaultData() {
    goldBox.addAll([
      GoldTransaction(id: '1', type: 'gold_18', purchaseDate: DateTime(2025,1,2), purchasePricePerUnit: 52518583, quantity: 100, description: ''),
      GoldTransaction(id: '2', type: 'gold_18', purchaseDate: DateTime(2025,2,9), purchasePricePerUnit: 65792511, quantity: 61.195, description: ''),
      GoldTransaction(id: '3', type: 'gold_18', purchaseDate: DateTime(2025,4,13), purchasePricePerUnit: 76180802, quantity: 50, description: ''),
      GoldTransaction(id: '4', type: 'gold_18', purchaseDate: DateTime(2025,10,6), purchasePricePerUnit: 105960571, quantity: 100, description: ''),
      GoldTransaction(id: '5', type: 'gold_18', purchaseDate: DateTime(2025,11,10), purchasePricePerUnit: 105730000, quantity: 60, description: ''),
      GoldTransaction(id: '6', type: 'gold_18', purchaseDate: DateTime(2025,12,14), purchasePricePerUnit: 138048000, quantity: 15, description: ''),
    ]);
    coinBox.addAll([
      CoinTransaction(id: 'c1', coinType: 'coin_quarter', purchaseDate: DateTime(2023,1,17), purchasePricePerUnit: 70500000, count: 3, description: 'خرید از بورس کالای کارگزاری آگاه'),
      CoinTransaction(id: 'c2', coinType: 'coin_new', purchaseDate: DateTime(2025,1,1), purchasePricePerUnit: 560000000, count: 2, description: 'خرید از زهرا'),
      CoinTransaction(id: 'c3', coinType: 'coin_quarter', purchaseDate: DateTime(2025,1,1), purchasePricePerUnit: 174000000, count: 1, description: 'خرید از زهرا'),
      CoinTransaction(id: 'c4', coinType: 'coin_new', purchaseDate: DateTime(2025,9,8), purchasePricePerUnit: 832224932, count: 6, description: 'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id: 'c5', coinType: 'coin_half', purchaseDate: DateTime(2025,9,8), purchasePricePerUnit: 441195425, count: 10, description: 'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id: 'c6', coinType: 'coin_quarter', purchaseDate: DateTime(2025,9,8), purchasePricePerUnit: 257758617, count: 14, description: 'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id: 'c7', coinType: 'coin_half', purchaseDate: DateTime(2025,11,12), purchasePricePerUnit: 575585000, count: 1, description: 'خرید از مرکز مبادلات کاربری مریم'),
      CoinTransaction(id: 'c8', coinType: 'coin_quarter', purchaseDate: DateTime(2025,11,12), purchasePricePerUnit: 327850000, count: 2, description: 'خرید از مرکز مبادلات کابری مریم'),
      CoinTransaction(id: 'c9', coinType: 'coin_new', purchaseDate: DateTime(2026,2,15), purchasePricePerUnit: 1930000000, count: 4, description: 'خرید از علی بابت پول ماشین'),
      CoinTransaction(id: 'c10', coinType: 'coin_quarter', purchaseDate: DateTime(2026,2,15), purchasePricePerUnit: 525000000, count: 6, description: 'خرید از علی بابت پول ماشین'),
      CoinTransaction(id: 'c11', coinType: 'coin_half', purchaseDate: DateTime(2026,2,15), purchasePricePerUnit: 970000000, count: 3, description: 'خرید از علی بابت پول ماشین'),
    ]);
  }

  List<GoldTransaction> get activeGold => goldBox.values.where((g) => g.remainingQuantity > 0).toList();
  List<CoinTransaction> get activeCoins => coinBox.values.where((c) => c.remainingCount > 0).toList();

  Future<void> addGold(GoldTransaction t) async { await goldBox.add(t); notifyListeners(); }
  Future<void> updateGold(GoldTransaction t) async { await t.save(); notifyListeners(); }
  Future<void> deleteGold(GoldTransaction t) async { await t.delete(); notifyListeners(); }
  Future<void> addCoin(CoinTransaction t) async { await coinBox.add(t); notifyListeners(); }
  Future<void> updateCoin(CoinTransaction t) async { await t.save(); notifyListeners(); }
  Future<void> deleteCoin(CoinTransaction t) async { await t.delete(); notifyListeners(); }

  Future<void> sellGold(GoldTransaction lot, double quantity, double pricePerUnit) async {
    if (quantity <= 0 || quantity > lot.remainingQuantity) return;
    lot.remainingQuantity -= quantity;
    final sale = SaleTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lotId: lot.id,
      saleDate: DateTime.now(),
      salePricePerUnit: pricePerUnit,
      quantity: quantity,
      isGold: true,
    );
    await saleBox.add(sale);
    if (lot.remainingQuantity <= 0.0001) await lot.delete();
    else await lot.save();
    notifyListeners();
  }

  Future<void> sellCoin(CoinTransaction lot, int count, double pricePerUnit) async {
    if (count <= 0 || count > lot.remainingCount) return;
    lot.remainingCount -= count;
    final sale = SaleTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lotId: lot.id,
      saleDate: DateTime.now(),
      salePricePerUnit: pricePerUnit,
      quantity: count.toDouble(),
      isGold: false,
      coinType: lot.coinType,
    );
    await saleBox.add(sale);
    if (lot.remainingCount == 0) await lot.delete();
    else await lot.save();
    notifyListeners();
  }

  double get totalRealizedProfit {
    double profit = 0;
    for (var sale in saleBox.values) {
      double purchasePrice = 0;
      if (sale.isGold) {
        final lot = goldBox.get(sale.lotId);
        if (lot != null) purchasePrice = lot.purchasePricePerUnit;
      } else {
        final lot = coinBox.get(sale.lotId);
        if (lot != null) purchasePrice = lot.purchasePricePerUnit;
      }
      profit += (sale.salePricePerUnit - purchasePrice) * sale.quantity;
    }
    return profit;
  }
}

// -------------------- Screens --------------------
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final basePriceProvider = Provider.of<BasePriceProvider>(context);
    final basePrices = basePriceProvider.basePrices;

    final DateTime startOf1405 = DateTime(2026, 3, 21);
    final DateTime endOf1404 = DateTime(2026, 3, 20);

    double totalGoldValue = 0, totalGoldCost = 0;
    double totalCoinValue = 0, totalCoinCost = 0;
    for (var g in dataProvider.activeGold) {
      final cp = priceProvider.prices[g.type]?.currentPrice ?? 0;
      totalGoldValue += cp * g.remainingQuantity;
      totalGoldCost += g.purchasePricePerUnit * g.remainingQuantity;
    }
    for (var c in dataProvider.activeCoins) {
      final cp = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
      totalCoinValue += cp * c.remainingCount;
      totalCoinCost += c.purchasePricePerUnit * c.remainingCount;
    }

    final totalAssets = totalGoldValue + totalCoinValue;
    final unrealizedProfit = totalAssets - (totalGoldCost + totalCoinCost);
    final realizedProfit = dataProvider.totalRealizedProfit;

    double base1405Cost = 0;
    for (var g in dataProvider.activeGold) {
      base1405Cost += (basePrices[g.type] ?? 0) * g.remainingQuantity;
    }
    for (var c in dataProvider.activeCoins) {
      base1405Cost += (basePrices[c.coinType] ?? 0) * c.remainingCount;
    }
    final days1405 = DateTime.now().difference(startOf1405).inDays;
    final bankInterestCost = base1405Cost * settings.bankInterestRate * days1405 / 36500;
    final profitFrom1405 = totalAssets - base1405Cost - bankInterestCost;

    double realized1404 = 0;
    for (var g in dataProvider.goldBox.values) {
      if (g.purchaseDate.isAfter(endOf1404)) continue;
      final endPrice = basePrices[g.type] ?? 0;
      realized1404 += (endPrice - g.purchasePricePerUnit) * g.quantity;
    }
    for (var c in dataProvider.coinBox.values) {
      if (c.purchaseDate.isAfter(endOf1404)) continue;
      final endPrice = basePrices[c.coinType] ?? 0;
      realized1404 += (endPrice - c.purchasePricePerUnit) * c.count;
    }

    return Scaffold(
      appBar: AppBar(title: Text('خلاصه دارایی'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: priceProvider.fetchPrices,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('آخرین به‌روزرسانی: ${priceProvider.lastUpdated.year > 2000 ? formatJalaliDate(priceProvider.lastUpdated) + ' ' + DateFormat('HH:mm').format(priceProvider.lastUpdated) : '---'}',
                        style: Theme.of(context).textTheme.bodySmall),
                    SizedBox(height: 16),
                    _summaryRow('ارزش کل دارایی', formatRial(totalAssets), Colors.green),
                    _summaryRow('سود محقق‌نشده', formatRial(unrealizedProfit), unrealizedProfit >= 0 ? Colors.green : Colors.red),
                    _summaryRow('سود محقق‌شده (فروش‌ها)', formatRial(realizedProfit), realizedProfit >= 0 ? Colors.green : Colors.red),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('عملکرد از ابتدای ۱۴۰۵ (با کسر هزینه فرصت بانکی)', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    AutoSizeText(formatRial(profitFrom1405),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: profitFrom1405 >= 0 ? Colors.green : Colors.red),
                        maxLines: 1),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('سود محقق شده پایان ۱۴۰۴ (بر اساس قیمت‌های ۱/۱/۱۴۰۵)', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    AutoSizeText(formatRial(realized1404),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: realized1404 >= 0 ? Colors.green : Colors.red),
                        maxLines: 1),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('قیمت‌های لحظه‌ای (ریال)', style: Theme.of(context).textTheme.titleMedium),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              children: priceProvider.prices.entries.map((e) {
                final price = e.value.currentPrice ?? 0;
                return Card(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AutoSizeText(goldTypeName(e.key), style: TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                          AutoSizeText(formatRial(price), maxLines: 1),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          AutoSizeText(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16), maxLines: 1),
        ],
      ),
    );
  }
}

class GoldListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);

    final activeGold = dataProvider.activeGold;
    double totalWeight = activeGold.fold(0, (sum, g) => sum + g.remainingQuantity);
    double totalPaid = activeGold.fold(0, (sum, g) => sum + g.purchasePricePerUnit * g.remainingQuantity);

    return Scaffold(
      appBar: AppBar(
        title: Text('طلای آب شده'),
        centerTitle: true,
        actions: [IconButton(icon: Icon(Icons.add), onPressed: () => _showAddEditGoldDialog(context, null))],
      ),
      body: Column(
        children: [
          Card(
            margin: EdgeInsets.all(8),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: _statColumn('وزن کل', '${totalWeight.toStringAsFixed(3)} گرم')),
                  Expanded(child: _statColumn('مبلغ پرداختی', formatRial(totalPaid))),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: activeGold.length,
              itemBuilder: (ctx, index) {
                final g = activeGold[index];
                final currentPrice = priceProvider.prices[g.type]?.currentPrice ?? 0;
                final paid = g.purchasePricePerUnit * g.remainingQuantity;
                final currentValue = currentPrice * g.remainingQuantity;
                final profit = currentValue - paid;

                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: AutoSizeText('${g.remainingQuantity.toStringAsFixed(3)} گرم (اصلی: ${g.quantity.toStringAsFixed(3)})'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText('فی خرید: ${formatRial(g.purchasePricePerUnit)}', maxLines: 1),
                          AutoSizeText('ارزش فعلی: ${formatRial(currentValue)}', maxLines: 1),
                          AutoSizeText('سود خالص: ${formatRial(profit)}',
                              style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                          if (g.description.isNotEmpty) AutoSizeText(g.description, style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.attach_money, color: Colors.red),
                            tooltip: 'فروش',
                            onPressed: () => _showSellGoldDialog(context, g),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, size: 20),
                            onPressed: () => _showAddEditGoldDialog(context, g),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('تأیید حذف'),
                                  content: Text('آیا از حذف این آیتم اطمینان دارید؟'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                                    TextButton(onPressed: () { dataProvider.deleteGold(g); Navigator.pop(ctx); }, child: Text('حذف', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
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

  Widget _statColumn(String label, String value) {
    return Column(children: [Text(label), SizedBox(height: 4), AutoSizeText(value, style: TextStyle(fontWeight: FontWeight.bold))]);
  }

  void _showAddEditGoldDialog(BuildContext context, GoldTransaction? existing) {
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = existing?.purchaseDate ?? DateTime.now();
    double price = existing?.purchasePricePerUnit ?? 0;
    double weight = existing?.quantity ?? 0;
    String desc = existing?.description ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'افزودن طلای آب شده' : 'ویرایش'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextFormField(
                    initialValue: price.toString(),
                    decoration: InputDecoration(labelText: 'فی خرید (ریال)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                    onSaved: (v) => price = double.parse(v!),
                  ),
                  TextFormField(
                    initialValue: weight.toString(),
                    decoration: InputDecoration(labelText: 'وزن (گرم)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                    onSaved: (v) => weight = double.parse(v!),
                  ),
                  ListTile(
                    title: Text('تاریخ خرید: ${formatJalaliDate(selectedDate)}'),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await PersianDatePicker.showDialog(
                        context: context,
                        initialDate: Jalali.fromDateTime(selectedDate),
                      );
                      if (picked != null) selectedDate = picked.toDateTime();
                    },
                  ),
                  TextFormField(
                    initialValue: desc,
                    decoration: InputDecoration(labelText: 'توضیحات'),
                    onSaved: (v) => desc = v ?? '',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  if (existing == null) {
                    final t = GoldTransaction(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      type: 'gold_18',
                      purchaseDate: selectedDate,
                      purchasePricePerUnit: price,
                      quantity: weight,
                      description: desc,
                    );
                    Provider.of<DataProvider>(context, listen: false).addGold(t);
                  } else {
                    existing.purchaseDate = selectedDate;
                    existing.purchasePricePerUnit = price;
                    existing.quantity = weight;
                    existing.remainingQuantity = weight;
                    existing.description = desc;
                    Provider.of<DataProvider>(context, listen: false).updateGold(existing);
                  }
                  Navigator.pop(ctx);
                }
              },
              child: Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }

  void _showSellGoldDialog(BuildContext context, GoldTransaction lot) {
    final priceController = TextEditingController(text: (Provider.of<PriceProvider>(context, listen: false).prices[lot.type]?.currentPrice ?? 0).toStringAsFixed(0));
    final qtyController = TextEditingController(text: lot.remainingQuantity.toStringAsFixed(3));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فروش طلا'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('موجودی: ${lot.remainingQuantity.toStringAsFixed(3)} گرم'),
            TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'مقدار فروش (گرم)')),
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'قیمت فروش هر گرم (ریال)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
          ElevatedButton(
            onPressed: () {
              final qty = double.tryParse(qtyController.text) ?? 0;
              final price = double.tryParse(priceController.text) ?? 0;
              if (qty > 0 && qty <= lot.remainingQuantity) {
                Provider.of<DataProvider>(context, listen: false).sellGold(lot, qty, price);
                Navigator.pop(ctx);
              }
            },
            child: Text('فروش'),
          ),
        ],
      ),
    );
  }
}

class CoinListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);

    final activeCoins = dataProvider.activeCoins;
    int totalCoins = activeCoins.fold(0, (sum, c) => sum + c.remainingCount);
    int rub = activeCoins.where((c) => c.coinType == 'coin_quarter').fold(0, (s, c) => s + c.remainingCount);
    int nim = activeCoins.where((c) => c.coinType == 'coin_half').fold(0, (s, c) => s + c.remainingCount);
    int tamam = activeCoins.where((c) => c.coinType == 'coin_new' || c.coinType == 'coin_old').fold(0, (s, c) => s + c.remainingCount);
    double totalPaid = activeCoins.fold(0, (sum, c) => sum + c.purchasePricePerUnit * c.remainingCount);

    return Scaffold(
      appBar: AppBar(
        title: Text('سکه‌ها'),
        centerTitle: true,
        actions: [IconButton(icon: Icon(Icons.add), onPressed: () => _showAddEditCoinDialog(context, null))],
      ),
      body: Column(
        children: [
          Card(
            margin: EdgeInsets.all(8),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _statColumn('ربع', '$rub'), _statColumn('نیم', '$nim'), _statColumn('تمام', '$tamam'),
                  ]),
                  Divider(),
                  Text('تعداد کل: $totalCoins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              title: Text('مجموع مبلغ پرداختی'),
              trailing: AutoSizeText(formatRial(totalPaid), style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: activeCoins.length,
              itemBuilder: (ctx, index) {
                final c = activeCoins[index];
                final currentPrice = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
                final paid = c.purchasePricePerUnit * c.remainingCount;
                final currentValue = currentPrice * c.remainingCount;
                final profit = currentValue - paid;

                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: AutoSizeText('${c.remainingCount} ${coinName(c.coinType)} (اصلی: ${c.count})'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText('فی خرید: ${formatRial(c.purchasePricePerUnit)}'),
                          AutoSizeText('ارزش فعلی: ${formatRial(currentValue)}'),
                          AutoSizeText('سود خالص: ${formatRial(profit)}',
                              style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                          if (c.description.isNotEmpty) AutoSizeText(c.description, style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.attach_money, color: Colors.red),
                            tooltip: 'فروش',
                            onPressed: () => _showSellCoinDialog(context, c),
                          ),
                          IconButton(icon: Icon(Icons.edit, size: 20), onPressed: () => _showAddEditCoinDialog(context, c)),
                          IconButton(
                            icon: Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('تأیید حذف'),
                                  content: Text('آیا از حذف این آیتم اطمینان دارید؟'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                                    TextButton(onPressed: () { dataProvider.deleteCoin(c); Navigator.pop(ctx); }, child: Text('حذف', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
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

  Widget _statColumn(String label, String value) => Column(children: [Text(label), SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]);

  void _showAddEditCoinDialog(BuildContext context, CoinTransaction? existing) {
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = existing?.purchaseDate ?? DateTime.now();
    double price = existing?.purchasePricePerUnit ?? 0;
    int count = existing?.count ?? 1;
    String desc = existing?.description ?? '';
    String coinType = existing?.coinType ?? 'coin_new';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'افزودن سکه' : 'ویرایش'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: coinType,
                  items: [
                    DropdownMenuItem(value: 'coin_new', child: Text('تمام (امامی)')),
                    DropdownMenuItem(value: 'coin_old', child: Text('تمام (قدیم)')),
                    DropdownMenuItem(value: 'coin_half', child: Text('نیم سکه')),
                    DropdownMenuItem(value: 'coin_quarter', child: Text('ربع سکه')),
                    DropdownMenuItem(value: 'coin_1g', child: Text('سکه یک گرمی')),
                  ],
                  onChanged: (v) => coinType = v!,
                  decoration: InputDecoration(labelText: 'نوع سکه'),
                ),
                TextFormField(initialValue: price.toString(), decoration: InputDecoration(labelText: 'فی خرید (ریال)'), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'وارد کنید' : null, onSaved: (v) => price = double.parse(v!)),
                TextFormField(initialValue: count.toString(), decoration: InputDecoration(labelText: 'تعداد'), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'وارد کنید' : null, onSaved: (v) => count = int.parse(v!)),
                ListTile(
                  title: Text('تاریخ خرید: ${formatJalaliDate(selectedDate)}'),
                  trailing: Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await PersianDatePicker.showDialog(
                      context: context,
                      initialDate: Jalali.fromDateTime(selectedDate),
                    );
                    if (picked != null) selectedDate = picked.toDateTime();
                  },
                ),
                TextFormField(initialValue: desc, decoration: InputDecoration(labelText: 'توضیحات'), onSaved: (v) => desc = v ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                if (existing == null) {
                  final t = CoinTransaction(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    coinType: coinType,
                    purchaseDate: selectedDate,
                    purchasePricePerUnit: price,
                    count: count,
                    description: desc,
                  );
                  Provider.of<DataProvider>(context, listen: false).addCoin(t);
                } else {
                  existing.coinType = coinType;
                  existing.purchaseDate = selectedDate;
                  existing.purchasePricePerUnit = price;
                  existing.count = count;
                  existing.remainingCount = count;
                  existing.description = desc;
                  Provider.of<DataProvider>(context, listen: false).updateCoin(existing);
                }
                Navigator.pop(ctx);
              }
            },
            child: Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  void _showSellCoinDialog(BuildContext context, CoinTransaction lot) {
    final priceController = TextEditingController(text: (Provider.of<PriceProvider>(context, listen: false).prices[lot.coinType]?.currentPrice ?? 0).toStringAsFixed(0));
    final countController = TextEditingController(text: lot.remainingCount.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فروش سکه'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('موجودی: ${lot.remainingCount} عدد'),
            TextField(controller: countController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'تعداد فروش')),
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'قیمت فروش هر عدد (ریال)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
          ElevatedButton(
            onPressed: () {
              final cnt = int.tryParse(countController.text) ?? 0;
              final price = double.tryParse(priceController.text) ?? 0;
              if (cnt > 0 && cnt <= lot.remainingCount) {
                Provider.of<DataProvider>(context, listen: false).sellCoin(lot, cnt, price);
                Navigator.pop(ctx);
              }
            },
            child: Text('فروش'),
          ),
        ],
      ),
    );
  }
}

class ChartsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);

    final activeGold = dataProvider.activeGold;
    final activeCoins = dataProvider.activeCoins;

    double goldValue = activeGold.fold(0, (s, g) => s + (priceProvider.prices[g.type]?.currentPrice ?? 0) * g.remainingQuantity);
    Map<String, double> coinTypeValues = {};
    for (var c in activeCoins) {
      final v = (priceProvider.prices[c.coinType]?.currentPrice ?? 0) * c.remainingCount;
      coinTypeValues.update(c.coinType, (old) => old + v, ifAbsent: () => v);
    }
    final total = goldValue + coinTypeValues.values.fold(0.0, (a, b) => a + b);
    List<PieChartSectionData> sections = [];
    if (goldValue > 0) sections.add(PieChartSectionData(value: goldValue, title: '${(goldValue/total*100).toStringAsFixed(1)}%', color: Colors.blue, radius: 50, titleStyle: TextStyle(fontSize: 10, color: Colors.white)));
    for (var e in coinTypeValues.entries) {
      sections.add(PieChartSectionData(value: e.value, title: '${coinName(e.key)}\n${(e.value/total*100).toStringAsFixed(1)}%', color: _coinColor(e.key), radius: 50, titleStyle: TextStyle(fontSize: 9, color: Colors.white)));
    }

    List<BarChartGroupData> bars = [];
    int x = 0;
    for (var g in activeGold) {
      final cp = priceProvider.prices[g.type]?.currentPrice ?? 0;
      final profit = (cp - g.purchasePricePerUnit) * g.remainingQuantity;
      bars.add(BarChartGroupData(x: x++, barRods: [BarChartRodData(toY: profit, color: profit>=0?Colors.green:Colors.red, width: 10)]));
    }
    for (var c in activeCoins) {
      final cp = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
      final profit = (cp - c.purchasePricePerUnit) * c.remainingCount;
      bars.add(BarChartGroupData(x: x++, barRods: [BarChartRodData(toY: profit, color: profit>=0?Colors.green:Colors.red, width: 10)]));
    }

    final allLots = <_Lot>[];
    for (var g in activeGold) allLots.add(_Lot(g.purchaseDate, g.purchasePricePerUnit * g.quantity));
    for (var c in activeCoins) allLots.add(_Lot(c.purchaseDate, c.purchasePricePerUnit * c.count.toDouble()));
    allLots.sort((a, b) => a.date.compareTo(b.date));
    List<FlSpot> spots = [];
    double cumulative = 0;
    for (var lot in allLots) {
      cumulative += lot.cost;
      spots.add(FlSpot(lot.date.millisecondsSinceEpoch.toDouble(), cumulative));
    }
    spots.add(FlSpot(DateTime.now().millisecondsSinceEpoch.toDouble(), total));

    return Scaffold(
      appBar: AppBar(title: Text('نمودارها'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text('توزیع دارایی', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(height: 250, child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 40))),
          SizedBox(height: 20),
          Text('سود/زیان هر لات', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 300,
            child: BarChart(
              BarChartData(
                barGroups: bars,
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text('روند سرمایه‌گذاری (هزینه تجمعی)', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 200,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
                  ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                    return AutoSizeText(formatJalaliDate(dt).substring(5), style: TextStyle(fontSize: 10));
                  }, reservedSize: 28)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 60, getTitlesWidget: (value, meta) {
                    return AutoSizeText(formatRial(value), style: TextStyle(fontSize: 10));
                  })),
                ),
                borderData: FlBorderData(show: true),
                gridData: FlGridData(show: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _coinColor(String type) {
    switch (type) {
      case 'coin_quarter': return Colors.amber;
      case 'coin_half': return Colors.green;
      case 'coin_new':
      case 'coin_old': return Colors.purple;
      case 'coin_1g': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

class _Lot {
  final DateTime date;
  final double cost;
  _Lot(this.date, this.cost);
}

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final priceProvider = Provider.of<PriceProvider>(context);
    final basePriceProvider = Provider.of<BasePriceProvider>(context);
    final basePrices = basePriceProvider.basePrices;

    return Scaffold(
      appBar: AppBar(title: Text('تنظیمات'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('نرخ سود بانکی'),
                  Slider(value: settings.bankInterestRate, min: 0, max: 50, divisions: 100, label: '${settings.bankInterestRate.toStringAsFixed(1)}%', onChanged: (v) => settings.setBankInterestRate(v)),
                  Text('${settings.bankInterestRate.toStringAsFixed(1)}%'),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('فاصله به‌روزرسانی خودکار (ثانیه)'),
                  Slider(value: settings.autoUpdateInterval.toDouble(), min: 30, max: 600, divisions: (600-30)~/10, label: '${settings.autoUpdateInterval}', onChanged: (v) { settings.setAutoUpdateInterval(v.toInt()); priceProvider.setAutoUpdateInterval(v.toInt()); }),
                  Text('${settings.autoUpdateInterval} ثانیه'),
                ],
              ),
            ),
          ),
          Card(child: ListTile(title: Text('به‌روزرسانی دستی قیمت‌ها'), trailing: Icon(Icons.refresh), onTap: priceProvider.fetchPrices)),
          SizedBox(height: 20),
          Text('قیمت‌های پایه (۱/۱/۱۴۰۵) - به ریال', style: Theme.of(context).textTheme.titleMedium),
          ...basePrices.keys.map((key) => Card(
                child: ListTile(
                  title: Text(goldTypeName(key)),
                  trailing: SizedBox(
                    width: 120,
                    child: TextFormField(
                      initialValue: basePrices[key] == 0 ? '' : basePrices[key].toString(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(hintText: 'ریال', isDense: true),
                      onFieldSubmitted: (value) {
                        final v = double.tryParse(value) ?? 0;
                        basePriceProvider.setBasePrice(key, v);
                      },
                    ),
                  ),
                ),
              )),
          Card(child: ListTile(title: Text('نسخه ۲.۰.۰'), subtitle: Text('ساخته شده توسط امیر - بنیانگذار نخودگرام'))),
        ],
      ),
    );
  }
}

// -------------------- Main --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fa', null);

  final appDocDir = await path_provider.getApplicationDocumentsDirectory();
  Hive.init(appDocDir.path);
  Hive.registerAdapter(GoldTransactionAdapter());
  Hive.registerAdapter(CoinTransactionAdapter());
  Hive.registerAdapter(SaleTransactionAdapter());

  final goldBox = await Hive.openBox<GoldTransaction>('goldTransactions');
  final coinBox = await Hive.openBox<CoinTransaction>('coinTransactions');
  final saleBox = await Hive.openBox<SaleTransaction>('saleTransactions');
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PriceProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => BasePriceProvider(prefs)),
        ChangeNotifierProvider(create: (_) => DataProvider(goldBox: goldBox, coinBox: coinBox, saleBox: saleBox)),
      ],
      child: MaterialApp(
        title: 'مدیریت دارایی طلا و سکه',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
          fontFamily: 'Vazir',
        ),
        home: MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [HomeScreen(), GoldListScreen(), CoinListScreen(), ChartsScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.monetization_on), label: 'طلای آب شده'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'سکه'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'نمودارها'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'تنظیمات'),
        ],
      ),
    );
  }
}