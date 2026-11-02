import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// A Patreon poll's results as bars, like a closed poll on X. The archive
/// can't vote, so the choices aren't tappable.
class PollView extends StatelessWidget {
  const PollView(this.poll, {super.key, this.compact = false});

  final Poll poll;

  /// Leaves out the description, for feed cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    final most = poll.mostVotes;
    final closes = poll.closesAt;
    final closed = poll.closedAt(DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_outlined, size: 18, color: pawPink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.title.isEmpty ? 'Poll' : poll.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (!compact && poll.description != null) ...[
            const SizedBox(height: 4),
            Text(poll.description!, style: TextStyle(color: ink(.7))),
          ],
          const SizedBox(height: 8),
          for (final choice in poll.choices)
            _ChoiceBar(
              choice: choice,
              share: total == 0 ? 0 : choice.votes / total,
              leading: most > 0 && choice.votes == most,
            ),
          const SizedBox(height: 2),
          Text(
            [
              total == 1 ? '1 vote' : '${compactCount(total)} votes',
              if (closes != null)
                closed
                    ? 'Closed ${longDate(closes)}'
                    : 'Closes ${longDate(closes)}',
              if (poll.allowMultiple) 'Multiple choice',
            ].join(' · '),
            style: TextStyle(color: ink(.5), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ChoiceBar extends StatelessWidget {
  const _ChoiceBar({
    required this.choice,
    required this.share,
    required this.leading,
  });

  final PollChoice choice;
  final double share;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final weight = leading ? FontWeight.w700 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: share,
                child: ColoredBox(
                  color: leading ? pawPink.withValues(alpha: .35) : ink(.1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      choice.text,
                      style: TextStyle(fontWeight: weight),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(share * 100).round()}%',
                    style: TextStyle(fontWeight: weight, color: ink(.85)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
