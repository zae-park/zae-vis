import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

class SummariesScreen extends StatelessWidget {
  const SummariesScreen({super.key, required this.api, required this.onOpenProject});
  final WorklogApi api;
  final void Function(String slug) onOpenProject;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<String>>(
      load: api.summaryMonths,
      builder: (context, months, _) => months.isEmpty
          ? const EmptyPane('아직 월간 정리가 없습니다. 매월 첫 월요일 주간 정리 뒤에 초안이 생깁니다.')
          : _Summaries(api: api, months: months, onOpenProject: onOpenProject),
    );
  }
}

class _Summaries extends StatefulWidget {
  const _Summaries({required this.api, required this.months, required this.onOpenProject});
  final WorklogApi api;
  final List<String> months;
  final void Function(String slug) onOpenProject;

  @override
  State<_Summaries> createState() => _SummariesState();
}

class _SummariesState extends State<_Summaries> {
  late String _month = widget.months.first;
  late Future<String> Function() _load = _loader(_month);

  Future<String> Function() _loader(String m) => () => widget.api.summary(m);

  @override
  Widget build(BuildContext context) {
    return Readable(
      child: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final m in widget.months)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(m),
                    selected: m == _month,
                    onSelected: (_) => setState(() {
                      _month = m;
                      _load = _loader(m);
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<String>(
            load: _load,
            builder: (context, md, _) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: MarkdownView(md, onLink: widget.onOpenProject),
            ),
          ),
        ),
      ]),
    );
  }
}
