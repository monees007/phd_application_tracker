import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/positions_controller.dart';

class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const FilterSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Filter & sort',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: c.hasActiveFilters ? c.clearFilters : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Sort by', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in SortBy.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: c.sortBy == s,
                      onSelected: (_) => c.setSortBy(s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.hidePastDeadlines,
                onChanged: c.setHidePast,
                title: const Text('Hide passed deadlines'),
                subtitle: const Text('Keeps the board to what is still open'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.fundedOnly,
                onChanged: c.setFundedOnly,
                title: const Text('Funded positions only'),
                subtitle: const Text('Only where funding is marked Yes'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.showArchived,
                onChanged: c.setShowArchived,
                title: const Text('Include archived'),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text('University', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Any'),
                    selected: c.universityFilter == null,
                    onSelected: (_) => c.setUniversityFilter(null),
                  ),
                  for (final u in c.universities)
                    FilterChip(
                      label: Text(u),
                      selected: c.universityFilter == u,
                      onSelected: (sel) =>
                          c.setUniversityFilter(sel ? u : null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
