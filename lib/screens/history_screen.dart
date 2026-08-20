import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> history = [];
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    final data = await DatabaseHelper.instance.getRateHistory();
    if (!mounted) return;
    setState(() {
      history = data;
      _loading = false;
    });
  }

  String _buildCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Rate Name,Rate Value,Date,Time');
    for (final row in history) {
      buffer.writeln(
        '${row['rateName']},${row['rateValue']},${row['date']},${row['time']}',
      );
    }
    return buffer.toString();
  }

  Future<void> _shareRecords() async {
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records to share yet")),
      );
      return;
    }

    setState(() => _sharing = true);

    try {
      final csvData = _buildCsv();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'rate_records_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour}${now.minute}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csvData);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Gold/Silver Rate Update Records',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not share records: $e")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          history.isEmpty
              ? "RATE UPDATE RECORDS"
              : "RATE UPDATE RECORDS (${history.length})",
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.share, size: 20, color: Colors.white),
            onPressed: _sharing ? null : _shareRecords,
            tooltip: 'Share records with owner',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : history.isEmpty
          ? const Center(
        child: Text(
          "No update records yet",
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      )
          : CenteredMaxWidth(
        maxWidth: 560,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: history.length,
          itemBuilder: (context, index) {
            final row = history[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.headerBand,
                  child: Text(
                    '${history.length - index}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.navy),
                  ),
                ),
                title: Text(
                  '${row['rateName']} : ${row['rateValue']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.navy),
                ),
                subtitle: Text(
                  '${row['date']}  •  ${row['time']}',
                  style:
                  const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: history.isEmpty
          ? null
          : FloatingActionButton.extended(
        onPressed: _sharing ? null : _shareRecords,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.share, size: 18),
        label: const Text(
          "Share with Owner",
          style: TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

