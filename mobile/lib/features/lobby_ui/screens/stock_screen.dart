import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:flutter/widgets.dart';

/// S13 Snack counter — shell owns the page title.
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final busy = DemoData.liveCount;
    final belowPar = DemoData.products.where((p) => p.isBelowPar).length;

    final actions = <(String, String, Color, Color)>[
      (
        'COUNT STOCK',
        'Physical count · update on hand',
        ArenaColors.textPrimary,
        const Color(0x0AFFFFFF),
      ),
      (
        'PLACE AN ORDER',
        belowPar > 0 ? '$belowPar lines below par' : 'Everything above par',
        ArenaColors.textPrimary,
        const Color(0x0AFFFFFF),
      ),
      (
        'RECEIVE DELIVERY',
        'No orders open',
        ArenaColors.textPrimary,
        const Color(0x0AFFFFFF),
      ),
      (
        'SELL TO A TAB',
        busy > 0
            ? '$busy open session${busy == 1 ? '' : 's'}'
            : 'No open sessions',
        busy > 0 ? ArenaColors.accent : ArenaColors.textPrimary.withValues(alpha: 0.4),
        busy > 0
            ? ArenaColors.accent.withValues(alpha: 0.09)
            : const Color(0x0AFFFFFF),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720
                  ? 4
                  : c.maxWidth >= 480
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 11,
                crossAxisSpacing: 11,
                childAspectRatio: cols == 1 ? 3.2 : 1.85,
                children: <Widget>[
                  for (final a in actions)
                    _ActionTile(
                      label: a.$1,
                      sub: a.$2,
                      fg: a.$3,
                      bg: a.$4,
                      ring: a.$1 == 'SELL TO A TAB' && busy > 0
                          ? ArenaColors.accent.withValues(alpha: 0.3)
                          : const Color(0x1AFFFFFF),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                Container(
                  color: ArenaColors.panel,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 16,
                        child: _colHead('PRODUCT', TextAlign.left),
                      ),
                      SizedBox(width: 96, child: _colHead('PRICE', TextAlign.right)),
                      SizedBox(width: 110, child: _colHead('ON HAND', TextAlign.right)),
                      SizedBox(width: 110, child: _colHead('PAR', TextAlign.right)),
                      SizedBox(width: 130, child: _colHead('FLAG', TextAlign.right)),
                      Expanded(
                        flex: 10,
                        child: _colHead('SOLD THIS WEEK', TextAlign.left),
                      ),
                    ],
                  ),
                ),
                for (final p in DemoData.products) _ProductRow(product: p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHead(String label, TextAlign align) {
    return Text(
      label,
      textAlign: align,
      style: LobbyFonts.mono(
        size: 9.5,
        letterSpacing: 9.5 * 0.11,
        color: ArenaColors.textPrimary.withValues(alpha: 0.38),
      ),
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({
    required this.label,
    required this.sub,
    required this.fg,
    required this.bg,
    required this.ring,
  });

  final String label;
  final String sub;
  final Color fg;
  final Color bg;
  final Color ring;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          decoration: BoxDecoration(
            color: _hover
                ? Color.lerp(widget.bg, const Color(0xFFFFFFFF), 0.06)
                : widget.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.ring),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                widget.label,
                style: LobbyFonts.display(
                  size: 16,
                  letterSpacing: 16 * 0.05,
                  color: widget.fg,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.sub,
                style: LobbyFonts.mono(
                  size: 10.5,
                  letterSpacing: 10.5 * 0.05,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final DemoProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stockFg = p.isLow || p.isNegative ? ArenaColors.warning : ArenaColors.textPrimary;
    final flagOk = !p.isBelowPar;
    final barPct = (p.soldWeek / 140).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0E13),
        border: Border(top: BorderSide(color: Color(0x0EFFFFFF))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 16,
            child: Text(
              p.name,
              style: LobbyFonts.body(size: 14.5, weight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              DemoData.inr(p.pricePaise),
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(size: 13),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${p.stock}',
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(
                size: 17,
                weight: FontWeight.w700,
                color: stockFg,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${p.par}',
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(
                size: 12.5,
                color: ArenaColors.textPrimary.withValues(alpha: 0.35),
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: flagOk
                      ? ArenaColors.accent.withValues(alpha: 0.12)
                      : ArenaColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  p.flag,
                  style: LobbyFonts.mono(
                    size: 10,
                    letterSpacing: 10 * 0.07,
                    color: flagOk ? ArenaColors.accent : ArenaColors.warning,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0x0FFFFFFF),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: barPct,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: flagOk ? ArenaColors.accent : ArenaColors.warning,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                SizedBox(
                  width: 72,
                  child: Text(
                    '${p.soldWeek} sold',
                    textAlign: TextAlign.right,
                    style: LobbyFonts.mono(
                      size: 11,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
