// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDone => 'Done';

  @override
  String get commonFailed => 'Failed';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonChange => 'Change';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonNone => 'None';

  @override
  String get commonSaved => 'Saved';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String commonError(String error) {
    return 'Error: $error';
  }

  @override
  String get settingsLanguage => 'Display language';

  @override
  String get settingsLanguageHint =>
      'Menus and buttons in this language. System follows your OS. Messages from the server are still Korean only.';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';

  @override
  String get textScaleSmall => 'Small';

  @override
  String get textScaleDefault => 'Default';

  @override
  String get textScaleLarger => 'Slightly larger';

  @override
  String get textScaleLarge => 'Large';

  @override
  String get textScaleHuge => 'Extra large';

  @override
  String askQuotaHandoff(String skips, String writer) {
    return '$skips hit its limit → written by $writer';
  }

  @override
  String get askHintClarify => 'Answer the question above (pick one or type)';

  @override
  String get askHintContinue =>
      'Follow up… (short is fine, like \"why?\" or \"download [2]\")';

  @override
  String get askHintFirst =>
      'Search, ask, or \"download the Nov 2 transcript\"';

  @override
  String get askAnswering => 'Answering';

  @override
  String get askSearching => 'Searching';

  @override
  String get askSend => 'Send';

  @override
  String get askNewConversation => 'New chat';

  @override
  String get askHistory => 'Previous chats';

  @override
  String askConversationMeta(int turns, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      turns,
      locale: localeName,
      other: '$turns turns',
      one: '1 turn',
    );
    return '$_temp0 · $when';
  }

  @override
  String get askDeleteConversation => 'Delete this chat';

  @override
  String get askIntro =>
      'Talk to your records\nType a few words to search your log, projects, reports, transcripts and collected files at once. Ask something like \"why did we put off indexing?\" and an agent answers from the passages it found, citing each as [n]. Say \"download the Nov 2 transcript\" to get that file. Agents only read your files.';

  @override
  String askAnswerBy(String agent, String detail) {
    return 'Answers by $agent · $detail';
  }

  @override
  String get askNoAgent =>
      'No agent can answer. Install Claude Code, Codex or Gemini CLI, or save an OpenRouter key in Settings.';

  @override
  String get askOpenSettings => 'Open settings';

  @override
  String get askStopping => 'Stopping…';

  @override
  String askWriting(String agent) {
    return '$agent is reading your records and writing an answer… (takes a little while)';
  }

  @override
  String get askAgentFallback => 'The agent';

  @override
  String get askStop => 'Stop';

  @override
  String get askClarifyTitle => 'Follow-up question';

  @override
  String askClarifyDone(String who) {
    return '$who · asked back because the records point several ways';
  }

  @override
  String askClarifyPrompt(String who) {
    return 'Pick one or type below · $who';
  }

  @override
  String get askSources => 'Sources';

  @override
  String askAnswerMeta(String who, String seconds, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count excerpts',
      one: '1 excerpt',
    );
    return '$who · ${seconds}s · based only on $_temp0';
  }

  @override
  String get askSearchingEllipsis => 'Searching…';

  @override
  String askSeeAllFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'See all $count results',
      one: 'See 1 result',
    );
    return '$_temp0';
  }

  @override
  String askFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get askGetAnswer => 'Get an answer';

  @override
  String askSeeAll(int count) {
    return 'See all ($count)';
  }

  @override
  String get askOneFile => 'Here is the file.';

  @override
  String askFiles(int count) {
    return 'Here are $count files.';
  }

  @override
  String get askOpen => 'Open';

  @override
  String get askStopped => 'Stopped';

  @override
  String get askAskAgain => 'Ask again';

  @override
  String get askTooltipMore => 'Click for the full excerpt and original';

  @override
  String askSourceIndex(int index, int total) {
    return 'Source $index of $total';
  }

  @override
  String get askPrevSource => 'Previous source';

  @override
  String get askNextSource => 'Next source';

  @override
  String get askNoExcerpt => '(no excerpt)';

  @override
  String get askOpenOriginal => 'Open original';

  @override
  String get memoryLayerLog => 'Log';

  @override
  String get memoryLayerDay => 'Day';

  @override
  String get memoryLayerOrigins => 'Originals';

  @override
  String get memoryLayerProjects => 'Status';

  @override
  String get memoryHideFlow => 'Hide how it flows';

  @override
  String get memoryShowFlow => 'How your notes are used';

  @override
  String get memoryMine => 'My lines';

  @override
  String get memoryFlowMineBody =>
      'Quick notes, recordings, transcripts. The digest agent can’t edit them; it only proposes changes for review.';

  @override
  String get memoryFlowDigestTitle => 'Digest lines';

  @override
  String get memoryFlowDigestBody =>
      'Lines the agent drew from collected files. Click the source to open the file.';

  @override
  String get memoryFlowUseTitle => 'Used by';

  @override
  String get memoryFlowUseBody =>
      'Search, questions and reports build on these lines and the originals.';

  @override
  String get memoryFlowSameDayTitle => 'Same day';

  @override
  String get memoryFlowSameDayBody =>
      'Your lines and the collected files are gathered on one card per date.';

  @override
  String get memoryFlowLinkedBody =>
      'Lines the digest drew from a file sit on the same card as that file.';

  @override
  String get memoryFlowOneRecordTitle => 'One record';

  @override
  String get memoryFlowOneRecordBody =>
      'Whatever shares a card is kept in one log and one search.';

  @override
  String get memoryFlowDailyTitle => 'Daily collection';

  @override
  String get memoryFlowDailyBody =>
      'git, agent sessions, shell, transcripts and connectors pile up as files by date.';

  @override
  String get memoryFlowDigestStepBody =>
      'The weekly digest reads these files and writes log lines and project status (applied after review).';

  @override
  String get memoryFlowSearchBody =>
      'The originals are indexed as they are, so search and questions find them too.';

  @override
  String get memoryFlowProjectPagesTitle => 'Project pages';

  @override
  String get memoryFlowProjectPagesBody =>
      'The digest agent keeps each project’s current state, decisions and open issues up to date.';

  @override
  String get memoryFlowLinkTitle => 'Linked to the log';

  @override
  String get memoryFlowLinkBody =>
      'A [[project]] link in a log line leads to its page.';

  @override
  String get memoryOriginsEmpty =>
      'Nothing collected yet\nPress \"Collect now\" in the Connect tab, or wait for the daily run; files by date will pile up here.';

  @override
  String memoryOriginsCount(int files, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    String _temp1 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String memoryCitedBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cited by $count lines',
      one: 'Cited by 1 line',
    );
    return '$_temp0';
  }

  @override
  String get memoryNotDigested => 'Not digested yet';

  @override
  String get memoryInboxPending => 'inbox (not digested yet)';

  @override
  String get memoryProcessed => 'digested';

  @override
  String get memoryNoteMineFilesLinked =>
      'Your lines and collected files share this day, and the digest wrote lines from those files';

  @override
  String get memoryNoteMineFiles =>
      'Your lines and collected files are grouped on this day';

  @override
  String get memoryNoteLinked =>
      'Lines written from collected files sit on the same day as those files';

  @override
  String get memoryNoteMineOnly =>
      'Only your lines. Nothing was collected this day';

  @override
  String get memoryNoteFilesOnly =>
      'Only collected files. No log lines come from them yet';

  @override
  String get memoryNoteFilesDigest =>
      'Collected files and digest lines share this day';

  @override
  String get memoryNoteDigestOnly => 'Only digest lines';

  @override
  String get memoryDayEmpty =>
      'No notes or collected files yet\nAs quick notes and collections from the Connect tab build up, each date gets one card.';

  @override
  String memoryDaySummary(int mine, int digest, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files collected files',
      one: '1 collected file',
    );
    return '$mine of mine · $digest from digest · $_temp0';
  }

  @override
  String memoryDayTogether(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days have',
      one: '1 day has',
    );
    return '$_temp0 notes and collected files together';
  }

  @override
  String memoryDayLinked(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days have',
      one: '1 day has',
    );
    return '$_temp0 lines drawn from files';
  }

  @override
  String get memoryJoined => 'Together';

  @override
  String get memoryLinked => 'Linked';

  @override
  String get memoryOneSide => 'One side';

  @override
  String get memoryCollected => 'Collected files';

  @override
  String get memoryLinesFromFiles => 'Lines from these files';

  @override
  String get memoryDayDigest => 'Digest for this day';

  @override
  String get memoryProjectStatus => 'Project status';

  @override
  String get memoryRefresh => 'Refresh';

  @override
  String get memoryProjectsHint =>
      'Current state · decisions · open issues, kept per project by the digest agent';

  @override
  String get memoryProjectsEmpty =>
      'No project pages yet\nWhen the digest runs, it makes a page for each [[project]] in the log.';

  @override
  String get logEmpty =>
      'No log yet. Write a line in log/YYYY-MM.md or wait for the weekly digest.';

  @override
  String logProposalBanner(int count, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count digest proposals are',
      one: '1 digest proposal is',
    );
    String _temp1 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines log lines',
      one: '1 log line',
    );
    return '$_temp0 waiting for review — $_temp1. Only the lines you pick go into the worklog.';
  }

  @override
  String get logReview => 'Review';

  @override
  String get logOnlyMine => 'Only my lines';

  @override
  String get logNoMatch => 'No log lines match.';

  @override
  String get logEdited => 'Line updated';

  @override
  String logOriginNotFound(String src) {
    return 'Couldn’t find the original file: $src';
  }

  @override
  String get logDeleteTitle => 'Delete this line?';

  @override
  String get logDeleted => 'Line deleted';

  @override
  String get logByDigestTip =>
      'Written by the digest agent from collected files — click the source to open it';

  @override
  String get logMineTip =>
      'Your line — the digest agent never edits it (it only proposes changes for review)';

  @override
  String get logDigest => 'Digest';

  @override
  String get logMine => 'Mine';

  @override
  String logSource(String source) {
    return 'Source: $source';
  }

  @override
  String get logMenu => 'Line menu';

  @override
  String get logEdit => 'Edit';

  @override
  String reviewApplied(int lines, int projects) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines log lines',
      one: '1 log line',
    );
    String _temp1 = intl.Intl.pluralLogic(
      projects,
      locale: localeName,
      other: '$projects projects',
      one: '1 project',
    );
    return 'Applied: $_temp0 · $_temp1';
  }

  @override
  String get reviewDismissTitle => 'Discard this digest?';

  @override
  String get reviewDismissBody =>
      'Nothing is written to the worklog. The next digest reads the same files again.';

  @override
  String get reviewDismiss => 'Discard';

  @override
  String get reviewDismissed => 'Discarded';

  @override
  String get reviewTitle => 'Review digest';

  @override
  String get reviewIntro =>
      'This is what the agent wanted to write. Pick what to keep and apply it. Anything you leave unchecked stays out of the worklog.';

  @override
  String reviewRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0 the agent wanted to delete — applying won’t delete them';
  }

  @override
  String reviewLogLines(int chosen, int total) {
    return 'Log lines ($chosen/$total)';
  }

  @override
  String get reviewNoNewLines => 'No new lines';

  @override
  String get reviewDeselectAll => 'Deselect all';

  @override
  String get reviewSelectAll => 'Select all';

  @override
  String reviewProjects(int chosen, int total) {
    return 'Projects ($chosen/$total)';
  }

  @override
  String get reviewNoProjects => 'No project changes';

  @override
  String get reviewNewFile => 'New file';

  @override
  String get reviewChanged => 'Changed';

  @override
  String reviewSummaries(int count) {
    return 'Monthly summaries ($count)';
  }

  @override
  String get reviewNoSummaries => 'No summary changes';

  @override
  String get reviewApplySummaries => 'Apply monthly summary changes';

  @override
  String reviewProcessed(int count) {
    return 'Processed inbox files ($count)';
  }

  @override
  String get reviewMoveProcessed => 'Move read inbox files to processed/';

  @override
  String reviewMore(int count) {
    return 'and $count more';
  }

  @override
  String get reviewProcessedHint =>
      'Turn off to read them again in the next digest.';

  @override
  String get reviewAgentReport => 'Agent report';

  @override
  String reviewSelected(int count) {
    return '$count selected';
  }

  @override
  String get reviewApply => 'Apply selected';

  @override
  String get reviewStatusApplied => 'Applied';

  @override
  String get reviewStatusDismissed => 'Discarded';

  @override
  String reviewLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String reviewPrevLineCount(int count) {
    return '(was $count)';
  }

  @override
  String get reviewProposed => 'Proposed';

  @override
  String get reviewCurrent => 'Current';

  @override
  String get searchPeriodAll => 'All';

  @override
  String get searchPeriodWeek => '7 days';

  @override
  String get searchPeriodMonth => '30 days';

  @override
  String get searchPeriodThisMonth => 'This month';

  @override
  String searchResultsTitle(String query) {
    return 'Results for \"$query\"';
  }

  @override
  String get searchClearFilters => 'Clear filters';

  @override
  String searchCount(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String searchCountOf(int shown, int total) {
    return '$shown of $total';
  }

  @override
  String get searchNoIndex => 'No index yet. Build the index first.';

  @override
  String get searchFailed => 'Search failed';

  @override
  String get searchOpenIndex => 'Open index status';

  @override
  String fileSpeakerNameTitle(String label) {
    return 'Name for [$label]';
  }

  @override
  String get fileSpeakerNameHint => 'e.g. Jae';

  @override
  String fileSpeakerRenamed(String from, String to) {
    return 'Renamed [$from] to [$to]';
  }

  @override
  String get fileSpeakers => 'Speakers';

  @override
  String get fileNameSpeaker => 'Name speaker';

  @override
  String get fileSpeakersHint =>
      'Click a speaker to name it. The file updates right away.';

  @override
  String get fileSpeakersDone => 'Speakers labeled';

  @override
  String get fileRelabelTitle => 'Label speakers again?';

  @override
  String get fileLabelTitle => 'Label speakers?';

  @override
  String get fileLabelBody =>
      'The kept recording is recognized again and split by who spoke into [A], [B]. It takes about as long as the recording and uses the CPU meanwhile.';

  @override
  String get fileLabelBodyNames => 'Names you gave go back to A, B.';

  @override
  String get fileLabelBodyReplace => 'The text of this file will be replaced.';

  @override
  String get fileLabelConfirm => 'Label';

  @override
  String get fileLabelQueued => 'Waiting to label speakers';

  @override
  String fileLabeling(String line) {
    return 'Labeling speakers · $line';
  }

  @override
  String get fileRelabel => 'Relabel speakers';

  @override
  String get fileLabel => 'Label speakers';

  @override
  String get fileNoSpeakers => 'This transcript doesn’t show who spoke.';

  @override
  String fileLastFailed(String error) {
    return 'Last attempt failed: $error';
  }

  @override
  String get projectsEmpty => 'No project files in projects/.';

  @override
  String get indexKiwiInstallTitle =>
      'Install Korean morphology analyzer (Kiwi)';

  @override
  String get indexTitle => 'Search index (AutoRAG Lite)';

  @override
  String get indexStatus => 'Status';

  @override
  String get indexDone => 'Indexed';

  @override
  String get indexFreshness => 'Freshness';

  @override
  String get indexStale => 'New files — needs reindexing';

  @override
  String get indexUpToDate => 'Up to date';

  @override
  String get indexSemantic => 'Semantic search';

  @override
  String get indexLastError => 'Last error';

  @override
  String indexMoreMessages(int count) {
    return '· $count more';
  }

  @override
  String get indexRefreshing => 'Indexing…';

  @override
  String get indexRefresh => 'Update index';

  @override
  String get indexRebuild => 'Rebuild';

  @override
  String get indexKeepsRunning => 'Indexing keeps going if you close this.';

  @override
  String get indexFirstSlow =>
      'The first index can take a few minutes while it builds embeddings.';

  @override
  String get indexStateReady => 'Ready';

  @override
  String get indexStateNever => 'Not indexed yet';

  @override
  String get indexStateIdle => 'Idle';

  @override
  String get indexStateNotConfigured => 'AutoRAG not set up';

  @override
  String get indexStateUnavailable => 'Can\'t connect';

  @override
  String get indexKeywords => 'Keywords';

  @override
  String get indexInstallKiwi => 'Install Kiwi';

  @override
  String indexKiwiTerminalHint(String command) {
    return 'To install, run $command in a terminal';
  }

  @override
  String get indexStarting => 'Starting index';

  @override
  String get indexStepRead => 'Reading';

  @override
  String get indexStepEmbed => 'Embedding & indexing';

  @override
  String get indexStepFinish => 'Finishing';

  @override
  String get backendTranslocated =>
      'Move zaevis to the Applications folder and open it again. (It\'s running from the download location, so it can\'t schedule the daily collect.)';

  @override
  String get backendNotInstalled => 'Not an installed app';

  @override
  String backendExitCode(int code) {
    return 'Exit code $code';
  }

  @override
  String get backendUpdateInstalledOnly =>
      'Updates work only in the installed app.';

  @override
  String get backendUpdateUnsupportedOs =>
      'Automatic updates aren\'t supported on this OS.';

  @override
  String get backendWebNoRun => 'Can\'t run in the browser';

  @override
  String get backendWebNoUpdate => 'Can\'t update in the browser';

  @override
  String get onboardingSourceGit => 'Git commits';

  @override
  String get onboardingSourceGitHint =>
      'Commits from every repository under your code folder (by author)';

  @override
  String get onboardingSourceAgents => 'Agent sessions';

  @override
  String get onboardingSourceAgentsHint =>
      'Claude Code · Codex · Gemini CLI conversations: requests → replies, edited files, commands run';

  @override
  String get onboardingSourceShell => 'Terminal history';

  @override
  String get onboardingSourceShellHint =>
      'zsh history (secrets masked). Turn on timestamps once in the Connect tab to keep when each command ran';

  @override
  String get onboardingSourceTranscripts => 'Meeting transcripts';

  @override
  String get onboardingSourceTranscriptsHint =>
      'Export folders from transcription services, and whisperX transcripts of in-app recordings';

  @override
  String get onboardingNextConnect => 'Check sources in Connect';

  @override
  String get onboardingNextConnectHint =>
      'See what each source collected, and add outside sources like Slack or Obsidian.';

  @override
  String get onboardingNextMemory => 'Take notes in Memory';

  @override
  String get onboardingNextMemoryHint =>
      'Jot one-liners with ⌘N (⌘⇧Space from any app); they back up search and answers.';

  @override
  String get onboardingNextReports => 'Turn on reports';

  @override
  String get onboardingNextReportsHint =>
      'Turn on daily and weekly reports under ⚙︎ in Reports, and an agent writes them after each collect.';

  @override
  String get onboardingLogKiwi =>
      'Installing the Korean morphology analyzer (Kiwi) — inflected Korean words match from the first index (about 130MB)';

  @override
  String onboardingLogKiwiFailed(String error) {
    return 'Kiwi install failed — you can install it later in Settings → Search: $error';
  }

  @override
  String get onboardingLogServer => 'Starting server';

  @override
  String get onboardingLogCollect =>
      'Starting first collect (last 7 days; indexing follows in the background)';

  @override
  String get onboardingPick => 'Choose';

  @override
  String get onboardingReady => 'You\'re all set';

  @override
  String get onboardingTitle => 'Get started with zaevis';

  @override
  String get onboardingReadyBody =>
      'The first collect is running, and indexing follows. Browse your records in Search, Memory and Reports, and manage sources in Connect.';

  @override
  String get onboardingIntro =>
      'Just pick where to keep your work records. The app installs the rest and collects every day. Then search them (Search), ask questions with sources (Ask), browse by date (Memory), and get daily, weekly and monthly summaries (Reports).';

  @override
  String get onboardingNext => 'What\'s next';

  @override
  String get onboardingOpenApp => 'Open app';

  @override
  String get onboardingWorklogFolder => 'Folder for your records (worklog)';

  @override
  String get onboardingReposFolder => 'Folder with your code repositories';

  @override
  String get onboardingSources => 'Data sources';

  @override
  String get onboardingSourcesHint =>
      'Change these anytime in Connect, or add connectors (any command) and outside sources (Slack, Notion, Obsidian…).';

  @override
  String get onboardingLanguage => 'Main language';

  @override
  String get onboardingLanguageHint =>
      'Recordings are transcribed in this language. You can change it or switch to auto-detect later in Settings.';

  @override
  String onboardingDaily(String time) {
    return 'Collect and update the search index daily at $time';
  }

  @override
  String get onboardingKiwiHint =>
      'Lets keyword search match inflected Korean words (인증서를) for a query (인증서). About a 130MB download; you can also install it later in Settings.';

  @override
  String get onboardingSettingUp => 'Setting up…';

  @override
  String get onboardingStart => 'Start';

  @override
  String onboardingFailed(String error) {
    return 'Setup failed: $error';
  }

  @override
  String get collectNeverCollected => 'Not collected yet';

  @override
  String get collectJustNow => 'Just now';

  @override
  String collectMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String collectHoursAgo(int count) {
    return '$count hr ago';
  }

  @override
  String collectDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get collectTranscriptionCancelled => 'Transcription cancelled';

  @override
  String get collectTimestampsTitle => 'Add a line to your shell config';

  @override
  String collectTimestampsBody(String zdotdir, String line) {
    return 'This appends the line below to ~/.zshrc (or $zdotdir/.zshrc). If it\'s already on, nothing changes.\n\n$line\n\nNew terminals will record when each command ran. Commands without a time are still collected under the day they\'re collected.';
  }

  @override
  String collectTimestampsAdded(String file) {
    return 'Added to $file. New terminals will record times.';
  }

  @override
  String collectTimestampsAlready(String file) {
    return 'Already on in $file. New terminals will record times.';
  }

  @override
  String get collectPaneNow => 'Now';

  @override
  String get collectPaneDaily => 'Daily';

  @override
  String get collectPaneOutside => 'Outside';

  @override
  String get collectQuickTitle => 'Add now';

  @override
  String get collectQuickHint =>
      'Goes into the worklog as soon as you save. Search picks it up after the next index.';

  @override
  String get collectAddedToLog => 'Added to the log';

  @override
  String get collectOneLine => 'Quick note';

  @override
  String collectSavedToInbox(String file) {
    return 'Saved to inbox: $file';
  }

  @override
  String get collectPasteTranscript => 'Paste transcript';

  @override
  String get collectRecord => 'Record';

  @override
  String collectQueuedRecordings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Queued $count recordings for transcription',
      one: 'Queued 1 recording for transcription',
    );
    return '$_temp0';
  }

  @override
  String get collectUploadRecordings => 'Upload recordings (whisperX)';

  @override
  String get collectSourcesTitle => 'Data sources';

  @override
  String get collectSourcesHint =>
      'Collected automatically every day. Turn them on or off, or collect now.';

  @override
  String get collectStarted => 'Collecting started (indexing follows)';

  @override
  String get collectCollecting => 'Collecting…';

  @override
  String get collectNow => 'Collect now';

  @override
  String collectSourceCollecting(String title) {
    return 'Collecting $title';
  }

  @override
  String collectSourceStarted(String title) {
    return 'Started collecting $title';
  }

  @override
  String get collectDeleted => 'Deleted';

  @override
  String collectConnectorAdded(String name) {
    return 'Added connector \"$name\" and started its first collect. Results show on its card.';
  }

  @override
  String get collectAddConnector => 'Add connector';

  @override
  String get collectAnyCommand =>
      'Any command that prints Markdown or text can be a data source — notes in a folder, a calendar, an export script from an internal tool.';

  @override
  String get collectExternalTitle => 'Outside sources (AutoRAG)';

  @override
  String get collectExternalHint =>
      'AutoRAG indexes places like Slack, Notion, Obsidian and GitHub directly and mixes them into search. They don\'t go into the worklog.';

  @override
  String get collectSyncing => 'Syncing…';

  @override
  String collectInstallTask(String title, String bin) {
    return 'Install $title tool ($bin)';
  }

  @override
  String collectInstalled(String bin) {
    return '$bin installed. Sign in and collect once with it, then connect.';
  }

  @override
  String collectExtOn(String title) {
    return 'Turned on $title. Syncing now.';
  }

  @override
  String collectExtOff(String title) {
    return 'Turned off $title';
  }

  @override
  String get collectSavedSyncing => 'Saved. Syncing now.';

  @override
  String collectExtConnected(String title) {
    return 'Connected $title. Starting the first sync.';
  }

  @override
  String get collectExtSyncStarted => 'Started syncing outside sources';

  @override
  String collectExtRemoved(String title) {
    return 'Removed $title';
  }

  @override
  String get collectNoExternal => 'No outside sources connected.';

  @override
  String get collectInboxTitle =>
      'inbox — goes into the log at the next weekly digest';

  @override
  String get collectTranscribeQueued => 'Waiting to transcribe';

  @override
  String get collectCancelled => 'Cancelled';

  @override
  String get collectTranscribing => 'Transcribing…';

  @override
  String get collectTranscripts => 'Transcripts';

  @override
  String get collectPendingAudio => 'Recordings waiting';

  @override
  String get collectSessionNotes => 'Claude Code session notes';

  @override
  String collectSpanHourMin(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String collectSpanMinSec(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String collectSpanSec(int seconds) {
    return '${seconds}s';
  }

  @override
  String get collectStartedChecking =>
      'Collecting started. Checking which step it\'s on…';

  @override
  String collectNoResponse(String span) {
    return 'Not responding · last signal $span ago';
  }

  @override
  String collectQuiet(String quiet, String total) {
    return 'In progress · no output for $quiet · $total total';
  }

  @override
  String collectRunning(String total) {
    return 'In progress · $total total';
  }

  @override
  String get collectStaleNote =>
      'The server stopped sending signals at this step.';

  @override
  String get collectQuietNote =>
      'Long recordings can transcribe for a while without output. While the time keeps growing, it\'s still on that step.';

  @override
  String get collectCancelTranscription => 'Cancel transcription';

  @override
  String get collectTimestampsOn => 'Record times';

  @override
  String get collectTimestampsHint =>
      'Turn on to keep when each command ran. Commands are collected either way.';

  @override
  String get collectOnePerLine => 'One per line';

  @override
  String get collectOnlyThis => 'Collect only this';

  @override
  String get collectEnvNone => 'Not set';

  @override
  String get collectEnvStored => 'Saved — type a new value to replace it';

  @override
  String get collectEnvInServer => 'Set in the server environment';

  @override
  String collectNotInstalled(String bin) {
    return 'Not installed — no $bin command';
  }

  @override
  String get collectNotConnected => 'Not connected';

  @override
  String get collectOff => 'Off';

  @override
  String get collectSyncFailed => 'Sync failed';

  @override
  String get collectConnected => 'Connected';

  @override
  String collectSyncedAgo(String ago) {
    return 'Synced $ago';
  }

  @override
  String collectChunks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chunks',
      one: '1 chunk',
    );
    return '$_temp0';
  }

  @override
  String get collectNeverSynced => 'Not synced yet';

  @override
  String collectOutbound(String what) {
    return 'Sent outside: $what';
  }

  @override
  String collectAuth(String what) {
    return 'Sign-in & tokens: $what';
  }

  @override
  String collectNeedsTool(String bin) {
    return 'Needs the $bin tool. It installs into the app\'s own folder (~/.zaevis/ext) — no admin rights needed.';
  }

  @override
  String collectInstallBin(String bin) {
    return 'Install $bin';
  }

  @override
  String get collectInstallFirst =>
      'First install it in a terminal, then sign in and collect once:';

  @override
  String get collectInstallCopied => 'Install command copied';

  @override
  String get collectCopyInstall => 'Copy install command';

  @override
  String collectNoArchive(String bin) {
    return 'No $bin archive yet. Sign in and collect once with $bin first.';
  }

  @override
  String get collectEnvHelper =>
      'Environment variable name; the value goes below';

  @override
  String collectTokenLabel(String name) {
    return 'Token value ($name)';
  }

  @override
  String get collectTokenHelper =>
      'Stored in ~/.zaevis/secrets.json (owner-only) and passed only to the search process. It won\'t be shown again.';

  @override
  String get collectNoteLabel => 'Note (optional)';

  @override
  String get collectNoteHelper =>
      'What this connection is. The answering agent sees it too.';

  @override
  String get collectConnect => 'Connect';

  @override
  String get collectSyncNow => 'Sync now';

  @override
  String get collectRemoveConnection => 'Remove connection';

  @override
  String get collectPresetFolder => 'Notes in a folder (Markdown, text)';

  @override
  String get collectPresetFolderHint =>
      'Brings in whole .md/.txt files changed during the collect period. Good for an Obsidian vault or a notes folder.';

  @override
  String get collectPresetCalendar => 'macOS Calendar events';

  @override
  String get collectPresetCalendarHint =>
      'Brings in calendar events from the collect period with title, time and attendees.';

  @override
  String get collectPresetCustom => 'Custom';

  @override
  String get collectPresetCustomHint =>
      'Any command that prints Markdown: a script, curl, an internal CLI…';

  @override
  String get collectStep1 => '1. Choose what to collect';

  @override
  String collectRequires(String what) {
    return 'Requires: $what';
  }

  @override
  String get collectStep2 => '2. Review and adjust';

  @override
  String get collectNameLabel => 'Name (lowercase letters, digits, -)';

  @override
  String get collectCommandLabel => 'Command';

  @override
  String get collectNotesFolderHelper => 'Replace ~/Notes with your folder';

  @override
  String get collectDescLabel => 'Description (optional)';

  @override
  String collectPlaceholderHelp(String dates, String times, String marker) {
    return 'Placeholders in the command are filled in at collect time:\n  $dates  →  2026-10-20  (date only)\n  $times  →  2026-10-20T00:00:00.000Z  (ISO time)\nTo split output by date, put $marker between lines. Otherwise it\'s filed under the day it\'s collected.\nAdding runs one collect right away and shows the result on the card.';
  }

  @override
  String get collectNeedNameCommand => 'Fill in a name and a command';

  @override
  String get collectAddAndCollect => 'Add and collect';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionRecording => 'Recording';

  @override
  String get settingsSectionDigest => 'Digest';

  @override
  String get settingsSectionCollect => 'Collection';

  @override
  String get settingsSectionShortcuts => 'Shortcuts';

  @override
  String get settingsSectionAdvanced => 'Advanced';

  @override
  String get settingsKiwiInstallTask =>
      'Install Korean morphological analysis (Kiwi)';

  @override
  String get settingsKiwiReindexTitle => 'Rebuild the index from scratch?';

  @override
  String get settingsKiwiReindexBody =>
      'Kiwi is installed. The current index was built by splitting on spaces, so it has to be rebuilt to find Korean words with particles and endings attached. It takes a few minutes and keeps going if you close the window.';

  @override
  String get settingsLater => 'Later';

  @override
  String get settingsReindex => 'Rebuild index';

  @override
  String get settingsReindexStarted =>
      'Started rebuilding the index from scratch';

  @override
  String get settingsMemoryAdded =>
      'Folder added to the index. Rebuilding the index from scratch.';

  @override
  String get settingsMemoryDialogTitle => 'Folder to index';

  @override
  String get settingsMemoryPathLabel => 'Folder path';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeHint =>
      'System follows the light/dark setting of macOS or Windows.';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsTextScale => 'Text size';

  @override
  String settingsTextScaleHint(int percent) {
    return 'Shows all text in the app at $percent%.';
  }

  @override
  String get settingsGroupLanguage => 'Language';

  @override
  String get settingsUserLanguage => 'Main language';

  @override
  String get settingsUserLanguageHint =>
      'The language you picked at first launch. Recordings are transcribed in it by default.';

  @override
  String get settingsTranscribeLanguage => 'Transcription language';

  @override
  String settingsTranscribeUser(String language) {
    return 'Transcribes in your main language ($language). Follows it when you change it under General.';
  }

  @override
  String get settingsTranscribeAuto =>
      'Detects the language from the start of the recording. Good for recordings in several languages, but may guess wrong when many words from another language are mixed in.';

  @override
  String settingsTranscribeFixed(String language) {
    return 'Always transcribes in $language.';
  }

  @override
  String settingsTranscribeMine(String language) {
    return 'My language ($language)';
  }

  @override
  String get settingsAutoDetect => 'Auto-detect';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsSystemNotifications => 'System notifications';

  @override
  String get settingsSystemNotificationsHint =>
      'Notifies you when a digest is ready for review, when collection fails, and when a transcription finishes. The server sends them, so they arrive even when the app window is closed.';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsNotInstalledBuild =>
      'Not an installed build (development run or web)';

  @override
  String get settingsNoVersionInfo => 'No version information';

  @override
  String settingsBuiltOn(String date) {
    return 'Built $date';
  }

  @override
  String get settingsInstalledOn => 'Installed';

  @override
  String get settingsInstalledOnHint =>
      'When this version was first opened on this computer';

  @override
  String get settingsTranscription => 'Transcription';

  @override
  String get settingsWhisperx => 'whisperX (transcription)';

  @override
  String get settingsInstalled => 'Installed';

  @override
  String get settingsWhisperxInstallHint =>
      'Once installed, recordings are transcribed automatically when uploaded (1–2 GB download)';

  @override
  String get settingsWhisperxMissing =>
      'Not installed — run \'zaevis ext install whisperx\' in a terminal';

  @override
  String get settingsWhisperxInstallTask => 'Install whisperX';

  @override
  String get settingsInstall => 'Install';

  @override
  String get settingsFastTranscribe => 'Fast transcription';

  @override
  String get settingsFastTranscribeHint =>
      'Off uses only 4 CPU cores and keeps the fan quiet. On uses every core and is about 1.4× faster, but the fan spins up.';

  @override
  String get settingsSpeakers => 'Speakers';

  @override
  String get settingsIndex => 'Index';

  @override
  String get settingsIndexOnInject => 'Index right away';

  @override
  String get settingsIndexOnInjectHint =>
      'Updates the search index as soon as you add a note or transcript. When off, changes appear only at scheduled or manual indexing.';

  @override
  String get settingsLocalEmbedding => 'Semantic search (local embeddings)';

  @override
  String get settingsLocalEmbeddingHint =>
      'Runs the Qwen3-Embedding model on this Mac to find records with similar meaning. No external services or keys. The first time, it downloads the model (1.1 GB) and rebuilds the index. When off, search is keyword-only.';

  @override
  String get settingsMemoryFolders => 'Indexed folders';

  @override
  String get settingsMemoryFoldersHint =>
      'The worklog folder is always indexed. Add folders where your other notes live. Adding or removing one rebuilds the index from scratch.';

  @override
  String get settingsWorklogFolder => 'Worklog folder';

  @override
  String get settingsRemove => 'Remove';

  @override
  String get settingsAddFolder => 'Add folder';

  @override
  String get settingsExternal => 'External services';

  @override
  String get settingsScheduleUnsupported =>
      'Automatic scheduling isn\'t supported on this OS.';

  @override
  String get settingsScheduleNone =>
      'Not scheduled — saving a time registers it.';

  @override
  String settingsScheduleRunning(String time) {
    return 'Runs daily at $time (if the Mac was asleep, runs when it wakes)';
  }

  @override
  String get settingsScheduleNotLoaded => 'Registered but not loaded yet';

  @override
  String get settingsDaily => 'Daily collection';

  @override
  String settingsDailyAt(String time) {
    return 'Runs at $time';
  }

  @override
  String get settingsLastRun => 'Last run';

  @override
  String get settingsDefault => 'Default';

  @override
  String get settingsServer => 'Server';

  @override
  String get settingsServerHint =>
      'The zaevis server the app talks to. You usually don\'t need to change it.';

  @override
  String get settingsServerAddress => 'Server address';

  @override
  String get settingsApply => 'Apply';

  @override
  String get settingsThisComputer => 'This computer';

  @override
  String get settingsOpenInBrowser => 'Open in browser';

  @override
  String get settingsInstallCli => 'Use the zaevis command in a terminal';

  @override
  String get settingsInstallCliHint =>
      'Registers the zaevis command in ~/.local/bin';

  @override
  String get settingsInstallCliTask => 'Register zaevis command';

  @override
  String get settingsRestartServer => 'Restart server';

  @override
  String get settingsOpenLogs => 'Open log folder';

  @override
  String settingsDate(int year, int month, int day) {
    return '$month/$day/$year';
  }

  @override
  String settingsUpdateDownloading(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get settingsUpdateInstalling => 'Installing and reopening…';

  @override
  String get settingsUpdateChecking => 'Checking for a new version…';

  @override
  String settingsUpdateAvailable(String version) {
    return 'New version available: $version';
  }

  @override
  String settingsUpdateAvailableBuilt(String version, String date) {
    return 'New version available: $version (built $date)';
  }

  @override
  String get settingsUpdate => 'Update';

  @override
  String get settingsUpdateNoAsset => 'No installer for this machine';

  @override
  String settingsUpdateCheckFailed(String error) {
    return 'Couldn\'t check: $error';
  }

  @override
  String get settingsCheckAgain => 'Check again';

  @override
  String get settingsUpdateNotChecked => 'Not checked yet';

  @override
  String settingsUpToDate(String time) {
    return 'Up to date · checked $time';
  }

  @override
  String get settingsCheckUpdate => 'Check for updates';

  @override
  String settingsKiwiNoRelease(String path) {
    return 'There\'s no Kiwi release for this platform. Download it yourself into $path, or set KIWI_LIBRARY_PATH and KIWI_MODEL_PATH.';
  }

  @override
  String settingsKiwiInstallHint(int mb) {
    return 'Once installed, Korean words with particles or endings attached (인증서를) match the search term (인증서). Keyword search works on Korean morphemes ($mb MB download, then a full reindex).';
  }

  @override
  String get settingsKiwiMissing =>
      'Not installed — run \'zaevis ext install kiwi\' in a terminal, then rebuild the index';

  @override
  String get settingsKiwiTitle => 'Korean morphological analysis (Kiwi)';

  @override
  String get settingsRerankTitle => 'Rerank search results (OpenRouter)';

  @override
  String settingsRerankOn(String model) {
    return 'Reorders the top 25 passages with OpenRouter\'s $model model. When on, your query and those passages leave this machine.';
  }

  @override
  String get settingsRerankNoKey =>
      'Save an OpenRouter API key below to turn this on. Without a key, nothing is sent even when on.';

  @override
  String get settingsRerankEnabled => 'Reranking on';

  @override
  String get settingsRerankNoKeySent => 'On, but nothing is sent without a key';

  @override
  String get settingsRerankDisabled => 'Reranking off';

  @override
  String get settingsRerankKey => 'OpenRouter API key';

  @override
  String settingsRerankKeySaved(String hint) {
    return 'Saved •••• $hint';
  }

  @override
  String get settingsRerankKeyHelper =>
      'Enter a new key and save to replace it. The key is stored only in ~/.zaevis/secrets.json (readable by owner only).';

  @override
  String get settingsKeySaved => 'Key saved';

  @override
  String get settingsTestConnection => 'Test connection';

  @override
  String get settingsKeyCleared => 'Key deleted';

  @override
  String get settingsDeleteKey => 'Delete key';

  @override
  String settingsRerankExternal(String requests) {
    return 'Outgoing requests now: $requests';
  }

  @override
  String get settingsDigestStarted =>
      'Digest started. It collects what is new first, then writes log lines (a few minutes).';

  @override
  String get settingsAgentAuto => 'Auto (next service on quota)';

  @override
  String settingsQuotaSkipped(String names) {
    return 'skipped $names (quota)';
  }

  @override
  String get settingsAgentOrder => 'Agent order';

  @override
  String get settingsAgentOrderHint =>
      'Reads inbox transcripts, session notes and the daily collected sources, then writes log lines, project status and monthly summaries. Blocks are tried left to right; when one hits its quota, the next takes over. Drag to reorder.';

  @override
  String get settingsOpenRouterModel => 'OpenRouter model';

  @override
  String get settingsRun => 'Run';

  @override
  String get settingsReviewFirst => 'Review project updates before applying';

  @override
  String get settingsReviewOn =>
      'Log lines go in right away; project pages and monthly summaries wait as a proposal you review.';

  @override
  String get settingsReviewOff =>
      'When off, project pages and monthly summaries also go straight into the worklog.';

  @override
  String get settingsWeekly => 'Weekly digest every Monday (project updates)';

  @override
  String settingsWeeklyNext(String next) {
    return 'Next run: $next (right after daily collection)';
  }

  @override
  String get settingsNextMonday => 'next Monday';

  @override
  String get settingsWeeklyOff =>
      'When off, project updates run only from the Weekly digest button below';

  @override
  String settingsDigestRunning(String agent) {
    return 'Digesting… ($agent)';
  }

  @override
  String get settingsDigestNow => 'Digest now';

  @override
  String get settingsNoAgent =>
      'No agent available. Install the Claude Code, Codex or Gemini CLI, or save an OpenRouter key under Search → External services.';

  @override
  String settingsDigestBy(String agent) {
    return 'Collects what is new and turns it into log lines · $agent';
  }

  @override
  String settingsPendingReviews(int count) {
    return 'Awaiting review ($count)';
  }

  @override
  String settingsProposalCounts(
      int lines, int projects, int summaries, int processed) {
    return 'Log: $lines lines · Projects: $projects · Monthly: $summaries · Inbox: $processed';
  }

  @override
  String get settingsReview => 'Review';

  @override
  String get settingsLastDigest => 'Last digest';

  @override
  String get settingsStatusPendingReview => 'Awaiting review';

  @override
  String get settingsInUse => 'In use';

  @override
  String get settingsIncluded => 'In order';

  @override
  String get settingsSkipped => 'Skipped';

  @override
  String get settingsHotkeyTitle => 'Change global shortcut';

  @override
  String get settingsHotkeyHint =>
      'Press the combination you want now: a modifier (⌘·⌃·⌥·⇧ or Ctrl·Alt·Shift) plus a letter, digit, F-key or Space.';

  @override
  String get settingsHotkeyNeedsModifier =>
      'Press it together with a modifier key';

  @override
  String get settingsHotkeyPress => 'Press keys here';

  @override
  String settingsHotkeyDefault(String key) {
    return 'Default: $key';
  }

  @override
  String get settingsSpeakersAfter =>
      'The text is saved first; speakers are added to the same file afterwards as [A], [B]. You can rename them in the original view.';

  @override
  String get settingsSpeakersNeedWhisperx =>
      'Available once whisperX is installed. No account needed.';

  @override
  String get settingsSpeakersOff => 'Off. Only the transcript text is saved.';

  @override
  String settingsSpeakersHf(String after) {
    return 'Uses the Hugging Face pyannote models. $after';
  }

  @override
  String settingsSpeakersReady(String after) {
    return 'Runs on this Mac, no account needed. $after';
  }

  @override
  String settingsSpeakersInstalling(int mb) {
    return 'Preparing speaker models… (about $mb MB)';
  }

  @override
  String settingsSpeakersFailed(String error) {
    return 'Couldn\'t prepare speaker models: $error';
  }

  @override
  String get settingsUnknownError => 'unknown error';

  @override
  String settingsSpeakersIdle(int mb) {
    return 'Runs on this Mac, no account needed. On the first recording it downloads the speaker models (about $mb MB) and the Korean alignment model (about 1.2 GB) once.';
  }

  @override
  String get settingsSpeakerLabel => 'Speaker labels';

  @override
  String get settingsPrepareAgain => 'Prepare again';

  @override
  String get settingsHfChecking => 'Checking sign-in status…';

  @override
  String settingsHfCode(String code) {
    return 'Sign in to Hugging Face in your browser and confirm the code $code.';
  }

  @override
  String get settingsHfAccount => 'your account';

  @override
  String settingsHfNeedsAccept(String user) {
    return 'Connected as $user. To use the speaker models, accept their terms on the model pages.';
  }

  @override
  String settingsHfConnected(String user) {
    return 'Connected as $user. Transcripts are saved first; speakers are added to the same file afterwards.';
  }

  @override
  String get settingsHfHint =>
      'Speaker labels work without signing in. Sign in and accept the model terms to use the original pyannote models. Labeling runs after the text is saved.';

  @override
  String get settingsHfTitle => 'Label with Hugging Face models (optional)';

  @override
  String get settingsHfAcceptPage => 'Terms pages';

  @override
  String get settingsDisconnect => 'Disconnect';

  @override
  String get settingsLogin => 'Sign in';

  @override
  String get railTitle => 'Service order';

  @override
  String railRunning(String title) {
    return '$title · writing';
  }

  @override
  String railWrote(String title) {
    return '$title · wrote';
  }

  @override
  String railQuota(String title) {
    return '$title · quota';
  }

  @override
  String railError(String title) {
    return '$title · failed';
  }

  @override
  String railLogin(String title) {
    return '$title · sign in';
  }

  @override
  String railMetered(String title) {
    return '$title · metered';
  }

  @override
  String get uiServerOffline =>
      'Make sure the server is running (`npm start` in the server folder).';

  @override
  String get uiTagDecision => 'Decision';

  @override
  String get uiTagBlocked => 'Blocked';

  @override
  String get uiTagLearned => 'Learned';

  @override
  String uiTaskFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get uiDownloading => 'Downloading';

  @override
  String uiTaskClose(String status) {
    return '$status · Close';
  }

  @override
  String get uiWeakMatch => 'Weak match';

  @override
  String get uiDownloadFile => 'Download file';

  @override
  String uiSavedTo(String path) {
    return 'Saved: $path';
  }

  @override
  String uiSaveFailed(String error) {
    return 'Couldn\'t save: $error';
  }

  @override
  String get homeStarting => 'Starting zaevis…';

  @override
  String homeStartFailed(String error) {
    return 'Couldn\'t start the server.\n$error';
  }

  @override
  String homeServerLog(String path) {
    return 'Log: $path';
  }

  @override
  String get homeTabSearch => 'Search';

  @override
  String get homeTabSearchHint => 'Find records, ask questions, download files';

  @override
  String get homeTabMemory => 'Memory';

  @override
  String get homeTabMemoryHint =>
      'Log · days · project status · collected sources — everything this app knows';

  @override
  String get homeTabReports => 'Reports';

  @override
  String get homeTabReportsHint => 'Daily · weekly · monthly reports';

  @override
  String get homeTabConnect => 'Connect';

  @override
  String get homeTabConnectHint =>
      'Data sources, external services, inbox, quick add';

  @override
  String get homeLogAdded => 'Added to the log';

  @override
  String get homeMenuSettings => 'Settings…';

  @override
  String get homeMenuLog => 'Log';

  @override
  String get homeNewLog => 'Quick note';

  @override
  String get homeRecord => 'Record';

  @override
  String get homeMenuView => 'View';

  @override
  String get homeSearchIndex => 'Search index';

  @override
  String get homeTagline => 'Work log · knowledge';

  @override
  String get homeIndex => 'Index';

  @override
  String get shortcutSearch => 'Go to search and type';

  @override
  String get shortcutNewLog => 'Quick note';

  @override
  String get shortcutRecord => 'Record';

  @override
  String get shortcutTabs => 'Search · Memory · Reports · Connect tabs';

  @override
  String get shortcutSettings => 'Settings';

  @override
  String get shortcutGlobal =>
      'Bring up the window and add a quick note from anywhere (global)';

  @override
  String apiCannotConnect(String url) {
    return 'Can\'t connect to the server: $url';
  }

  @override
  String get apiNotFound => 'Not found';

  @override
  String get apiRequestFailed => 'Request failed';

  @override
  String get apiBadResponse => 'Unexpected response format';

  @override
  String apiUploadFailed(String url) {
    return 'Upload failed: $url';
  }

  @override
  String get apiSaveFileTitle => 'Save file';

  @override
  String get apiSaveUnsupported => 'Files can\'t be saved here';

  @override
  String get updateAppNotInImage =>
      'Couldn\'t find zaevis.app in the disk image.';

  @override
  String get updateReplaceFailed => 'Couldn\'t replace the app.';

  @override
  String get updateQuarantineFailed =>
      'Couldn\'t clear the quarantine flag. Run this in Terminal:';

  @override
  String get updateMountFailed => 'Couldn\'t open the disk image.';

  @override
  String updateDownloadFailed(int status) {
    return 'Couldn\'t download the installer ($status)';
  }

  @override
  String updateGithubStatus(int status) {
    return 'GitHub responded $status';
  }

  @override
  String get updateBadRelease => 'Couldn\'t read the release info';

  @override
  String get updateAvailable => 'A new version is available';

  @override
  String get updateButton => 'Update';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get updateDownloading => 'Downloading';

  @override
  String get updateInstalling => 'Installing and reopening…';

  @override
  String get updateNoInstaller => 'No installer for this machine';

  @override
  String get updateLater => 'Later';

  @override
  String get updateNotice => 'Notice';

  @override
  String get updateFolderTitle => 'Folder access prompts every day at 18:30';

  @override
  String get updateFolderBody =>
      'The repository scan opens Desktop, Documents, Downloads, Pictures, Music and Library one by one. Collecting commits doesn\'t need them.';

  @override
  String get updateFolderApply => 'Skip them all';

  @override
  String get modelSourceGit => 'git commits';

  @override
  String get modelSourceAgentSessions => 'Agent sessions';

  @override
  String get modelSourceClaudeCode => 'Claude Code sessions';

  @override
  String get modelSourceShell => 'Shell commands';

  @override
  String get modelSourceTranscripts => 'Transcripts';

  @override
  String get modelSourceSessionNotes => 'Session notes';

  @override
  String get modelTokenizerMorphemes =>
      'Morpheme analysis (Kiwi) — finds Korean words with particles and endings attached (인증서를 → 인증서)';

  @override
  String get modelTokenizerNeedsReindex =>
      'Kiwi installed — rebuild the index from scratch to turn on morpheme analysis';

  @override
  String get modelTokenizerNextIndex =>
      'Not indexed yet — morpheme analysis from the next index';

  @override
  String get modelTokenizerSimple =>
      'Whitespace only — Korean words with particles (인증서를) won\'t match the search term (인증서)';

  @override
  String modelEmbeddingReady(String model, String device) {
    return 'On — $model ($device)';
  }

  @override
  String get modelEmbeddingLocalModel => 'local model';

  @override
  String get modelEmbeddingStarting =>
      'Starting… the first time it downloads the model (1.1 GB)';

  @override
  String modelEmbeddingFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get modelEmbeddingOff => 'Off — keyword search only';

  @override
  String get modelEmbeddingUnavailable => 'Unavailable (no minsync)';

  @override
  String modelLoginNeeded(String hint) {
    return 'Sign-in needed: $hint';
  }

  @override
  String get modelLoginInTerminal => 'sign in from Terminal';

  @override
  String modelProgressFiles(int scanned, int total) {
    return '$scanned/$total files';
  }

  @override
  String modelProgressChunks(int count) {
    return '$count';
  }

  @override
  String get modelProgressParsed => 'Reading files';

  @override
  String get modelProgressEmbedding => 'Embedding and indexing';

  @override
  String get modelProgressDatasources => 'Indexing connectors';

  @override
  String get modelProgressKeywords => 'Building the keyword index';

  @override
  String get modelProgressFileNames => 'Indexing file names';

  @override
  String get modelProgressFinalizing => 'Finishing up';

  @override
  String get modelProgressPreparing => 'Preparing';

  @override
  String get modelKindDaily => 'Daily';

  @override
  String get modelKindWeekly => 'Weekly';

  @override
  String get modelKindMonthly => 'Monthly';

  @override
  String get modelKindDailyWord => 'daily';

  @override
  String get modelKindWeeklyWord => 'weekly';

  @override
  String get modelKindMonthlyWord => 'monthly';

  @override
  String get modelWeekdayMon => 'Mon';

  @override
  String get modelWeekdayTue => 'Tue';

  @override
  String get modelWeekdayWed => 'Wed';

  @override
  String get modelWeekdayThu => 'Thu';

  @override
  String get modelWeekdayFri => 'Fri';

  @override
  String get modelWeekdaySat => 'Sat';

  @override
  String get modelWeekdaySun => 'Sun';

  @override
  String get modelToday => 'Today';

  @override
  String get modelYesterday => 'Yesterday';

  @override
  String get modelThisWeek => 'This week';

  @override
  String get modelLastWeek => 'Last week';

  @override
  String get modelThisMonth => 'This month';

  @override
  String get modelLastMonth => 'Last month';

  @override
  String get reportsNone => 'No report';

  @override
  String get reportsSettings => 'Report settings';

  @override
  String reportsEmpty(String kind) {
    return 'No $kind reports yet.\nUse \"Make now\", or turn on days in settings (⚙︎) to write them automatically after each daily collection.';
  }

  @override
  String reportsPeriodNoService(String period) {
    return '$period · no service';
  }

  @override
  String get reportsMakeNow => 'Make now';

  @override
  String get reportsNoServiceWas => 'No service was available';

  @override
  String get reportsFailed => 'Couldn\'t write the report';

  @override
  String get reportsRemake => 'Make again';

  @override
  String reportsWrittenBy(String agent, String detail) {
    return 'Reports are written by $agent · $detail';
  }

  @override
  String get reportsNoAgent =>
      'No agent available. Install the Claude Code, Codex or Gemini CLI, or save an OpenRouter key in settings.';

  @override
  String reportsRunning(String kind, String period, String agent) {
    return 'Writing the $kind report for $period… $agent This takes from tens of seconds to a few minutes.';
  }

  @override
  String get reportsNoService => 'No service available';

  @override
  String get reportsDigest => 'Digest';

  @override
  String get reportsDaily => 'Daily report';

  @override
  String get reportsDailyHint =>
      'Summarizes each chosen day after that day\'s collection (the previous day when it runs in the morning).';

  @override
  String get reportsWeekdays => 'Weekdays';

  @override
  String get reportsWeekend => 'Weekend';

  @override
  String get reportsEveryday => 'Every day';

  @override
  String get reportsWeekly => 'Weekly report';

  @override
  String get reportsWeeklyHint =>
      'On the chosen day, summarizes the week (Mon–Sun) containing the day before. On Monday, that\'s last week.';

  @override
  String reportsWeekdayName(String day) {
    return '$day';
  }

  @override
  String get reportsMonthly => 'Monthly report';

  @override
  String get reportsMonthlyHint =>
      'On the chosen day each month, summarizes last month (summaries/YYYY-MM.md, the monthly digest slot).';

  @override
  String reportsMonthDay(int day) {
    return 'Day $day';
  }

  @override
  String get recordPreparing => 'Preparing transcription';

  @override
  String get recordTranscribing => 'Transcribing…';

  @override
  String get recordMicDenied =>
      'Microphone access isn\'t allowed. Turn on zaevis in System Settings → Privacy & Security → Microphone.';

  @override
  String recordError(String error) {
    return 'Recording error: $error';
  }

  @override
  String recordStartFailed(String error) {
    return 'Couldn\'t start recording: $error';
  }

  @override
  String get recordTranscribeFailed => 'Transcription failed';

  @override
  String get recordTranscribeFailedLong => 'Transcription failed';

  @override
  String get recordQueued => 'Waiting to transcribe';

  @override
  String get recordCancelling => 'Cancelling';

  @override
  String get recordTitle => 'Recording';

  @override
  String get recordUploading => 'Uploading…';

  @override
  String get recordTapToStart => 'Press to start recording';

  @override
  String get recordHintRecording =>
      'When you stop, it goes to the inbox and is transcribed right away if whisperX is installed.';

  @override
  String get recordHintTranscribing =>
      'Closing (top right) keeps the transcription going. The recording stays in the inbox.';

  @override
  String get recordHintIdle =>
      'Saved as 16 kHz mono WAV, about 2 MB per minute. You\'ll be asked for microphone access the first time.';

  @override
  String get recordCancelTranscription => 'Cancel transcription';

  @override
  String get recordStopUpload => 'Stop and upload';

  @override
  String get recordStart => 'Start recording';

  @override
  String recordQueuedToast(String file) {
    return 'Recording queued for transcription: $file';
  }

  @override
  String get trailRecognizing => 'Recognizing';

  @override
  String trailRecognizingDetail(String detail) {
    return 'Recognizing · $detail';
  }

  @override
  String get trailSpeakersQueued => 'Queued · speakers will be labeled soon';

  @override
  String trailSpeakersRunning(String detail) {
    return 'Labeling speakers · $detail';
  }

  @override
  String get trailQueued => 'Queued · transcription starts soon';

  @override
  String get trailTranscribing => 'transcribing';

  @override
  String trailFailed(String error) {
    return 'Transcription failed · $error';
  }

  @override
  String get trailCanRetry => 'you can try again';

  @override
  String get trailNextCollect => 'Queued · transcribed at the next collection';

  @override
  String get trailLinked => 'Linked · this transcript is part of a digest.';

  @override
  String get trailIndexing => 'Indexing · searchable when done';

  @override
  String get trailWaitingDigest =>
      'Searchable · waiting for the digest. Becomes a memory source after the weekly digest';

  @override
  String get trailSaved => 'Text saved · included in the next index';

  @override
  String trailFilteredOut(int total) {
    return 'None of the $total results match this period or source.';
  }

  @override
  String get trailSearchIndexing => 'Indexing. Search again when it\'s done.';

  @override
  String trailMore(int count) {
    return 'and $count more';
  }

  @override
  String trailPendingTranscripts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transcripts were just saved',
      one: '1 transcript was just saved',
    );
    return '$_temp0. Searchable once indexing finishes.';
  }

  @override
  String trailNoResultsLatin(String query) {
    return 'No results for \"$query\". Records are often in Korean — try asking in Korean.';
  }

  @override
  String trailNoResults(String query) {
    return 'No results for \"$query\".';
  }

  @override
  String get inputEditLine => 'Edit line';

  @override
  String get inputNewLog => 'Quick note';

  @override
  String get inputLogHint => 'What you did, and why';

  @override
  String get inputDate => 'Date';

  @override
  String inputDigestLine(String source) {
    return 'Written by the digest. Its source ($source) is kept.';
  }

  @override
  String get inputProject => 'Project (optional)';

  @override
  String get inputPasteTranscript => 'Paste transcript';

  @override
  String get inputTitle => 'Title';

  @override
  String get inputTitleHint => 'Weekly review meeting';

  @override
  String get inputPasteHint =>
      'Paste the text you copied from a transcription service';

  @override
  String get voiceStart => 'Speak';

  @override
  String get voiceStop => 'Done speaking';

  @override
  String voiceListening(String elapsed) {
    return 'Listening $elapsed · press again to send';
  }

  @override
  String get voiceConverting => 'Turning speech into text…';

  @override
  String get voiceNothing => 'Nothing was heard. Please try again.';

  @override
  String voiceFailed(String error) {
    return 'Couldn\'t turn the speech into text: $error';
  }

  @override
  String apiVoiceFailed(String url) {
    return 'Couldn\'t send the recording: $url';
  }

  @override
  String get knTitle => 'Knowledge status';

  @override
  String get knStepCollect => 'Collected';

  @override
  String get knStepWaiting => 'To digest';

  @override
  String get knStepReview => 'To review';

  @override
  String get knStepKnowledge => 'Knowledge';

  @override
  String get knStepReports => 'Reports';

  @override
  String get knNone => 'none';

  @override
  String knCollectValue(int count) {
    return '$count day files';
  }

  @override
  String knLatest(String day) {
    return 'latest $day';
  }

  @override
  String knWaitingValue(int days) {
    return '$days days of sources';
  }

  @override
  String knWaitingFiles(int files) {
    return '$files transcripts/sessions';
  }

  @override
  String knLastDigest(String day) {
    return 'last digest $day';
  }

  @override
  String get knNeverDigested => 'never digested';

  @override
  String knReviewValue(int lines, int projects) {
    return '$lines lines · $projects projects';
  }

  @override
  String get knReviewNone => 'nothing waiting';

  @override
  String knKnowledgeValue(int lines) {
    return '$lines log lines';
  }

  @override
  String knKnowledgeSub(int projects, int summaries) {
    return '$projects projects · $summaries monthly';
  }

  @override
  String knReportsValue(int m, int w, int d) {
    return 'monthly $m · weekly $w · daily $d';
  }

  @override
  String knReportsOn(String kinds) {
    return 'automatic: $kinds';
  }

  @override
  String get knReportsOff => 'automatic reports off';

  @override
  String get knKindDaily => 'daily';

  @override
  String get knKindWeekly => 'weekly';

  @override
  String get knKindMonthly => 'monthly';

  @override
  String get knNextRunning =>
      'Digesting now. Log lines go in right away; project updates, if any, wait for review.';

  @override
  String knNextReview(int days, int lines, int projects) {
    return 'A digest proposal has waited $days days for review — $lines log lines, $projects projects. Search, questions and reports use it once applied.';
  }

  @override
  String knNextReviewToday(int lines, int projects) {
    return 'A digest proposal is waiting for review — $lines log lines, $projects projects. Search, questions and reports use it once applied.';
  }

  @override
  String get knNextCollectFailed =>
      'The last daily collection failed. See which source failed in the Connect tab.';

  @override
  String get knNextNothing =>
      'Nothing collected yet. Turn sources on in the Connect tab and collect now.';

  @override
  String get knNextNoAgent =>
      'Sources are waiting, but no agent can digest them. Sign in to a CLI such as Claude Code or save an OpenRouter key.';

  @override
  String knNextDigest(int days, int files) {
    return '$days days of sources and $files transcripts/sessions arrived since the last digest. A digest turns them into log lines.';
  }

  @override
  String get knNextReports =>
      'Turn reports on and a weekly summary of what was done, decided and next is written from these records.';

  @override
  String get knNextAllSet => 'Everything is digested.';

  @override
  String knNextAllSetWhen(String day) {
    return 'Everything is digested. Next automatic digest $day.';
  }

  @override
  String get knActionReview => 'Review';

  @override
  String get knActionConnect => 'Open Connect';

  @override
  String get knActionSettings => 'Open settings';

  @override
  String get knActionDigest => 'Digest now';

  @override
  String get knActionReports => 'Report settings';

  @override
  String get knDigestStarted =>
      'Digest started. It collects what is new first, then writes log lines (a few minutes).';

  @override
  String get knShowSteps => 'Show steps';

  @override
  String get knHideSteps => 'Hide steps';

  @override
  String reviewGroupsTitle(int projects, int lines) {
    return '$projects projects · $lines log lines';
  }

  @override
  String get reviewGroupsHint =>
      'Grouped by project. Checking a project takes its log lines and its project page together; expand it to pick single lines.';

  @override
  String get reviewNoProject => 'No project';

  @override
  String reviewGroupLines(int chosen, int lines) {
    return '$chosen/$lines log lines';
  }

  @override
  String reviewGroupPage(String badge) {
    return 'page $badge';
  }

  @override
  String get onbFirstDigestTitle => 'Try a first digest';

  @override
  String onbFirstDigestBody(String agent) {
    return '$agent reads what was just collected and writes log lines. It takes a few minutes; open the app to see progress at the top of the Memory tab. From now on this runs after every daily collection.';
  }

  @override
  String get onbFirstDigestButton => 'Start the first digest';

  @override
  String get onbFirstDigestStarted =>
      'First digest started. Progress shows at the top of the Memory tab, and the log lines go in when it finishes.';

  @override
  String get onbFirstDigestNoAgent =>
      'No agent can digest yet, so the first digest is skipped. Sign in to a CLI such as Claude Code, then use \'Digest now\' in the memory tab.';

  @override
  String askBasis(int knowledge, int raw) {
    return 'Based on: $knowledge digested · $raw raw';
  }

  @override
  String get askBasisRawOnly =>
      'No digested records matched, so only raw sources were used. Digesting in the memory tab makes the basis shorter and clearer.';

  @override
  String get askSourceKnowledge => 'Digested record';

  @override
  String get askSourceRaw => 'Raw source';

  @override
  String get settingsDailyOn =>
      'After each daily collection, that day\'s records become log lines, without review.';

  @override
  String get settingsDailyOff =>
      'When off, log lines come only from the Monday digest and Digest now.';

  @override
  String get settingsWeeklyNow => 'Weekly digest';

  @override
  String get settingsWeeklyStarted =>
      'Weekly digest started. Project updates will wait for your review.';

  @override
  String get knNextAllSetDaily =>
      'Everything is digested. Each day\'s records become log lines after collection.';

  @override
  String get settingsDailyDigest => 'Daily digest';
}
