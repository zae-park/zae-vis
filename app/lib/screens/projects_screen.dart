import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key, required this.api});
  final WorklogApi api;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Project>>(
      load: api.projects,
      builder: (context, projects, reload) {
        if (projects.isEmpty) return const EmptyPane('projects/ 폴더에 프로젝트 파일이 없습니다.');
        return Readable(
          child: RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ProjectCard(
                project: projects[i],
                onTap: () => openProject(context, api, projects[i].slug),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> openProject(BuildContext context, WorklogApi api, String slug) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ProjectDetailScreen(api: api, slug: slug),
  ));
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(project.title, style: t.titleMedium)),
              if (project.status.isNotEmpty) Chip(label: Text(project.status), visualDensity: VisualDensity.compact),
            ]),
            if (project.currentState.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text.rich(inlineSpan(context, project.currentState, base: t.bodyMedium), maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (project.repos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(project.repos.join(' · '), style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
            ],
          ]),
        ),
      ),
    );
  }
}

class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.api, required this.slug});
  final WorklogApi api;
  final String slug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(slug)),
      body: AsyncView<Project>(
        load: () => api.project(slug),
        builder: (context, p, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Readable(
            child: MarkdownView(
              p.markdown ?? '',
              onLink: (s) => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                builder: (_) => ProjectDetailScreen(api: api, slug: s),
              )),
            ),
          ),
        ),
      ),
    );
  }
}
