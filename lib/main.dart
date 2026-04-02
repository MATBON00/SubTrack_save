import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'dart:io' show Platform;

// ─────────────────────────────────────────
//  NOTIFICATION SERVICE
// ─────────────────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // flutter_local_notifications non supporta Windows/Linux/macOS desktop.
  // Su quelle piattaforme tutte le chiamate diventano no-op.
  static bool get _supported =>
      Platform.isAndroid || Platform.isIOS;

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (!_supported || _initialized) return;
    await init();
  }

  Future<void> init() async {
    if (!_supported || _initialized) return;
    _plugin = FlutterLocalNotificationsPlugin();
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin!.initialize(settings);

    await _plugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> schedulePaymentReminders({
    required int id,
    required String name,
    required double price,
    required DateTime paymentDate,
  }) async {
    if (!_supported) return;
    await _ensureInit();
    if (_plugin == null) return;
    await cancelReminders(id);

    final now = DateTime.now();
    final notify48h = paymentDate.subtract(const Duration(hours: 48));
    final notify24h = paymentDate.subtract(const Duration(hours: 24));

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'subtrack_reminders',
        'Promemoria Pagamenti',
        channelDescription: 'Avvisi 24h e 48h prima del rinnovo abbonamento',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    if (notify48h.isAfter(now)) {
      await _plugin!.zonedSchedule(
        id * 10,
        '⏰ Pagamento tra 48 ore',
        '$name – ${price.toStringAsFixed(2)} € il ${_fmt(paymentDate)}',
        tz.TZDateTime.from(notify48h, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    if (notify24h.isAfter(now)) {
      await _plugin!.zonedSchedule(
        id * 10 + 1,
        '🔔 Pagamento domani!',
        '$name – ${price.toStringAsFixed(2)} € il ${_fmt(paymentDate)}',
        tz.TZDateTime.from(notify24h, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelReminders(int id) async {
    if (!_supported) return;
    await _ensureInit();
    if (_plugin == null) return;
    await _plugin!.cancel(id * 10);
    await _plugin!.cancel(id * 10 + 1);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─────────────────────────────────────────
//  MODEL
// ─────────────────────────────────────────
class Subscription {
  final String name;
  final double price;

  /// Giorno del mese in cui scatta il pagamento (1-28).
  final int paymentDay;

  /// Data del prossimo pagamento, aggiornata automaticamente.
  DateTime nextPaymentDate;

  final IconData icon;
  final Color color;
  bool isCanceled;

  Subscription({
    required this.name,
    required this.price,
    required this.paymentDay,
    required this.nextPaymentDate,
    required this.icon,
    Color? color,
    this.isCanceled = false,
  }) : color = color ?? const Color(0xFF6C63FF);

  /// Avanza la data al mese successivo (mantiene il giorno originale).
  void advanceToNextMonth() {
    final d = nextPaymentDate;
    final newMonth = d.month < 12 ? d.month + 1 : 1;
    final newYear = d.month < 12 ? d.year : d.year + 1;
    // Clamp al giorno massimo del mese (es. 31 gen → 28 feb)
    final lastDay = DateTime(newYear, newMonth + 1, 0).day;
    nextPaymentDate =
        DateTime(newYear, newMonth, paymentDay.clamp(1, lastDay));
  }
}

/// Calcola la prossima data di pagamento a partire dal giorno del mese scelto.
DateTime nextPaymentFromDay(int day) {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, day);
  if (thisMonth.isAfter(now)) return thisMonth;
  // Se il giorno è già passato questo mese, vai al mese prossimo
  final newMonth = now.month < 12 ? now.month + 1 : 1;
  final newYear = now.month < 12 ? now.year : now.year + 1;
  final lastDay = DateTime(newYear, newMonth + 1, 0).day;
  return DateTime(newYear, newMonth, day.clamp(1, lastDay));
}

// ─────────────────────────────────────────
//  MAIN
// ─────────────────────────────────────────
final NotificationService _notifService = NotificationService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _notifService.init();
  runApp(const SubTrackApp());
}

class SubTrackApp extends StatelessWidget {
  const SubTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFFFF6584),
          surface: Color(0xFF16161F),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'monospace'),
          bodyLarge: TextStyle(fontFamily: 'monospace'),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────
//  HOME SCREEN
// ─────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final List<Subscription> _allSubscriptions = [];

  List<Subscription> get _activeSubs =>
      _allSubscriptions.where((s) => !s.isCanceled).toList();
  List<Subscription> get _canceledSubs =>
      _allSubscriptions.where((s) => s.isCanceled).toList();

  double get _totalMonthly =>
      _activeSubs.fold(0, (sum, item) => sum + item.price);

  final List<Map<String, dynamic>> _availableServices = [
    {'name': 'NETFLIX', 'icon': Icons.play_circle_fill, 'color': Color(0xFFE50914)},
    {'name': 'SPOTIFY', 'icon': Icons.graphic_eq, 'color': Color(0xFF1DB954)},
    {'name': 'PRIME', 'icon': Icons.local_shipping_outlined, 'color': Color(0xFF00A8E0)},
    {'name': 'DISNEY+', 'icon': Icons.auto_awesome, 'color': Color(0xFF0063E5)},
    {'name': 'YOUTUBE', 'icon': Icons.smart_display_outlined, 'color': Color(0xFFFF0000)},
    {'name': 'APPLE TV+', 'icon': Icons.apple, 'color': Color(0xFFCCCCCC)},
    {'name': 'ALTRO', 'icon': Icons.grid_view_rounded, 'color': Color(0xFF6C63FF)},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Controlla se qualche abbonamento ha superato la data di pagamento
  /// e, in caso, avanza al mese successivo e ri-schedula le notifiche.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRenew();
    }
  }

  void _checkAndRenew() {
    final now = DateTime.now();
    bool changed = false;
    for (int i = 0; i < _allSubscriptions.length; i++) {
      final sub = _allSubscriptions[i];
      if (!sub.isCanceled && sub.nextPaymentDate.isBefore(now)) {
        sub.advanceToNextMonth();
        _scheduleNotifications(i, sub);
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _scheduleNotifications(int index, Subscription sub) async {
    await _notifService.schedulePaymentReminders(
      id: index,
      name: sub.name,
      price: sub.price,
      paymentDate: sub.nextPaymentDate,
    );
  }

  void _goToDetail(Subscription sub) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailScreen(
          subscription: sub,
          onCancel: () {
            final idx = _allSubscriptions.indexOf(sub);
            setState(() => sub.isCanceled = true);
            _notifService.cancelReminders(idx);
          },
        ),
      ),
    );
  }

  void _showServicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scegli servizio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _availableServices.length,
              itemBuilder: (context, index) {
                final svc = _availableServices[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _showDetailsPicker(svc);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: (svc['color'] as Color).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (svc['color'] as Color).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(svc['icon'] as IconData, size: 28, color: svc['color'] as Color),
                        const SizedBox(height: 6),
                        Text(
                          svc['name'] as String,
                          style: TextStyle(
                            fontSize: 9,
                            color: svc['color'] as Color,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailsPicker(Map<String, dynamic> service) {
    final TextEditingController priceController = TextEditingController();
    int selectedDay = DateTime.now().day;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24, right: 24, top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: (service['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(service['icon'] as IconData,
                        color: service['color'] as Color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    service['name'] as String,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Prezzo
              const Text('Costo mensile',
                  style: TextStyle(fontSize: 12, color: Colors.white54, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    suffixText: '€',
                    suffixStyle: TextStyle(
                        color: service['color'] as Color, fontWeight: FontWeight.bold),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Giorno del pagamento — wheel picker
              const Text('Giorno del pagamento (ogni mese)',
                  style: TextStyle(fontSize: 12, color: Colors.white54, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Wheel
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Riga di selezione evidenziata
                          Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: (service['color'] as Color).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: (service['color'] as Color).withOpacity(0.35),
                                width: 1.5,
                              ),
                            ),
                          ),
                          // Fade top
                          Positioned(
                            top: 0, left: 0, right: 0,
                            height: 50,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0xFF1E1E2A),
                                    const Color(0xFF1E1E2A).withOpacity(0),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                            ),
                          ),
                          // Fade bottom
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            height: 50,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    const Color(0xFF1E1E2A),
                                    const Color(0xFF1E1E2A).withOpacity(0),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(16)),
                              ),
                            ),
                          ),
                          // Il wheel vero e proprio
                          ListWheelScrollView.useDelegate(
                            itemExtent: 44,
                            diameterRatio: 1.6,
                            perspective: 0.003,
                            physics: const FixedExtentScrollPhysics(),
                            controller: FixedExtentScrollController(
                                initialItem: selectedDay - 1),
                            onSelectedItemChanged: (i) =>
                                setModalState(() => selectedDay = i + 1),
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 28,
                              builder: (context, index) {
                                final day = index + 1;
                                final isSelected = day == selectedDay;
                                return Center(
                                  child: Text(
                                    day.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 24 : 18,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? service['color'] as Color
                                          : Colors.white38,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Label a destra
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.repeat_rounded,
                              size: 20, color: service['color'] as Color),
                          const SizedBox(height: 6),
                          const Text('del\nmese',
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Preview prossima data
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Prossimo pagamento: ${_fmtDate(nextPaymentFromDay(selectedDay))}',
                  style: TextStyle(
                      fontSize: 11,
                      color: (service['color'] as Color).withOpacity(0.8)),
                ),
              ),

              const SizedBox(height: 20),

              // Riepilogo notifiche
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (service['color'] as Color).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: (service['color'] as Color).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_outlined,
                        size: 16, color: service['color'] as Color),
                    const SizedBox(width: 8),
                    Text(
                      'Riceverai notifiche 48h e 24h prima',
                      style: TextStyle(
                          fontSize: 11,
                          color: (service['color'] as Color).withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Salva
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: service['color'] as Color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (priceController.text.isNotEmpty) {
                      final nextDate = nextPaymentFromDay(selectedDay);
                      final newSub = Subscription(
                        name: service['name'] as String,
                        price: double.tryParse(
                                priceController.text.replaceAll(',', '.')) ??
                            0.0,
                        paymentDay: selectedDay,
                        nextPaymentDate: nextDate,
                        icon: service['icon'] as IconData,
                        color: service['color'] as Color,
                      );
                      setState(() => _allSubscriptions.add(newSub));
                      final idx = _allSubscriptions.length - 1;
                      _scheduleNotifications(idx, newSub);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Salva abbonamento',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    // Controlla rinnovi ogni volta che si entra nella build (utile al boot)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndRenew());

    final bool isIOS = Platform.isIOS;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'SubTrack',
          style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold,
            color: Colors.white, letterSpacing: -0.5,
          ),
        ),
        actions: isIOS
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: _showServicePicker,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: CustomScrollView(
        slivers: [
          // ── Card totale ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spesa mensile',
                        style: TextStyle(fontSize: 13, color: Colors.white70, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                      '${_totalMonthly.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        fontSize: 42, fontWeight: FontWeight.bold,
                        color: Colors.white, letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _statChip('${_activeSubs.length} attivi',
                            Icons.check_circle_outline, Colors.white),
                        const SizedBox(width: 10),
                        if (_canceledSubs.isNotEmpty)
                          _statChip('${_canceledSubs.length} disdetti',
                              Icons.cancel_outlined, Colors.white54),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Sezione Attivi ────────────────────────────────────
          if (_activeSubs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text('ATTIVI',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 2)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sub = _activeSubs[index];
                    return _SubCard(sub: sub, onTap: () => _goToDetail(sub));
                  },
                  childCount: _activeSubs.length,
                ),
              ),
            ),
          ] else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Nessun abbonamento attivo.\nPremi + per aggiungerne uno.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white24, height: 1.6),
                  ),
                ),
              ),
            ),

          // ── Sezione Disdetti ─────────────────────────────────
          if (_canceledSubs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: Text('DISDETTI',
                    style: TextStyle(
                        color: Colors.white24, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 2)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sub = _canceledSubs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161F),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(sub.icon, color: Colors.white24, size: 18),
                            ),
                            const SizedBox(width: 14),
                            Text(sub.name,
                                style: const TextStyle(
                                    color: Colors.white24,
                                    decoration: TextDecoration.lineThrough,
                                    fontSize: 15)),
                            const Spacer(),
                            const Text('Disdetto',
                                style: TextStyle(color: Colors.white24, fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _canceledSubs.length,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),

      floatingActionButton: !isIOS
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF6C63FF),
              onPressed: _showServicePicker,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _statChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  CARD ABBONAMENTO
// ─────────────────────────────────────────
class _SubCard extends StatelessWidget {
  final Subscription sub;
  final VoidCallback onTap;

  const _SubCard({required this.sub, required this.onTap});

  /// Restituisce quanti giorni mancano al prossimo pagamento.
  int _daysLeft() {
    final now = DateTime.now();
    return sub.nextPaymentDate.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft();
    final urgentColor = days <= 2
        ? const Color(0xFFFF6584)
        : days <= 5
            ? Colors.orange
            : Colors.white38;
    final urgentLabel = days == 0
        ? 'Oggi!'
        : days == 1
            ? 'Domani!'
            : 'tra $days giorni';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16161F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sub.color.withOpacity(0.15), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: sub.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(sub.icon, color: sub.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Il ${sub.nextPaymentDate.day.toString().padLeft(2, '0')}/'
                          '${sub.nextPaymentDate.month.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: Colors.white38),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· $urgentLabel',
                          style: TextStyle(fontSize: 11, color: urgentColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${sub.price.toStringAsFixed(2)} €',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: sub.color)),
                  const Text('/mese',
                      style: TextStyle(fontSize: 10, color: Colors.white24)),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white12, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  DETAIL SCREEN
// ─────────────────────────────────────────
class DetailScreen extends StatelessWidget {
  final Subscription subscription;
  final VoidCallback onCancel;

  const DetailScreen({super.key, required this.subscription, required this.onCancel});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(sub.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    sub.color.withOpacity(0.3),
                    sub.color.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sub.color.withOpacity(0.2), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: sub.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(sub.icon, color: sub.color, size: 28),
                  ),
                  const SizedBox(height: 20),
                  Text('${sub.price.toStringAsFixed(2)} €',
                      style: const TextStyle(
                          fontSize: 40, fontWeight: FontWeight.bold,
                          color: Colors.white, letterSpacing: -1)),
                  const Text('al mese',
                      style: TextStyle(color: Colors.white38, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF16161F),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _detailRow(
                    icon: Icons.label_outline,
                    label: 'Servizio',
                    value: sub.name,
                    color: sub.color,
                  ),
                  _divider(),
                  _detailRow(
                    icon: Icons.repeat_rounded,
                    label: 'Giorno di pagamento',
                    value: 'ogni ${sub.paymentDay} del mese',
                    color: sub.color,
                  ),
                  _divider(),
                  _detailRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Prossimo pagamento',
                    value: _fmt(sub.nextPaymentDate),
                    color: sub.color,
                  ),
                  _divider(),
                  _detailRow(
                    icon: Icons.euro_outlined,
                    label: 'Costo annuale',
                    value: '${(sub.price * 12).toStringAsFixed(2)} €',
                    color: sub.color,
                  ),
                  _divider(),
                  _detailRow(
                    icon: Icons.notifications_outlined,
                    label: 'Notifiche',
                    value: '48h e 24h prima',
                    color: sub.color,
                  ),
                ],
              ),
            ),

            const Spacer(),

            if (!sub.isCanceled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF6584)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.cancel_outlined,
                      color: Color(0xFFFF6584), size: 18),
                  onPressed: () {
                    onCancel();
                    Navigator.pop(context);
                  },
                  label: const Text('Disdici abbonamento',
                      style: TextStyle(
                          color: Color(0xFFFF6584),
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
      {required IconData icon, required String label,
       required String value, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFF1E1E2A), indent: 46);
}