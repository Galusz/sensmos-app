import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/api_service.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  List<dynamic> _cities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiService>();
      final cities = await api.leaderboardCities();
      if (mounted) setState(() { _cities = cities; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ranking miast'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _cities.length,
                itemBuilder: (context, i) {
                  final c = _cities[i];
                  return Card(
                    child: ListTile(
                      leading: Text('${i + 1}',
                          style: TextStyle(
                              color: i < 3 ? AppTheme.amber : AppTheme.muted,
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      title: Text('${c['city']}',
                          style: const TextStyle(color: AppTheme.text)),
                      subtitle: Text(tr('%s nodów · %s online', [c['node_count'], c['online_count']]),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      trailing: Text('${(double.tryParse('${c['total_galu']}') ?? 0).toStringAsFixed(0)} GALU',
                          style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
