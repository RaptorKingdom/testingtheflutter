import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:intl/date_symbol_data_local.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:html/parser.dart' as html_parser;
import 'package:shamsi_date/shamsi_date.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:persian_datetimepickers/persian_datetimepickers.dart';
import 'package:persian_number_utility/persian_number_utility.dart';
import 'package:crystal_navigation_bar/crystal_navigation_bar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

part 'main.g.dart';

// -------------------- Helpers --------------------
String formatRial(double amount) {
  final formatted = NumberFormat('#,###').format(amount);
  return formatted.toPersianDigit();
}

String formatDoubleWithoutTrailingZeros(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  } else {
    String str = value.toString();
    if (str.contains('.')) {
      str = str.replaceAll(RegExp(r'0*$'), '');
      if (str.endsWith('.')) str = str.substring(0, str.length - 1);
    }
    return str;
  }
}

/// فرمت عدد با جداکننده هزارگان به صورت انگلیسی (برای ورودی)
String formatWithSeparator(double value) {
  if (value == 0) return '';
  return NumberFormat('#,###').format(value);
}

String formatJalaliDate(DateTime dt) {
  final j = Jalali.fromDateTime(dt);
  return '${j.year}/${j.month.toString().padLeft(2,'0')}/${j.day.toString().padLeft(2,'0')}';
}

String coinName(String t) {
  switch(t) {
    case 'coin_new': return 'سکه تمام (امامی)';
    case 'coin_old': return 'سکه تمام (قدیم)';
    case 'coin_half': return 'نیم سکه';
    case 'coin_quarter': return 'ربع سکه';
    case 'coin_1g': return 'سکه یک گرمی';
    default: return t;
  }
}

String goldTypeName(String k) {
  switch(k) {
    case 'gold_18': return 'طلای ۱۸ عیار';
    case 'gold_24': return 'طلای ۲۴ عیار';
    case 'gold_ons': return 'انس طلا';
    case 'gold_mazneh': return 'مظنه تهران';
    case 'coin_old': return 'سکه قدیم';
    case 'coin_new': return 'سکه جدید';
    case 'coin_half': return 'نیم سکه';
    case 'coin_quarter': return 'ربع سکه';
    case 'coin_1g': return 'سکه یک گرمی';
    default: return k;
  }
}

/// تبدیل عدد به تومان (برای نمایش زیر ورودی)
String formatToman(double amount) {
  final toman = amount / 10;
  final formatted = NumberFormat('#,###').format(toman);
  return '${formatted.toPersianDigit()} تومان';
}

/// تبدیل عدد به حروف تومان
String numberToTomanWords(double amount) {
  final toman = amount / 10;
  final intValue = toman.round();
  final words = intValue.toString().toWord();
  return words.toPersianDigit() + ' تومان';
}

/// ویجت ورودی عدد با جداکننده هزارگان، چپ‌چین و نمایش تومان برای قیمت‌ها
class NumberInputWithToman extends StatefulWidget {
  final String label;
  final String? initialValue;
  final ValueChanged<String> onSaved;
  final TextInputType keyboardType;
  final FormFieldValidator<String>? validator;
  final bool isPrice;

  const NumberInputWithToman({
    Key? key,
    required this.label,
    this.initialValue,
    required this.onSaved,
    this.keyboardType = TextInputType.number,
    this.validator,
    this.isPrice = true,
  }) : super(key: key);

  @override
  _NumberInputWithTomanState createState() => _NumberInputWithTomanState();
}

class _NumberInputWithTomanState extends State<NumberInputWithToman> {
  late TextEditingController _controller;
  String _tomanText = '';
  String _wordsText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _updateDisplay(_controller.text);
    _controller.addListener(() {
      _updateDisplay(_controller.text);
    });
  }

  void _updateDisplay(String value) {
    final clean = value.replaceAll(RegExp(r'[^\d]'), '');
    if (clean.isNotEmpty && widget.isPrice) {
      final num = double.tryParse(clean) ?? 0;
      setState(() {
        _tomanText = formatToman(num);
        _wordsText = numberToTomanWords(num);
      });
    } else {
      setState(() {
        _tomanText = '';
        _wordsText = '';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: TextStyle(fontFamily: 'Vazir'),
          ),
          keyboardType: widget.keyboardType,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
            ThousandsSeparatorInputFormatter(),
          ],
          validator: widget.validator,
          onSaved: (v) {
            final cleaned = v?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
            widget.onSaved(cleaned);
          },
        ),
        if (_tomanText.isNotEmpty && widget.isPrice)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tomanText,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  textDirection: TextDirection.rtl,
                ),
                Text(
                  _wordsText,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// فرمتر برای جدا کردن هزارگان هنگام تایپ
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final clean = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (clean.isEmpty) return newValue;
    final intValue = int.tryParse(clean);
    if (intValue == null) return newValue;
    final formatted = NumberFormat('#,###').format(intValue);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

Future<DateTime?> pickJalaliDate(BuildContext context, DateTime initial) async {
  final picked = await showPersianDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1370, 1, 1),
    lastDate: DateTime.now(),
  );
  return picked;
}

// -------------------- Models --------------------
@HiveType(typeId: 0)
class GoldTransaction extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String type;
  @HiveField(2) DateTime purchaseDate;
  @HiveField(3) double purchasePricePerUnit;
  @HiveField(4) double quantity;
  @HiveField(5) String description;
  @HiveField(6) double remainingQuantity;

  GoldTransaction({
    required this.id, required this.type, required this.purchaseDate,
    required this.purchasePricePerUnit, required this.quantity,
    required this.description, double? remainingQuantity,
  }) : remainingQuantity = remainingQuantity ?? quantity;
}

@HiveType(typeId: 1)
class CoinTransaction extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String coinType;
  @HiveField(2) DateTime purchaseDate;
  @HiveField(3) double purchasePricePerUnit;
  @HiveField(4) int count;
  @HiveField(5) String description;
  @HiveField(6) int remainingCount;

  CoinTransaction({
    required this.id, required this.coinType, required this.purchaseDate,
    required this.purchasePricePerUnit, required this.count,
    required this.description, int? remainingCount,
  }) : remainingCount = remainingCount ?? count;
}

@HiveType(typeId: 2)
class SaleTransaction extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String lotId;
  @HiveField(2) DateTime saleDate;
  @HiveField(3) double salePricePerUnit;
  @HiveField(4) double quantity;
  @HiveField(5) bool isGold;
  @HiveField(6) String? coinType;

  SaleTransaction({
    required this.id, required this.lotId, required this.saleDate,
    required this.salePricePerUnit, required this.quantity,
    required this.isGold, this.coinType,
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

  PriceResponse({required this.name, this.currentPrice, this.high, this.low, this.yesterdayAvg, this.change});

  factory PriceResponse.fromJson(Map<String, dynamic> json) => PriceResponse(
    name: json['name'] ?? '',
    currentPrice: json['current_price'] != null ? (json['current_price'] as num).toDouble() : null,
    high: json['high'] != null ? (json['high'] as num).toDouble() : null,
    low: json['low'] != null ? (json['low'] as num).toDouble() : null,
    yesterdayAvg: json['yesterday_avg'] != null ? (json['yesterday_avg'] as num).toDouble() : null,
    change: json['change'] != null ? Change.fromJson(json['change']) : null,
  );
}

class Change {
  final double? value;
  final double? percent;
  final String? direction;
  Change({this.value, this.percent, this.direction});
  factory Change.fromJson(Map<String, dynamic> json) => Change(
    value: json['value'] != null ? (json['value'] as num).toDouble() : null,
    percent: json['percent'] != null ? (json['percent'] as num).toDouble() : null,
    direction: json['direction'],
  );
}

// -------------------- API Service --------------------
class ApiService {
  static const String _pageUrl = 'https://www.estjt.ir/price/';
  static const Map<String, String> _nameToKey = {
    'انس طلا': 'gold_ons', 'مظنه تهران': 'gold_mazneh',
    'طلای ۱۸ عیار': 'gold_18', 'طلای ۲۴ عیار': 'gold_24',
    'سکه طرح قدیم': 'coin_old', 'سکه طرح جدید': 'coin_new',
    'نیم سکه': 'coin_half', 'ربع سکه': 'coin_quarter', 'سکه یک گرمی': 'coin_1g',
  };

  static String _persianToEnglish(String s) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const english = '0123456789';
    final buf = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = persian.indexOf(c);
      buf.write(i != -1 ? english[i] : c);
    }
    return buf.toString();
  }

  static double? _parsePrice(String text) {
    if (text.trim() == '—') return null;
    final cleaned = _persianToEnglish(text).replaceAll(RegExp(r'[^\d.]'), '');
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  static Map<String, double?>? _parseChange(String text) {
    final t = _persianToEnglish(text);
    final m = RegExp(r'([\d.]+)\s*\(([\d.]+)\)').firstMatch(t);
    if (m != null) return {'value': double.tryParse(m.group(1)!), 'percent': double.tryParse(m.group(2)!)};
    return null;
  }

  static Future<Map<String, PriceResponse>> fetchAllPrices() async {
    try {
      final res = await http.get(Uri.parse(_pageUrl), headers: {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'text/html',
        'Accept-Language': 'en-US,en;q=0.5',
      });
      if (res.statusCode != 200) return {};
      final doc = html_parser.parse(res.body);
      final rows = doc.querySelectorAll('div.price-box table tbody tr');
      final Map<String, PriceResponse> prices = {};
      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 6) continue;
        final name = cells[0].text.trim();
        final key = _nameToKey[name];
        if (key == null) continue;
        var cur = _parsePrice(cells[1].text.trim());
        var high = _parsePrice(cells[2].text.trim());
        var low = _parsePrice(cells[3].text.trim());
        var yday = _parsePrice(cells[4].text.trim());
        String? dir; double? cVal; double? cPct;
        final span = cells[5].querySelector('span');
        if (span != null) {
          if (span.classes.contains('asc')) dir = 'up';
          else if (span.classes.contains('desc')) dir = 'down';
          final cd = _parseChange(span.text.trim());
          if (cd != null) { cVal = cd['value']; cPct = cd['percent']; }
        }

        // تبدیل قیمت‌ها به ریال (به جز انس طلا که دلار است)
        const rialsMultiplier = 10.0;
        if (key != 'gold_ons') {
          cur = cur != null ? cur * rialsMultiplier : null;
          high = high != null ? high * rialsMultiplier : null;
          low = low != null ? low * rialsMultiplier : null;
          yday = yday != null ? yday * rialsMultiplier : null;
          if (cVal != null) cVal = cVal * rialsMultiplier;
        }

        prices[key] = PriceResponse(
          name: name,
          currentPrice: cur,
          high: high,
          low: low,
          yesterdayAvg: yday,
          change: Change(value: cVal, percent: cPct, direction: dir),
        );
      }
      return prices;
    } catch (_) { return {}; }
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
    'gold_18','gold_24','gold_ons','gold_mazneh',
    'coin_old','coin_new','coin_half','coin_quarter','coin_1g'
  ];
  Map<String, PriceResponse> get prices => UnmodifiableMapView(_prices);
  DateTime get lastUpdated => _lastUpdated;

  PriceProvider(this._prefs) {
    _loadSavedPrices(); fetchPrices(); startAutoUpdate();
  }

  void _loadSavedPrices() {
    _lastSavedPrices = {};
    for (var key in _priceKeys) {
      String? jsonStr = _prefs.getString('price_$key');
      if (jsonStr != null) {
        try {
          final json = jsonDecode(jsonStr);
          _lastSavedPrices[key] = PriceResponse.fromJson(json);
        } catch (_) {}
      }
    }
    if (_lastSavedPrices.isNotEmpty) {
      _prices = Map.from(_lastSavedPrices);
      int? t = _prefs.getInt('last_update');
      if (t != null) _lastUpdated = DateTime.fromMillisecondsSinceEpoch(t);
    }
  }

  Future<void> _savePrices(Map<String, PriceResponse> prices) async {
    for (var e in prices.entries) {
      final jsonStr = jsonEncode({
        'name': e.value.name,
        'current_price': e.value.currentPrice,
        'high': e.value.high,
        'low': e.value.low,
        'yesterday_avg': e.value.yesterdayAvg,
        'change': e.value.change != null ? {
          'value': e.value.change!.value,
          'percent': e.value.change!.percent,
          'direction': e.value.change!.direction,
        } : null,
      });
      await _prefs.setString('price_${e.key}', jsonStr);
    }
    await _prefs.setInt('last_update', DateTime.now().millisecondsSinceEpoch);
  }

  void startAutoUpdate({int intervalSeconds = 300}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => fetchPrices());
  }
  void setAutoUpdateInterval(int s) { startAutoUpdate(intervalSeconds: s); }

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

  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

class SettingsProvider extends ChangeNotifier {
  double _bankInterestRate = 26.0;
  int _autoUpdateInterval = 300;
  Color _secondaryColor = Colors.amber;
  double get bankInterestRate => _bankInterestRate;
  int get autoUpdateInterval => _autoUpdateInterval;
  Color get secondaryColor => _secondaryColor;
  final SharedPreferences _prefs;
  SettingsProvider(this._prefs) { _loadSettings(); }
  void _loadSettings() {
    _bankInterestRate = _prefs.getDouble('bankInterestRate') ?? 26.0;
    _autoUpdateInterval = _prefs.getInt('autoUpdateInterval') ?? 300;
    final colorStr = _prefs.getString('secondaryColor');
    if (colorStr != null) {
      try {
        _secondaryColor = Color(int.parse(colorStr));
      } catch (_) {}
    }
  }
  Future<void> setBankInterestRate(double v) async { _bankInterestRate = v; await _prefs.setDouble('bankInterestRate', v); notifyListeners(); }
  Future<void> setAutoUpdateInterval(int s) async { _autoUpdateInterval = s; await _prefs.setInt('autoUpdateInterval', s); notifyListeners(); }
  Future<void> setSecondaryColor(Color c) async {
    _secondaryColor = c;
    await _prefs.setString('secondaryColor', c.value.toString());
    notifyListeners();
  }
}

/// BasePriceProvider با قیمت‌های ثابت ۱۴۰۵/۱/۱
class BasePriceProvider extends ChangeNotifier {
  Map<String, double> _basePrices = {};
  BasePriceProvider() {
    _basePrices = {
      'gold_18': 183065000,
      'gold_24': 244060000,
      'gold_ons': 46850000, // دلار
      'gold_mazneh': 793000000,
      'coin_old': 1815000000,
      'coin_new': 1855000000,
      'coin_half': 985000000,
      'coin_quarter': 560000000,
      'coin_1g': 280000000,
    };
  }
  Map<String, double> get basePrices => UnmodifiableMapView(_basePrices);
}

class DataProvider extends ChangeNotifier {
  final Box<GoldTransaction> goldBox;
  final Box<CoinTransaction> coinBox;
  final Box<SaleTransaction> saleBox;

  DataProvider({required this.goldBox, required this.coinBox, required this.saleBox}) {
    if (goldBox.isEmpty && coinBox.isEmpty) _addDefaultData();
  }

  void _addDefaultData() {
    goldBox.addAll([
      GoldTransaction(id:'1',type:'gold_18',purchaseDate:DateTime(2025,1,2),purchasePricePerUnit:52518583,quantity:100,description:''),
      GoldTransaction(id:'2',type:'gold_18',purchaseDate:DateTime(2025,2,9),purchasePricePerUnit:65792511,quantity:61.195,description:''),
      GoldTransaction(id:'3',type:'gold_18',purchaseDate:DateTime(2025,4,13),purchasePricePerUnit:76180802,quantity:50,description:''),
      GoldTransaction(id:'4',type:'gold_18',purchaseDate:DateTime(2025,10,6),purchasePricePerUnit:105960571,quantity:100,description:''),
      GoldTransaction(id:'5',type:'gold_18',purchaseDate:DateTime(2025,11,10),purchasePricePerUnit:105730000,quantity:60,description:''),
      GoldTransaction(id:'6',type:'gold_18',purchaseDate:DateTime(2025,12,14),purchasePricePerUnit:138048000,quantity:15,description:''),
    ]);
    coinBox.addAll([
      CoinTransaction(id:'c1',coinType:'coin_quarter',purchaseDate:DateTime(2023,1,17),purchasePricePerUnit:70500000,count:3,description:'خرید از بورس کالای کارگزاری آگاه'),
      CoinTransaction(id:'c2',coinType:'coin_new',purchaseDate:DateTime(2025,1,1),purchasePricePerUnit:560000000,count:2,description:'خرید از زهرا'),
      CoinTransaction(id:'c3',coinType:'coin_quarter',purchaseDate:DateTime(2025,1,1),purchasePricePerUnit:174000000,count:1,description:'خرید از زهرا'),
      CoinTransaction(id:'c4',coinType:'coin_new',purchaseDate:DateTime(2025,9,8),purchasePricePerUnit:832224932,count:6,description:'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id:'c5',coinType:'coin_half',purchaseDate:DateTime(2025,9,8),purchasePricePerUnit:441195425,count:10,description:'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id:'c6',coinType:'coin_quarter',purchaseDate:DateTime(2025,9,8),purchasePricePerUnit:257758617,count:14,description:'خرید از مرکز مبادلات سکه و ارز'),
      CoinTransaction(id:'c7',coinType:'coin_half',purchaseDate:DateTime(2025,11,12),purchasePricePerUnit:575585000,count:1,description:'خرید از مرکز مبادلات کاربری مریم'),
      CoinTransaction(id:'c8',coinType:'coin_quarter',purchaseDate:DateTime(2025,11,12),purchasePricePerUnit:327850000,count:2,description:'خرید از مرکز مبادلات کابری مریم'),
      CoinTransaction(id:'c9',coinType:'coin_new',purchaseDate:DateTime(2026,2,15),purchasePricePerUnit:1930000000,count:4,description:'خرید از علی بابت پول ماشین'),
      CoinTransaction(id:'c10',coinType:'coin_quarter',purchaseDate:DateTime(2026,2,15),purchasePricePerUnit:525000000,count:6,description:'خرید از علی بابت پول ماشین'),
      CoinTransaction(id:'c11',coinType:'coin_half',purchaseDate:DateTime(2026,2,15),purchasePricePerUnit:970000000,count:3,description:'خرید از علی بابت پول ماشین'),
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
    await saleBox.add(SaleTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lotId: lot.id, saleDate: DateTime.now(),
      salePricePerUnit: pricePerUnit, quantity: quantity, isGold: true,
    ));
    if (lot.remainingQuantity <= 0.0001) await lot.delete();
    else await lot.save();
    notifyListeners();
  }

  Future<void> sellCoin(CoinTransaction lot, int count, double pricePerUnit) async {
    if (count <= 0 || count > lot.remainingCount) return;
    lot.remainingCount -= count;
    await saleBox.add(SaleTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      lotId: lot.id, saleDate: DateTime.now(),
      salePricePerUnit: pricePerUnit, quantity: count.toDouble(), isGold: false, coinType: lot.coinType,
    ));
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

  // Export: تمام داده‌ها را به صورت JSON برمی‌گرداند
  Future<Map<String, dynamic>> exportAllData() async {
    final goldData = goldBox.values.map((g) => {
      'id': g.id,
      'type': g.type,
      'purchaseDate': g.purchaseDate.toIso8601String(),
      'purchasePricePerUnit': g.purchasePricePerUnit,
      'quantity': g.quantity,
      'description': g.description,
      'remainingQuantity': g.remainingQuantity,
    }).toList();
    final coinData = coinBox.values.map((c) => {
      'id': c.id,
      'coinType': c.coinType,
      'purchaseDate': c.purchaseDate.toIso8601String(),
      'purchasePricePerUnit': c.purchasePricePerUnit,
      'count': c.count,
      'description': c.description,
      'remainingCount': c.remainingCount,
    }).toList();
    final saleData = saleBox.values.map((s) => {
      'id': s.id,
      'lotId': s.lotId,
      'saleDate': s.saleDate.toIso8601String(),
      'salePricePerUnit': s.salePricePerUnit,
      'quantity': s.quantity,
      'isGold': s.isGold,
      'coinType': s.coinType,
    }).toList();
    return {
      'goldTransactions': goldData,
      'coinTransactions': coinData,
      'saleTransactions': saleData,
      'exportDate': DateTime.now().toIso8601String(),
    };
  }

  // Import: پاک کردن داده‌های فعلی و جایگزینی با داده‌های جدید
  Future<void> importData(Map<String, dynamic> data) async {
    await goldBox.clear();
    await coinBox.clear();
    await saleBox.clear();

    final goldList = data['goldTransactions'] as List? ?? [];
    for (var item in goldList) {
      final g = GoldTransaction(
        id: item['id'],
        type: item['type'],
        purchaseDate: DateTime.parse(item['purchaseDate']),
        purchasePricePerUnit: (item['purchasePricePerUnit'] as num).toDouble(),
        quantity: (item['quantity'] as num).toDouble(),
        description: item['description'] ?? '',
        remainingQuantity: (item['remainingQuantity'] as num).toDouble(),
      );
      await goldBox.add(g);
    }

    final coinList = data['coinTransactions'] as List? ?? [];
    for (var item in coinList) {
      final c = CoinTransaction(
        id: item['id'],
        coinType: item['coinType'],
        purchaseDate: DateTime.parse(item['purchaseDate']),
        purchasePricePerUnit: (item['purchasePricePerUnit'] as num).toDouble(),
        count: item['count'],
        description: item['description'] ?? '',
        remainingCount: item['remainingCount'],
      );
      await coinBox.add(c);
    }

    final saleList = data['saleTransactions'] as List? ?? [];
    for (var item in saleList) {
      final s = SaleTransaction(
        id: item['id'],
        lotId: item['lotId'],
        saleDate: DateTime.parse(item['saleDate']),
        salePricePerUnit: (item['salePricePerUnit'] as num).toDouble(),
        quantity: (item['quantity'] as num).toDouble(),
        isGold: item['isGold'],
        coinType: item['coinType'],
      );
      await saleBox.add(s);
    }
    notifyListeners();
  }
}

// -------------------- ویجت AppBar بلوری --------------------
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const GlassAppBar({Key? key, required this.title, this.actions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AppBar(
          title: Text(title),
          centerTitle: true,
          backgroundColor: Colors.black.withOpacity(0.2),
          elevation: 0,
          actions: actions,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
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
    for (var g in dataProvider.activeGold) base1405Cost += (basePrices[g.type] ?? 0) * g.remainingQuantity;
    for (var c in dataProvider.activeCoins) base1405Cost += (basePrices[c.coinType] ?? 0) * c.remainingCount;
    final days1405 = DateTime.now().difference(startOf1405).inDays;
    final bankInterestCost = base1405Cost * settings.bankInterestRate * days1405 / 36500;
    final profitFrom1405 = totalAssets - base1405Cost - bankInterestCost;

    double realized1404 = 0;
    for (var g in dataProvider.goldBox.values) {
      if (g.purchaseDate.isAfter(endOf1404)) continue;
      realized1404 += ((basePrices[g.type] ?? 0) - g.purchasePricePerUnit) * g.quantity;
    }
    for (var c in dataProvider.coinBox.values) {
      if (c.purchaseDate.isAfter(endOf1404)) continue;
      realized1404 += ((basePrices[c.coinType] ?? 0) - c.purchasePricePerUnit) * c.count;
    }

    return Scaffold(
      appBar: GlassAppBar(title: 'خلاصه دارایی'),
      body: RefreshIndicator(
        onRefresh: priceProvider.fetchPrices,
        child: ListView(
          padding: EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
          children: [
            Card(
              child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
                Text('آخرین به‌روزرسانی: ${priceProvider.lastUpdated.year > 2000 ? formatJalaliDate(priceProvider.lastUpdated) + ' ' + DateFormat('HH:mm').format(priceProvider.lastUpdated) : '---'}',
                    style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: 16),
                _summaryRow('ارزش کل دارایی', formatRial(totalAssets), Colors.green),
                _summaryRow('سود محقق‌نشده', formatRial(unrealizedProfit), unrealizedProfit >= 0 ? Colors.green : Colors.red),
                _summaryRow('سود محقق‌شده (فروش‌ها)', formatRial(realizedProfit), realizedProfit >= 0 ? Colors.green : Colors.red),
              ])),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
                Text('عملکرد از ابتدای ۱۴۰۵ (با کسر هزینه فرصت بانکی)', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                AutoSizeText(formatRial(profitFrom1405), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: profitFrom1405 >= 0 ? Colors.green : Colors.red), maxLines: 1),
              ])),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
                Text('سود محقق شده پایان ۱۴۰۴', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                AutoSizeText(formatRial(realized1404), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: realized1404 >= 0 ? Colors.green : Colors.red), maxLines: 1),
              ])),
            ),
            SizedBox(height: 16),
            Text('قیمت‌های لحظه‌ای (ریال)', style: Theme.of(context).textTheme.titleMedium),
            GridView.count(
              shrinkWrap: true, physics: NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 2.5,
              children: priceProvider.prices.entries.map((e) {
                final price = e.value.currentPrice ?? 0;
                return Card(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Padding(padding: EdgeInsets.all(8), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AutoSizeText(goldTypeName(e.key), style: TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                      AutoSizeText(formatRial(price), maxLines: 1),
                    ])),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 80), // فضای اضافی برای جلوگیری از همپوشانی با منو
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      AutoSizeText(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16), maxLines: 1),
    ]),
  );
}

class GoldListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final activeGold = dataProvider.activeGold;
    double totalWeight = activeGold.fold(0, (s, g) => s + g.remainingQuantity);
    double totalPaid = activeGold.fold(0, (s, g) => s + g.purchasePricePerUnit * g.remainingQuantity);

    return Scaffold(
      appBar: GlassAppBar(
        title: 'طلای آب شده',
        actions: [IconButton(icon: Icon(Icons.add), onPressed: () => _showAddEditGoldDialog(context, null))],
      ),
      body: Column(children: [
        Card(
          margin: EdgeInsets.all(8),
          child: Padding(padding: EdgeInsets.all(12), child: Row(children: [
            Expanded(child: _statColumn('وزن کل', '${formatDoubleWithoutTrailingZeros(totalWeight)} گرم')),
            Expanded(child: _statColumn('مبلغ پرداختی', formatRial(totalPaid))),
          ])),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: 200),
            children: activeGold.map((g) {
              final cp = priceProvider.prices[g.type]?.currentPrice ?? 0;
              final paid = g.purchasePricePerUnit * g.remainingQuantity;
              final currentValue = cp * g.remainingQuantity;
              final profit = currentValue - paid;
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: AutoSizeText('${formatDoubleWithoutTrailingZeros(g.remainingQuantity)} گرم'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AutoSizeText('فی خرید: ${formatRial(g.purchasePricePerUnit)}', maxLines: 1),
                      AutoSizeText('ارزش فعلی: ${formatRial(currentValue)}', maxLines: 1),
                      AutoSizeText('سود خالص: ${formatRial(profit)}', style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                      if (g.description.isNotEmpty)
                        AutoSizeText(
                          g.description,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 2,
                          minFontSize: 10,
                        ),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: Icon(Icons.attach_money, color: Colors.red), tooltip: 'فروش', onPressed: () => _showSellGoldDialog(context, g)),
                      IconButton(icon: Icon(Icons.edit, size: 20), onPressed: () => _showAddEditGoldDialog(context, g)),
                      IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () {
                        showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('تأیید حذف'), content: Text('آیا از حذف این آیتم اطمینان دارید؟'), actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                          TextButton(onPressed: () { dataProvider.deleteGold(g); Navigator.pop(ctx); }, child: Text('حذف', style: TextStyle(color: Colors.red))),
                        ]));
                      }),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _statColumn(String label, String value) => Column(children: [Text(label), SizedBox(height: 4), AutoSizeText(value, style: TextStyle(fontWeight: FontWeight.bold))]);

  void _showAddEditGoldDialog(BuildContext context, GoldTransaction? existing) {
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = existing?.purchaseDate ?? DateTime.now();
    double price = existing?.purchasePricePerUnit ?? 0;
    double weight = existing?.quantity ?? 0;
    String desc = existing?.description ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'افزودن طلای آب شده' : 'ویرایش'),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    NumberInputWithToman(
                      label: 'فی خرید (ریال)',
                      initialValue: price == 0 ? '' : formatWithSeparator(price),
                      onSaved: (v) => price = double.parse(v),
                      validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                    ),
                    TextFormField(
                      initialValue: weight == 0 ? '' : formatDoubleWithoutTrailingZeros(weight),
                      decoration: InputDecoration(labelText: 'وزن (گرم)'),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                      onSaved: (v) => weight = double.parse(v!),
                    ),
                    ListTile(
                      title: Text('تاریخ خرید: ${formatJalaliDate(selectedDate)}'),
                      trailing: Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await pickJalaliDate(context, selectedDate);
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    TextFormField(
                      initialValue: desc,
                      decoration: InputDecoration(labelText: 'توضیحات'),
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      onSaved: (v) => desc = v ?? '',
                    ),
                  ],
                ),
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
                    Provider.of<DataProvider>(context, listen: false).addGold(GoldTransaction(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      type: 'gold_18',
                      purchaseDate: selectedDate,
                      purchasePricePerUnit: price,
                      quantity: weight,
                      description: desc,
                    ));
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
        ),
      ),
    );
  }

  void _showSellGoldDialog(BuildContext context, GoldTransaction lot) {
    final currentPrice = Provider.of<PriceProvider>(context, listen: false).prices[lot.type]?.currentPrice ?? 0;
    final priceCtrl = TextEditingController(
      text: currentPrice == 0 ? '' : formatWithSeparator(currentPrice)
    );
    final qtyCtrl = TextEditingController(text: formatDoubleWithoutTrailingZeros(lot.remainingQuantity));
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('فروش طلا'),
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('موجودی: ${formatDoubleWithoutTrailingZeros(lot.remainingQuantity)} گرم'),
          TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'مقدار فروش (گرم)'),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          ),
          NumberInputWithToman(
            label: 'قیمت فروش هر گرم (ریال)',
            initialValue: priceCtrl.text,
            onSaved: (v) => priceCtrl.text = v,
            isPrice: true,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
        ElevatedButton(onPressed: () {
          final q = double.tryParse(qtyCtrl.text) ?? 0;
          final p = double.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          if (q > 0 && q <= lot.remainingQuantity) {
            Provider.of<DataProvider>(context, listen: false).sellGold(lot, q, p);
            Navigator.pop(ctx);
          }
        }, child: Text('فروش')),
      ],
    ));
  }
}

class CoinListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final activeCoins = dataProvider.activeCoins;
    int totalCoins = activeCoins.fold(0, (s, c) => s + c.remainingCount);
    int rub = activeCoins.where((c) => c.coinType == 'coin_quarter').fold(0, (s, c) => s + c.remainingCount);
    int nim = activeCoins.where((c) => c.coinType == 'coin_half').fold(0, (s, c) => s + c.remainingCount);
    int tamam = activeCoins.where((c) => c.coinType == 'coin_new' || c.coinType == 'coin_old').fold(0, (s, c) => s + c.remainingCount);
    double totalPaid = activeCoins.fold(0, (s, c) => s + c.purchasePricePerUnit * c.remainingCount);

    return Scaffold(
      appBar: GlassAppBar(
        title: 'سکه‌ها',
        actions: [IconButton(icon: Icon(Icons.add), onPressed: () => _showAddEditCoinDialog(context, null))],
      ),
      body: Column(children: [
        Card(margin: EdgeInsets.all(8), child: Padding(padding: EdgeInsets.all(12), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _statColumn('ربع', '$rub'), _statColumn('نیم', '$nim'), _statColumn('تمام', '$tamam'),
          ]),
          Divider(),
          Text('تعداد کل: $totalCoins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]))),
        Card(margin: EdgeInsets.symmetric(horizontal: 8), child: ListTile(title: Text('مجموع مبلغ پرداختی'), trailing: AutoSizeText(formatRial(totalPaid), style: TextStyle(fontWeight: FontWeight.bold)))),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: 200),
            children: activeCoins.map((c) {
              final cp = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
              final paid = c.purchasePricePerUnit * c.remainingCount;
              final currentValue = cp * c.remainingCount;
              final profit = currentValue - paid;
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: AutoSizeText('${c.remainingCount} ${coinName(c.coinType)}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AutoSizeText('فی خرید: ${formatRial(c.purchasePricePerUnit)}'),
                      AutoSizeText('ارزش فعلی: ${formatRial(currentValue)}'),
                      AutoSizeText('سود خالص: ${formatRial(profit)}', style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                      if (c.description.isNotEmpty) AutoSizeText(c.description, style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: Icon(Icons.attach_money, color: Colors.red), tooltip: 'فروش', onPressed: () => _showSellCoinDialog(context, c)),
                      IconButton(icon: Icon(Icons.edit, size: 20), onPressed: () => _showAddEditCoinDialog(context, c)),
                      IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () {
                        showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('تأیید حذف'), content: Text('آیا از حذف این آیتم اطمینان دارید؟'), actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                          TextButton(onPressed: () { dataProvider.deleteCoin(c); Navigator.pop(ctx); }, child: Text('حذف', style: TextStyle(color: Colors.red))),
                        ]));
                      }),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
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
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'افزودن سکه' : 'ویرایش'),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Form(
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
                    NumberInputWithToman(
                      label: 'فی خرید (ریال)',
                      initialValue: price == 0 ? '' : formatWithSeparator(price),
                      onSaved: (v) => price = double.parse(v),
                      validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                    ),
                    TextFormField(
                      initialValue: count == 0 ? '' : count.toString(),
                      decoration: InputDecoration(labelText: 'تعداد'),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      validator: (v) => v!.isEmpty ? 'وارد کنید' : null,
                      onSaved: (v) => count = int.parse(v!),
                    ),
                    ListTile(
                      title: Text('تاریخ خرید: ${formatJalaliDate(selectedDate)}'),
                      trailing: Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await pickJalaliDate(context, selectedDate);
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    TextFormField(
                      initialValue: desc,
                      decoration: InputDecoration(labelText: 'توضیحات'),
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      onSaved: (v) => desc = v ?? '',
                    ),
                  ],
                ),
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
                    Provider.of<DataProvider>(context, listen: false).addCoin(CoinTransaction(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      coinType: coinType,
                      purchaseDate: selectedDate,
                      purchasePricePerUnit: price,
                      count: count,
                      description: desc,
                    ));
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
      ),
    );
  }

  void _showSellCoinDialog(BuildContext context, CoinTransaction lot) {
    final currentPrice = Provider.of<PriceProvider>(context, listen: false).prices[lot.coinType]?.currentPrice ?? 0;
    final priceCtrl = TextEditingController(
      text: currentPrice == 0 ? '' : formatWithSeparator(currentPrice)
    );
    final cntCtrl = TextEditingController(text: lot.remainingCount.toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('فروش سکه'),
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('موجودی: ${lot.remainingCount} عدد'),
          TextField(
            controller: cntCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'تعداد فروش'),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          ),
          NumberInputWithToman(
            label: 'قیمت فروش هر عدد (ریال)',
            initialValue: priceCtrl.text,
            onSaved: (v) => priceCtrl.text = v,
            isPrice: true,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
        ElevatedButton(onPressed: () {
          final n = int.tryParse(cntCtrl.text) ?? 0;
          final p = double.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          if (n > 0 && n <= lot.remainingCount) {
            Provider.of<DataProvider>(context, listen: false).sellCoin(lot, n, p);
            Navigator.pop(ctx);
          }
        }, child: Text('فروش')),
      ],
    ));
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
      appBar: GlassAppBar(title: 'نمودارها'),
      body: ListView(
        padding: EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
        children: [
          Text('توزیع دارایی', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(height: 250, child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 40))),
          SizedBox(height: 20),
          Text('سود/زیان هر لات', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(height: 300, child: BarChart(BarChartData(barGroups: bars, titlesData: FlTitlesData(show: false), borderData: FlBorderData(show: false), gridData: FlGridData(show: false)))),
          SizedBox(height: 20),
          Text('روند سرمایه‌گذاری (هزینه تجمعی)', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(height: 200, child: LineChart(LineChartData(
            lineBarsData: [
              LineChartBarData(spots: spots, isCurved: true, color: Colors.blue, barWidth: 3, dotData: FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1))),
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
          ))),
          SizedBox(height: 80),
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

class _Lot { final DateTime date; final double cost; _Lot(this.date, this.cost); }

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final secondaryColor = settings.secondaryColor;

    return Scaffold(
      appBar: GlassAppBar(title: 'تنظیمات'),
      body: ListView(
        padding: EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
        children: [
          Card(
            child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
              Text('نرخ سود بانکی'),
              Slider(value: settings.bankInterestRate, min: 0, max: 50, divisions: 100, label: '${settings.bankInterestRate.toStringAsFixed(1)}%', onChanged: (v) => settings.setBankInterestRate(v)),
              Text('${settings.bankInterestRate.toStringAsFixed(1)}%'),
            ])),
          ),
          Card(
            child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
              Text('فاصله به‌روزرسانی خودکار (ثانیه)'),
              Slider(value: settings.autoUpdateInterval.toDouble(), min: 30, max: 600, divisions: (600-30)~/10, label: '${settings.autoUpdateInterval}', onChanged: (v) { settings.setAutoUpdateInterval(v.toInt()); priceProvider.setAutoUpdateInterval(v.toInt()); }),
              Text('${settings.autoUpdateInterval} ثانیه'),
            ])),
          ),
          Card(child: ListTile(title: Text('به‌روزرسانی دستی قیمت‌ها'), trailing: Icon(Icons.refresh), onTap: priceProvider.fetchPrices)),
          Card(
            child: ListTile(
              title: Text('رنگ ثانویه'),
              trailing: CircleAvatar(backgroundColor: secondaryColor, radius: 16),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('انتخاب رنگ ثانویه'),
                    content: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: secondaryColor,
                        onColorChanged: (color) {
                          settings.setSecondaryColor(color);
                        },
                        colorPickerWidth: 300,
                        pickerAreaHeightPercent: 0.7,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('بستن'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 20),
          Text('مدیریت داده‌ها', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.upload_file, color: Colors.green),
                  title: Text('Export (خروجی گرفتن)'),
                  subtitle: Text('ذخیره تمام داده‌ها در یک فایل JSON'),
                  trailing: _isExporting ? SizedBox(width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.arrow_forward),
                  onTap: _isExporting ? null : () => _exportData(context, dataProvider),
                ),
                Divider(height: 0),
                ListTile(
                  leading: Icon(Icons.download, color: Colors.blue),
                  title: Text('Import (وارد کردن)'),
                  subtitle: Text('بازیابی داده‌ها از فایل JSON'),
                  trailing: _isImporting ? SizedBox(width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.arrow_forward),
                  onTap: _isImporting ? null : () => _importData(context, dataProvider),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          Card(child: ListTile(title: Text('نسخه ۲.۰.۰'), subtitle: Text('ساخته شده توسط امیر - بنیانگذار نخودگرام'))),
          SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _exportData(BuildContext context, DataProvider dataProvider) async {
    setState(() => _isExporting = true);
    try {
      final data = await dataProvider.exportAllData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final tempDir = await path_provider.getTemporaryDirectory();
      final file = File('${tempDir.path}/gold_coin_backup.json');
      await file.writeAsString(jsonString);

      // اشتراک‌گذاری فایل
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'فایل پشتیبان مدیریت طلا و سکه',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در خروجی گرفتن: $e')),
      );
    }
    setState(() => _isExporting = false);
  }

  Future<void> _importData(BuildContext context, DataProvider dataProvider) async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null) {
        setState(() => _isImporting = false);
        return;
      }

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // تأیید کاربر
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('هشدار!'),
          content: Text('آیا از جایگزینی تمام داده‌های فعلی با داده‌های فایل وارد شده اطمینان دارید؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('لغو')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('تأیید', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) {
        setState(() => _isImporting = false);
        return;
      }

      await dataProvider.importData(data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('داده‌ها با موفقیت بازیابی شدند')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در وارد کردن: $e')),
      );
    }
    setState(() => _isImporting = false);
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
        ChangeNotifierProvider(create: (_) => BasePriceProvider()),
        ChangeNotifierProvider(create: (_) => DataProvider(goldBox: goldBox, coinBox: coinBox, saleBox: saleBox)),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'مدیریت دارایی طلا و سکه',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: settings.secondaryColor,
              ),
              fontFamily: 'Vazir',
            ),
            home: MainScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
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
  final List<Widget> _screens = [
    HomeScreen(),
    GoldListScreen(),
    CoinListScreen(),
    ChartsScreen(),
    SettingsScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _screens[_selectedIndex],
      bottomNavigationBar: CrystalNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.black.withOpacity(0.15),
        selectedItemColor: Colors.blue.shade400,
        unselectedItemColor: Colors.white70,
        enableFloatingNavBar: true,
        borderRadius: 32,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        indicatorColor: Colors.blue.shade400.withOpacity(0.3),
        items: [
          CrystalNavigationBarItem(
            icon: Icons.home,
            selectedColor: Colors.blue.shade400,
          ),
          CrystalNavigationBarItem(
            icon: Icons.monetization_on,
            selectedColor: Colors.blue.shade400,
          ),
          CrystalNavigationBarItem(
            icon: Icons.account_balance_wallet,
            selectedColor: Colors.blue.shade400,
          ),
          CrystalNavigationBarItem(
            icon: Icons.bar_chart,
            selectedColor: Colors.blue.shade400,
          ),
          CrystalNavigationBarItem(
            icon: Icons.settings,
            selectedColor: Colors.blue.shade400,
          ),
        ],
      ),
    );
  }
}