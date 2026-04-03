import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hive_flutter/hive_flutter.dart';

// Nome della box Hive per la persistenza
const String kSubBox = 'subscriptions_box';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  


  // Inizializzazione Hive
  await Hive.initFlutter();
  await Hive.openBox(kSubBox);
  
  // Imposta la barra di stato trasparente su Android
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const SubTrackApp());
}

class SubTrackApp extends StatelessWidget {
  const SubTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SubTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        fontFamily: 'Inter', 
      ),
      home: const MyHomePage(),
    );
  }
}

// ─────────────────────────────────────────
// MODELLO DATI
// ─────────────────────────────────────────
class Subscription {
  final String name;
  final double price;
  final int paymentDay;
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
    required this.color,
    this.isCanceled = false,
  });

  // Converti in Map per Hive
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'paymentDay': paymentDay,
    'nextPaymentDate': nextPaymentDate.millisecondsSinceEpoch,
    'icon': icon.codePoint,
    'color': color.value,
    'isCanceled': isCanceled,
  };

  // Crea da Map di Hive
  factory Subscription.fromMap(Map<dynamic, dynamic> map) => Subscription(
    name: map['name'],
    price: map['price'],
    paymentDay: map['paymentDay'],
    nextPaymentDate: DateTime.fromMillisecondsSinceEpoch(map['nextPaymentDate']),
    icon: IconData(map['icon'], fontFamily: 'MaterialIcons'),
    color: Color(map['color']),
    isCanceled: map['isCanceled'] ?? false,
  );
}

// ─────────────────────────────────────────
// HOME PAGE
// ─────────────────────────────────────────
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Box _box;
  List<Subscription> _allSubscriptions = [];

  // Pubblicità
 bool _isBannerLoaded = false;

  // Servizi predefiniti per il picker
  final List<Map<String, dynamic>> _availableServices = [
    {'name': 'Netflix', 'icon': Icons.movie_filter_rounded, 'color': const Color(0xFFE50914)},
    {'name': 'Spotify', 'icon': Icons.music_note_rounded, 'color': const Color(0xFF1DB954)},
    {'name': 'Disney+', 'icon': Icons.stream_rounded, 'color': const Color(0xFF006E99)},
    {'name': 'Prime Video', 'icon': Icons.play_arrow_rounded, 'color': const Color(0xFF00A8E1)},
    {'name': 'DAZN', 'icon': Icons.sports_soccer_rounded, 'color': const Color(0xFFF0FF00)},
    {'name': 'YouTube Prem.', 'icon': Icons.play_circle_filled_rounded, 'color': const Color(0xFFFF0000)},
    {'name': 'iCloud+', 'icon': Icons.cloud_done_rounded, 'color': const Color(0xFF007AFF)},
    {'name': 'ChatGPT Plus', 'icon': Icons.bolt, 'color': const Color(0xFF10A37F)},
    {'name': 'Altro', 'icon': Icons.add_circle_outline_rounded, 'color': const Color(0xFF6C63FF)},
  ];

  @override
  void initState() {
    super.initState();
    _box = Hive.box(kSubBox);
    _loadFromHive();
    }


  @override
  void dispose() {
    super.dispose();
  }

  // Caricamento dati da Hive
  void _loadFromHive() {
    final rawData = _box.get('subs', defaultValue: []);
    setState(() {
      _allSubscriptions = (rawData as List)
          .map((item) => Subscription.fromMap(Map<dynamic, dynamic>.from(item)))
          .toList();
    });
  }

  // Salvataggio dati su Hive
  void _saveToHive() {
    final data = _allSubscriptions.map((s) => s.toMap()).toList();
    _box.put('subs', data);
  }

  // Calcolo totale mensile
  double get _totalMonthly => _allSubscriptions
      .where((s) => !s.isCanceled)
      .fold(0.0, (sum, item) => sum + item.price);

  List<Subscription> get _activeSubs => _allSubscriptions.where((s) => !s.isCanceled).toList();
  List<Subscription> get _canceledSubs => _allSubscriptions.where((s) => s.isCanceled).toList();

  // Reset dei dati
  void _resetData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        title: const Text("Reset Dati", style: TextStyle(color: Colors.white)),
        content: const Text("Sei sicuro di voler cancellare tutti i tuoi abbonamenti?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annulla")),
          TextButton(
            onPressed: () {
              setState(() => _allSubscriptions.clear());
              _box.clear();
              Navigator.pop(context);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // Funzione per gestire i rinnovi automatici (simulazione)
  void _checkAndRenew() {
    final now = DateTime.now();
    bool changed = false;
    for (var sub in _allSubscriptions) {
      if (!sub.isCanceled && sub.nextPaymentDate.isBefore(DateTime(now.year, now.month, now.day))) {
        sub.nextPaymentDate = nextPaymentFromDay(sub.paymentDay);
        changed = true;
      }
    }
    if (changed) _saveToHive();
  }

  DateTime nextPaymentFromDay(int day) {
    final now = DateTime.now();
    DateTime next = DateTime(now.year, now.month, day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year, now.month + 1, day);
    }
    return next;
  }

  void _showServicePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF16161F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text("Scegli un servizio", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 15, mainAxisSpacing: 15,
                ),
                itemCount: _availableServices.length,
                itemBuilder: (context, i) {
                  final s = _availableServices[i];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _showAddSubscriptionForm(s);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (s['color'] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: (s['color'] as Color).withOpacity(0.2)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s['icon'], color: s['color'], size: 32),
                          const SizedBox(height: 8),
                          Text(s['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSubscriptionForm(Map<String, dynamic> service) {
    final priceController = TextEditingController();
    int selectedDay = DateTime.now().day > 28 ? 1 : DateTime.now().day;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(service['icon'], color: service['color'], size: 28),
                    const SizedBox(width: 12),
                    Text("Aggiungi ${service['name']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text("COSTO MENSILE", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
                TextField(
                  controller: priceController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "0,00",
                    suffixText: "€",
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("GIORNO DI PAGAMENTO", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 40,
                    physics: const FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(initialItem: selectedDay - 1),
                    onSelectedItemChanged: (i) => setModalState(() => selectedDay = i + 1),
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 28,
                      builder: (context, index) => Center(
                        child: Text("${index + 1}", style: TextStyle(
                          color: (index + 1) == selectedDay ? service['color'] : Colors.white38,
                          fontSize: (index + 1) == selectedDay ? 22 : 18,
                          fontWeight: (index + 1) == selectedDay ? FontWeight.bold : FontWeight.normal,
                        )),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: service['color'],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      if (priceController.text.isNotEmpty) {
                        final newSub = Subscription(
                          name: service['name'],
                          price: double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0.0,
                          paymentDay: selectedDay,
                          nextPaymentDate: nextPaymentFromDay(selectedDay),
                          icon: service['icon'],
                          color: service['color'],
                        );
                        setState(() => _allSubscriptions.add(newSub));
                        _saveToHive();
                        Navigator.pop(context);
                      }
                    },
                    child: const Text("Salva abbonamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToDetail(Subscription sub) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetailScreen(
        subscription: sub,
        onCancel: () {
          setState(() => sub.isCanceled = true);
          _saveToHive();
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndRenew());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white70),
          onPressed: () => _showSettingsMenu(),
        ),
        title: const Text('SubTrack', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFF6C63FF), size: 28),
            onPressed: _showServicePicker,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)]),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SPESA MENSILE', style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text('${_totalMonthly.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _statChip('${_activeSubs.length} attivi', Icons.check_circle_outline),
                              const SizedBox(width: 8),
                              _statChip('${_canceledSubs.length} disdetti', Icons.cancel_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_activeSubs.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
                      child: Text('ATTIVI', style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _SubCard(sub: _activeSubs[i], onTap: () => _goToDetail(_activeSubs[i])),
                        childCount: _activeSubs.length,
                      ),
                    ),
                  ),
                ],
                if (_canceledSubs.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Text('DISDETTI', style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _CanceledCard(sub: _canceledSubs[i]),
                        childCount: _canceledSubs.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
          
          // --- PUBBLICITÀ BANNER ---
          
        ],
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              title: const Text("Reset Data", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _resetData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// COMPONENTI UI
// ─────────────────────────────────────────
class _SubCard extends StatelessWidget {
  final Subscription sub;
  final VoidCallback onTap;

  const _SubCard({required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final days = sub.nextPaymentDate.difference(DateTime.now()).inDays + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16161F),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sub.color.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: sub.color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(sub.icon, color: sub.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Tra $days giorni', style: TextStyle(fontSize: 12, color: days <= 3 ? Colors.orange : Colors.white38)),
                  ],
                ),
              ),
              Text('${sub.price.toStringAsFixed(2)} €', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sub.color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanceledCard extends StatelessWidget {
  final Subscription sub;
  const _CanceledCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Icon(sub.icon, color: Colors.white24),
              const SizedBox(width: 16),
              Text(sub.name, style: const TextStyle(decoration: TextDecoration.lineThrough)),
              const Spacer(),
              const Text("Disdetto", style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailScreen extends StatelessWidget {
  final Subscription subscription;
  final VoidCallback onCancel;

  const DetailScreen({super.key, required this.subscription, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(subscription.icon, size: 80, color: subscription.color),
            const SizedBox(height: 24),
            Text(subscription.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${subscription.price.toStringAsFixed(2)} € / mese', style: const TextStyle(fontSize: 20, color: Colors.white70)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  onCancel();
                  Navigator.pop(context);
                },
                child: const Text("Disdici Abbonamento", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}