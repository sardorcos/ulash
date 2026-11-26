// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../dialogs/adaptive.dart';
import '../sheets/incoming_offer_sheet.dart';
import '../ui_format.dart';
import '../widgets/common.dart';
import '../widgets/page_banners.dart';
import '../widgets/transfer_tile.dart';

enum HistoryFilter { all, sent, received, text }

/// Incoming offers (pinned), then transfers grouped by day, newest first.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.controller,
    this.settingsButton,
    this.onSend,
  });
  final AppController controller;
  final Widget? settingsButton;
  final VoidCallback? onSend;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

sealed class _Row {}

class _DayRow extends _Row {
  _DayRow(this.label);
  final String label;
}

class _ItemRow extends _Row {
  _ItemRow(this.item);
  final TransferItem item;
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryFilter _filter = HistoryFilter.all;
  final _search = TextEditingController();
  String _query = '';
  AppController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(TransferItem t) {
    final passesFilter = switch (_filter) {
      HistoryFilter.all => true,
      HistoryFilter.sent => t.direction == TransferDirection.outgoing,
      HistoryFilter.received => t.direction == TransferDirection.incoming,
      HistoryFilter.text => t.kind == TransferKind.text,
    };
    if (!passesFilter) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return t.title.toLowerCase().contains(q) ||
        t.peerName.toLowerCase().contains(q) ||
        (t.messageText?.toLowerCase().contains(q) ?? false) ||
        t.receivedFiles.any((f) => f.name.toLowerCase().contains(q));
  }

  List<_Row> _rows(AppLocalizations l, List<TransferItem> items) {
    final rows = <_Row>[];
    String? lastDay;
    for (final item in items) {
      final day = formatDay(l, item.createdAt);
      if (day != lastDay) {
        rows.add(_DayRow(day));
        lastDay = day;
      }
      rows.add(_ItemRow(item));
    }
    return rows;
  }

  Future<void> _confirmClear() async {
    final l = context.l10n;
    final accepted = await confirmDestructive(
      context,
      title: l.clearHistoryQuestion,
      body: l.clearHistoryBody,
      confirmLabel: l.clear,
      confirmKey: const Key('confirm-clear-history'),
    );
    if (accepted && mounted) await runAction(context, c, c.clearHistory);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final items = c.transfers.where(_matches).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rows = _rows(l, items);
    final hasFinished = c.transfers.any((t) => t.isTerminal);
    final offers = c.pendingTransfers;
    final filters = [
      (HistoryFilter.all, l.filterAll),
      (HistoryFilter.sent, l.filterSent),
      (HistoryFilter.received, l.filterReceived),
      if (c.capabilities.textMessages) (HistoryFilter.text, l.filterText),
    ];

    return LargeTitlePage(
      title: l.navHistory,
      storageKey: 'history',
      actions: [
        if (hasFinished)
          IconButton(
            key: const Key('clear-history'),
            tooltip: l.clearHistory,
            onPressed: c.isBusy ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ?widget.settingsButton,
      ],
      slivers: [
        SliverToBoxAdapter(child: PageBanners(controller: c)),
        if (offers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l.incomingOffers,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: offers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => IncomingOfferCard(
              key: ValueKey('offer-${offers[index].id}'),
              controller: c,
              request: offers[index],
            ),
          ),
        ],
        if (c.transfers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchBar(
                    key: const Key('history-search'),
                    controller: _search,
                    hintText: l.searchHint,
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                      scheme.surfaceContainerHigh,
                    ),
                    constraints: const BoxConstraints(minHeight: 44),
                    leading: const Icon(Icons.search_rounded),
                    trailing: [
                      if (_query.isNotEmpty)
                        IconButton(
                          tooltip: l.clear,
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (filter, label) in filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: Key('filter-${filter.name}'),
                              label: Text(label),
                              selected: _filter == filter,
                              onSelected: (_) {
                                Haptics.selection();
                                setState(() => _filter = filter);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: c.transfers.isEmpty
                  ? (offers.isEmpty
                        ? EmptyState(
                            icon: Icons.history_rounded,
                            title: l.historyEmptyTitle,
                            description: l.historyEmptyHint,
                            action: widget.onSend == null
                                ? null
                                : OutlinedButton(
                                    onPressed: widget.onSend,
                                    child: Text(l.sendFiles),
                                  ),
                          )
                        : const SizedBox.shrink())
                  : EmptyState(
                      icon: Icons.search_off_rounded,
                      title: _query.isEmpty
                          ? l.historyFilteredEmptyTitle
                          : l.nothingFound,
                      description: l.historyFilteredEmptyHint,
                    ),
            ),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              _DayRow(:final label) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _ItemRow(:final item) => Padding(
                key: ValueKey('transfer-${item.id}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: TransferTile(controller: c, item: item),
              ),
            },
          ),
      ],
    );
  }
}
