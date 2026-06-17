import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/node_service.dart';
import '../node_config/node_location_screen.dart';

class NodesLocationScreen extends StatelessWidget {
  const NodesLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nodes = context.read<NodeService>().nodes;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Lokalizacja nodów'))),
      body: nodes.isEmpty
          ? Center(
              child: Text(tr('Brak zapisanych nodów'),
                  style: const TextStyle(color: AppTheme.muted)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                    tr('Ustaw współrzędne każdego noda osobno — pozycja na mapie '
                        'sieci i regiony scoringu.'),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 14),
                ...nodes.map((n) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.location_on_outlined,
                            color: AppTheme.purple),
                        title: Text(n.label,
                            style: const TextStyle(color: AppTheme.text)),
                        subtitle: Text(
                            '${n.id.length > 8 ? '${n.id.substring(0, 8)}…' : n.id} · ${n.ip}',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppTheme.muted),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NodeLocationScreen(
                                ip: n.ip, pin: n.pin, title: n.label),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}
