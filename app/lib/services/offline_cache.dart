import 'package:hive_flutter/hive_flutter.dart';

/// Models

class CachedHelpline {
  final String name;
  final String number;
  final String crisisType;

  CachedHelpline({required this.name, required this.number, required this.crisisType});
}

class CachedSafeSpot {
  final String name;
  final double lat;
  final double lon;
  final String type;

  CachedSafeSpot({required this.name, required this.lat, required this.lon, required this.type});
}

class CachedFirstAid {
  final String topic;
  final String contentUr;
  final String contentEn;

  CachedFirstAid({required this.topic, required this.contentUr, required this.contentEn});
}

class QueuedReport {
  final String text;
  final String? voicePath;
  final double lat;
  final double lon;
  final DateTime createdAt;
  bool synced;

  QueuedReport({
    required this.text,
    this.voicePath,
    required this.lat,
    required this.lon,
    required this.createdAt,
    this.synced = false,
  });
}

/// Adapters

class CachedHelplineAdapter extends TypeAdapter<CachedHelpline> {
  @override
  final int typeId = 0;

  @override
  CachedHelpline read(BinaryReader reader) {
    return CachedHelpline(
      name: reader.readString(),
      number: reader.readString(),
      crisisType: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, CachedHelpline obj) {
    writer.writeString(obj.name);
    writer.writeString(obj.number);
    writer.writeString(obj.crisisType);
  }
}

class CachedSafeSpotAdapter extends TypeAdapter<CachedSafeSpot> {
  @override
  final int typeId = 1;

  @override
  CachedSafeSpot read(BinaryReader reader) {
    return CachedSafeSpot(
      name: reader.readString(),
      lat: reader.readDouble(),
      lon: reader.readDouble(),
      type: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, CachedSafeSpot obj) {
    writer.writeString(obj.name);
    writer.writeDouble(obj.lat);
    writer.writeDouble(obj.lon);
    writer.writeString(obj.type);
  }
}

class CachedFirstAidAdapter extends TypeAdapter<CachedFirstAid> {
  @override
  final int typeId = 2;

  @override
  CachedFirstAid read(BinaryReader reader) {
    return CachedFirstAid(
      topic: reader.readString(),
      contentUr: reader.readString(),
      contentEn: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, CachedFirstAid obj) {
    writer.writeString(obj.topic);
    writer.writeString(obj.contentUr);
    writer.writeString(obj.contentEn);
  }
}

class QueuedReportAdapter extends TypeAdapter<QueuedReport> {
  @override
  final int typeId = 4;

  @override
  QueuedReport read(BinaryReader reader) {
    return QueuedReport(
      text: reader.readString(),
      voicePath: reader.readBool() ? reader.readString() : null,
      lat: reader.readDouble(),
      lon: reader.readDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      synced: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, QueuedReport obj) {
    writer.writeString(obj.text);
    writer.writeBool(obj.voicePath != null);
    if (obj.voicePath != null) {
      writer.writeString(obj.voicePath!);
    }
    writer.writeDouble(obj.lat);
    writer.writeDouble(obj.lon);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeBool(obj.synced);
  }
}

/// Offline Cache Service
class OfflineCache {
  static const String boxHelplines = 'helplines';
  static const String boxSafeSpots = 'safeSpots';
  static const String boxFirstAid = 'firstAid';
  static const String boxReports = 'reports';

  static Future<void> init() async {
    await Hive.initFlutter();
    
    Hive.registerAdapter(CachedHelplineAdapter());
    Hive.registerAdapter(CachedSafeSpotAdapter());
    Hive.registerAdapter(CachedFirstAidAdapter());
    Hive.registerAdapter(QueuedReportAdapter());

    await Hive.openBox<CachedHelpline>(boxHelplines);
    await Hive.openBox<CachedSafeSpot>(boxSafeSpots);
    await Hive.openBox<CachedFirstAid>(boxFirstAid);
    await Hive.openBox<QueuedReport>(boxReports);

    await _seedFirstAid();
  }

  static Future<void> _seedFirstAid() async {
    final box = Hive.box<CachedFirstAid>(boxFirstAid);
    if (box.isNotEmpty) return; // Already seeded

    final items = [
      CachedFirstAid(
        topic: 'Drowning rescue',
        contentEn: '• Don\'t enter water\n• Throw rope/branch\n• Airway → breathing → call helpline',
        contentUr: '• پانی میں مت جائیں\n• رسی یا شاخ پھینکیں\n• سانس چیک کریں اور ہیلپ لائن کال کریں',
      ),
      CachedFirstAid(
        topic: 'Heatstroke',
        contentEn: '• Move to shade\n• Cool with water, no ice\n• Give fluids if conscious\n• Call helpline if confused/unconscious',
        contentUr: '• سائے میں لے جائیں\n• پانی سے ٹھنڈا کریں، برف نہیں\n• اگر ہوش میں ہو تو پانی پلائیں\n• ہیلپ لائن کال کریں',
      ),
      CachedFirstAid(
        topic: 'Electrocution',
        contentEn: '• Don\'t touch person\n• Cut power if possible\n• Check breathing\n• CPR if trained',
        contentUr: '• شخص کو مت چھوئیں\n• بجلی کاٹ دیں\n• سانس چیک کریں\n• سی پی آر کریں',
      ),
      CachedFirstAid(
        topic: 'Severe bleeding',
        contentEn: '• Direct pressure\n• Elevate\n• Don\'t remove embedded objects\n• Call helpline',
        contentUr: '• سیدھا دباؤ ڈالیں\n• اونچا رکھیں\n• گھسی ہوئی چیز مت نکالیں\n• ہیلپ لائن کال کریں',
      ),
    ];

    for (var item in items) {
      await box.put(item.topic, item);
    }
  }

  static Future<void> queueReport(QueuedReport report) async {
    final box = Hive.box<QueuedReport>(boxReports);
    await box.add(report);
  }

  static List<QueuedReport> getPendingReports() {
    final box = Hive.box<QueuedReport>(boxReports);
    return box.values.where((r) => !r.synced).toList();
  }

  static Future<void> markReportSynced(QueuedReport report) async {
    report.synced = true;
    final box = Hive.box<QueuedReport>(boxReports);
    // Find the key
    final key = box.keys.firstWhere((k) => box.get(k) == report, orElse: () => null);
    if (key != null) {
      await box.put(key, report);
      // or box.delete(key)
      await box.delete(key);
    }
  }
}
