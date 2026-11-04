// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get commonCancel => '취소';

  @override
  String get commonSave => '저장';

  @override
  String get commonClose => '닫기';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonDone => '완료';

  @override
  String get commonFailed => '실패';

  @override
  String get commonAdd => '추가';

  @override
  String get commonClear => '지우기';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonChange => '바꾸기';

  @override
  String get commonDownload => '내려받기';

  @override
  String get commonSettings => '설정';

  @override
  String get commonSearch => '검색';

  @override
  String get commonNone => '없음';

  @override
  String get commonSaved => '저장했습니다';

  @override
  String get commonCopy => '복사';

  @override
  String get commonCopied => '복사했습니다';

  @override
  String commonError(String error) {
    return '오류: $error';
  }

  @override
  String get settingsLanguage => '화면 언어';

  @override
  String get settingsLanguageHint =>
      '앱의 메뉴·버튼 글자를 이 언어로 보여 줍니다. 시스템은 운영체제 언어를 따릅니다. 서버가 보내는 메시지는 아직 한국어로만 나옵니다.';

  @override
  String get settingsLanguageSystem => '시스템';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';

  @override
  String get textScaleSmall => '작게';

  @override
  String get textScaleDefault => '기본';

  @override
  String get textScaleLarger => '조금 크게';

  @override
  String get textScaleLarge => '크게';

  @override
  String get textScaleHuge => '아주 크게';

  @override
  String askQuotaHandoff(String skips, String writer) {
    return '$skips 할당량 → $writer가 작성';
  }

  @override
  String get askHintClarify => '위 질문에 답해 주세요 (고르거나 직접 적기)';

  @override
  String get askHintContinue => '이어서… (\"그건 왜?\", \"[2] 내려받기\"처럼 짧게 이어도 됩니다)';

  @override
  String get askHintFirst => '찾을 말, 질문, 또는 \"11월 2일 전사본 내려받기\"';

  @override
  String get askAnswering => '답하는 중';

  @override
  String get askSearching => '찾는 중';

  @override
  String get askSend => '보내기';

  @override
  String get askNewConversation => '새 대화';

  @override
  String get askHistory => '이전 대화';

  @override
  String askConversationMeta(int turns, String when) {
    return '$turns턴 · $when';
  }

  @override
  String get askDeleteConversation => '이 대화 지우기';

  @override
  String get askIntro =>
      '기록에 말을 거세요\n단어를 넣으면 로그 · 프로젝트 · 리포트 · 전사본 · 수집 원본에서 바로 찾습니다. \"색인은 왜 미뤘지?\"처럼 물으면 찾은 문단만 근거로 에이전트가 출처 [번호]를 달아 답합니다. \"11월 2일 전사본 내려받기\"처럼 말하면 그 파일을 내려받을 수 있습니다. 에이전트는 파일을 읽기만 합니다.';

  @override
  String askAnswerBy(String agent, String detail) {
    return '답은 $agent가 씁니다 · $detail';
  }

  @override
  String get askNoAgent =>
      '답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.';

  @override
  String get askOpenSettings => '설정 열기';

  @override
  String get askStopping => '멈추는 중…';

  @override
  String askWriting(String agent) {
    return '$agent가 기록을 읽고 답을 쓰는 중… (수십 초)';
  }

  @override
  String get askAgentFallback => '에이전트';

  @override
  String get askStop => '멈추기';

  @override
  String get askClarifyTitle => '되묻기';

  @override
  String askClarifyDone(String who) {
    return '$who · 기록이 여러 갈래라 되물었습니다';
  }

  @override
  String askClarifyPrompt(String who) {
    return '고르거나 아래에 직접 적어 주세요 · $who';
  }

  @override
  String get askSources => '근거';

  @override
  String askAnswerMeta(String who, String seconds, int count) {
    return '$who · $seconds초 · 발췌 $count개만 근거로 썼습니다';
  }

  @override
  String get askSearchingEllipsis => '찾는 중…';

  @override
  String askSeeAllFound(int count) {
    return '찾은 기록 $count건 모두 보기';
  }

  @override
  String askFound(int count) {
    return '찾은 기록 $count건';
  }

  @override
  String get askGetAnswer => '답 받기';

  @override
  String askSeeAll(int count) {
    return '모두 보기 ($count건)';
  }

  @override
  String get askOneFile => '이 파일입니다.';

  @override
  String askFiles(int count) {
    return '파일 $count개입니다.';
  }

  @override
  String get askOpen => '열기';

  @override
  String get askStopped => '멈췄습니다';

  @override
  String get askAskAgain => '다시 묻기';

  @override
  String get askTooltipMore => '누르면 전체 발췌와 원문';

  @override
  String askSourceIndex(int index, int total) {
    return '근거 $index / $total';
  }

  @override
  String get askPrevSource => '이전 근거';

  @override
  String get askNextSource => '다음 근거';

  @override
  String get askNoExcerpt => '(발췌 없음)';

  @override
  String get askOpenOriginal => '원문 열기';

  @override
  String get memoryLayerLog => '기록';

  @override
  String get memoryLayerDay => '하루';

  @override
  String get memoryLayerOrigins => '원본';

  @override
  String get memoryLayerProjects => '상태';

  @override
  String get memoryHideFlow => '흐름 설명 숨기기';

  @override
  String get memoryShowFlow => '내 기록이 어떻게 쓰이는지';

  @override
  String get memoryMine => '내가 쓴 줄';

  @override
  String get memoryFlowMineBody =>
      '한 줄 기록·녹음·전사본. 정리 에이전트는 고치지 못하고 검토를 거쳐 제안만 합니다.';

  @override
  String get memoryFlowDigestTitle => '정리가 쓴 줄';

  @override
  String get memoryFlowDigestBody => '수집된 원본에서 에이전트가 뽑은 줄. 출처를 누르면 원본이 열립니다.';

  @override
  String get memoryFlowUseTitle => '쓰임';

  @override
  String get memoryFlowUseBody => '검색·질문·리포트가 이 줄들과 원본을 근거로 씁니다.';

  @override
  String get memoryFlowSameDayTitle => '같은 날';

  @override
  String get memoryFlowSameDayBody => '내가 쓴 줄과 수집된 원본을 날짜 하나의 카드로 모읍니다.';

  @override
  String get memoryFlowLinkedBody => '정리가 원본에서 뽑은 줄은 그 파일과 같은 카드에 붙습니다.';

  @override
  String get memoryFlowOneRecordTitle => '한 기록';

  @override
  String get memoryFlowOneRecordBody => '같은 카드에 있으면 한 로그·한 검색으로 관리되고 있습니다.';

  @override
  String get memoryFlowDailyTitle => '매일 수집';

  @override
  String get memoryFlowDailyBody => 'git·에이전트 세션·셸·전사본·커넥터가 날짜별 파일로 쌓입니다.';

  @override
  String get memoryFlowDigestStepBody =>
      '주간 정리가 이 파일을 읽어 기록 줄과 프로젝트 상태를 씁니다 (검토 뒤 적용).';

  @override
  String get memoryFlowSearchBody => '원본도 그대로 색인되어 검색·질문에 잡힙니다.';

  @override
  String get memoryFlowProjectPagesTitle => '프로젝트 페이지';

  @override
  String get memoryFlowProjectPagesBody =>
      '정리 에이전트가 프로젝트마다 현재 상태·결정·열린 문제를 갱신합니다.';

  @override
  String get memoryFlowLinkTitle => '기록과 연결';

  @override
  String get memoryFlowLinkBody => '기록 줄의 [[프로젝트]] 링크가 이 페이지로 옵니다.';

  @override
  String get memoryOriginsEmpty =>
      '아직 수집된 원본이 없습니다\n연결 탭에서 \"지금 수집\"을 누르거나 매일 수집을 기다리면 날짜별 파일이 여기 쌓입니다.';

  @override
  String memoryOriginsCount(int files, int days) {
    return '$files개 파일 · $days일';
  }

  @override
  String memoryCitedBy(int count) {
    return '기록 $count줄의 근거';
  }

  @override
  String get memoryNotDigested => '아직 정리 안 됨';

  @override
  String get memoryInboxPending => 'inbox (아직 정리 전)';

  @override
  String get memoryProcessed => '정리됨';

  @override
  String get memoryNoteMineFilesLinked =>
      '내 기록과 수집 원본이 같은 날에 있고, 정리가 그 원본에서 줄을 남겼습니다';

  @override
  String get memoryNoteMineFiles => '내 기록과 수집 원본이 같은 날로 묶여 있습니다';

  @override
  String get memoryNoteLinked => '수집한 원본에서 쓴 줄이 그 파일과 같은 하루에 있습니다';

  @override
  String get memoryNoteMineOnly => '내가 쓴 줄만 있습니다. 이 날 수집된 원본은 없습니다';

  @override
  String get memoryNoteFilesOnly => '수집된 원본만 있습니다. 아직 기록 줄로 이어지지 않았습니다';

  @override
  String get memoryNoteFilesDigest => '수집 원본과 정리 줄이 같은 날에 있습니다';

  @override
  String get memoryNoteDigestOnly => '정리 줄만 있습니다';

  @override
  String get memoryDayEmpty =>
      '아직 기록도 수집된 원본도 없습니다\n한 줄 기록이나 연결 탭의 수집이 쌓이면 날짜마다 한 카드로 모입니다.';

  @override
  String memoryDaySummary(int mine, int digest, int files) {
    return '내 기록 $mine줄 · 정리 $digest줄 · 수집 $files개 파일';
  }

  @override
  String memoryDayTogether(int days) {
    return '$days일은 한 줄과 수집이 함께 있습니다';
  }

  @override
  String memoryDayLinked(int days) {
    return '$days일은 원본에서 줄로 이어졌습니다';
  }

  @override
  String get memoryJoined => '함께';

  @override
  String get memoryLinked => '이어짐';

  @override
  String get memoryOneSide => '한쪽';

  @override
  String get memoryCollected => '수집된 원본';

  @override
  String get memoryLinesFromFiles => '이 원본에서 남긴 줄';

  @override
  String get memoryDayDigest => '이 날의 정리';

  @override
  String get memoryProjectStatus => '프로젝트 상태';

  @override
  String get memoryRefresh => '새로고침';

  @override
  String get memoryProjectsHint => '정리 에이전트가 프로젝트마다 갱신하는 현재 상태 · 결정 · 열린 문제';

  @override
  String get memoryProjectsEmpty =>
      '아직 프로젝트 페이지가 없습니다\n정리가 돌면 기록의 [[프로젝트]]마다 페이지를 만듭니다.';

  @override
  String get logEmpty =>
      '아직 로그가 없습니다. log/YYYY-MM.md에 한 줄을 적거나 주간 정리를 기다려 주세요.';

  @override
  String logProposalBanner(int count, int lines) {
    return '정리 제안 $count건이 검토를 기다립니다 — 로그 $lines줄. 고른 줄만 worklog에 들어갑니다.';
  }

  @override
  String get logReview => '검토하기';

  @override
  String get logOnlyMine => '내가 쓴 줄만';

  @override
  String get logNoMatch => '조건에 맞는 로그가 없습니다.';

  @override
  String get logEdited => '줄을 고쳤습니다';

  @override
  String logOriginNotFound(String src) {
    return '원본 파일을 찾지 못했습니다: $src';
  }

  @override
  String get logDeleteTitle => '이 줄을 지울까요?';

  @override
  String get logDeleted => '줄을 지웠습니다';

  @override
  String get logByDigestTip => '정리 에이전트가 원본에서 뽑아 쓴 줄 — 출처를 누르면 원본이 열립니다';

  @override
  String get logMineTip => '내가 쓴 줄 — 정리 에이전트는 이 줄을 고치지 않습니다 (검토를 거쳐 제안만 합니다)';

  @override
  String get logDigest => '정리';

  @override
  String get logMine => '내 기록';

  @override
  String logSource(String source) {
    return '출처 $source';
  }

  @override
  String get logMenu => '줄 메뉴';

  @override
  String get logEdit => '편집';

  @override
  String reviewApplied(int lines, int projects) {
    return '적용했습니다: 로그 $lines줄 · 프로젝트 $projects개';
  }

  @override
  String get reviewDismissTitle => '이 정리 결과를 버릴까요?';

  @override
  String get reviewDismissBody =>
      'worklog에는 아무것도 쓰지 않습니다. 다음 정리에서 같은 원본을 다시 읽습니다.';

  @override
  String get reviewDismiss => '버리기';

  @override
  String get reviewDismissed => '버렸습니다';

  @override
  String get reviewTitle => '정리 결과 검토';

  @override
  String get reviewIntro =>
      '에이전트가 쓰려던 내용입니다. 남길 것만 고르고 적용하세요. 고르지 않은 것은 worklog에 들어가지 않습니다.';

  @override
  String reviewRemoved(int count) {
    return '에이전트가 지우려던 줄 $count개 — 적용해도 지워지지 않습니다';
  }

  @override
  String reviewLogLines(int chosen, int total) {
    return '로그 줄 ($chosen/$total)';
  }

  @override
  String get reviewNoNewLines => '새 줄 없음';

  @override
  String get reviewDeselectAll => '모두 해제';

  @override
  String get reviewSelectAll => '모두 선택';

  @override
  String reviewProjects(int chosen, int total) {
    return '프로젝트 ($chosen/$total)';
  }

  @override
  String get reviewNoProjects => '바뀐 프로젝트 없음';

  @override
  String get reviewNewFile => '새 파일';

  @override
  String get reviewChanged => '변경';

  @override
  String reviewSummaries(int count) {
    return '월간 정리 ($count)';
  }

  @override
  String get reviewNoSummaries => '바뀐 정리 없음';

  @override
  String get reviewApplySummaries => '월간 정리 변경을 적용';

  @override
  String reviewProcessed(int count) {
    return '처리된 inbox 파일 ($count)';
  }

  @override
  String get reviewMoveProcessed => '읽은 inbox 파일을 processed/로 옮김';

  @override
  String reviewMore(int count) {
    return '외 $count';
  }

  @override
  String get reviewProcessedHint => '끄면 다음 정리에서 다시 읽습니다.';

  @override
  String get reviewAgentReport => '에이전트 보고';

  @override
  String reviewSelected(int count) {
    return '선택 $count개';
  }

  @override
  String get reviewApply => '선택한 것 적용';

  @override
  String get reviewStatusApplied => '적용됨';

  @override
  String get reviewStatusDismissed => '버림';

  @override
  String reviewLineCount(int count) {
    return '$count줄';
  }

  @override
  String reviewPrevLineCount(int count) {
    return '(이전 $count줄)';
  }

  @override
  String get reviewProposed => '제안';

  @override
  String get reviewCurrent => '현재';

  @override
  String get searchPeriodAll => '전체';

  @override
  String get searchPeriodWeek => '7일';

  @override
  String get searchPeriodMonth => '30일';

  @override
  String get searchPeriodThisMonth => '이번 달';

  @override
  String searchResultsTitle(String query) {
    return '\"$query\" 검색 결과';
  }

  @override
  String get searchClearFilters => '필터 지우기';

  @override
  String searchCount(int total) {
    return '$total건';
  }

  @override
  String searchCountOf(int shown, int total) {
    return '$shown / $total건';
  }

  @override
  String get searchNoIndex => '아직 색인이 없습니다. 색인을 먼저 만들어 주세요.';

  @override
  String get searchFailed => '검색에 실패했습니다';

  @override
  String get searchOpenIndex => '색인 상태 열기';

  @override
  String fileSpeakerNameTitle(String label) {
    return '[$label] 이름';
  }

  @override
  String get fileSpeakerNameHint => '예: 재박';

  @override
  String fileSpeakerRenamed(String from, String to) {
    return '[$from]을 [$to](으)로 바꿨습니다';
  }

  @override
  String get fileSpeakers => '화자';

  @override
  String get fileNameSpeaker => '이름 붙이기';

  @override
  String get fileSpeakersHint => '누르면 이름을 붙입니다. 이 파일에 바로 반영됩니다.';

  @override
  String get fileSpeakersDone => '화자를 붙였습니다';

  @override
  String get fileRelabelTitle => '화자를 다시 붙일까요?';

  @override
  String get fileLabelTitle => '화자를 붙일까요?';

  @override
  String get fileLabelBody =>
      '남겨 둔 원본 녹음을 다시 인식해 말한 사람마다 [A], [B]로 나눕니다. 녹음 길이만큼 걸리고 그동안 CPU를 씁니다.';

  @override
  String get fileLabelBodyNames => '붙여 둔 이름은 A, B로 돌아갑니다.';

  @override
  String get fileLabelBodyReplace => '이 파일의 본문이 새 글로 바뀝니다.';

  @override
  String get fileLabelConfirm => '붙이기';

  @override
  String get fileLabelQueued => '화자 붙이기 대기 중';

  @override
  String fileLabeling(String line) {
    return '화자 붙이는 중 · $line';
  }

  @override
  String get fileRelabel => '화자 다시 붙이기';

  @override
  String get fileLabel => '화자 붙이기';

  @override
  String get fileNoSpeakers => '말한 사람이 표시되지 않은 전사본입니다.';

  @override
  String fileLastFailed(String error) {
    return '지난번 실패: $error';
  }

  @override
  String get projectsEmpty => 'projects/ 폴더에 프로젝트 파일이 없습니다.';

  @override
  String get indexKiwiInstallTitle => '한국어 형태소 분석 (Kiwi) 설치';

  @override
  String get indexTitle => '검색 색인 (AutoRAG Lite)';

  @override
  String get indexStatus => '상태';

  @override
  String get indexDone => '색인 완료';

  @override
  String get indexFreshness => '최신 여부';

  @override
  String get indexStale => '새 파일이 있음 — 다시 색인 필요';

  @override
  String get indexUpToDate => '최신';

  @override
  String get indexSemantic => '의미 검색';

  @override
  String get indexLastError => '마지막 오류';

  @override
  String indexMoreMessages(int count) {
    return '· 외 $count건';
  }

  @override
  String get indexRefreshing => '색인 중…';

  @override
  String get indexRefresh => '색인 갱신';

  @override
  String get indexRebuild => '처음부터 다시';

  @override
  String get indexKeepsRunning => '창을 닫아도 색인은 계속됩니다.';

  @override
  String get indexFirstSlow => '처음 색인은 임베딩을 만드느라 몇 분 걸릴 수 있습니다.';

  @override
  String get indexStateReady => '준비됨';

  @override
  String get indexStateNever => '아직 색인 안 함';

  @override
  String get indexStateIdle => '대기';

  @override
  String get indexStateNotConfigured => 'AutoRAG 미설정';

  @override
  String get indexStateUnavailable => '연결 실패';

  @override
  String get indexKeywords => '키워드 분석';

  @override
  String get indexInstallKiwi => 'Kiwi 설치';

  @override
  String indexKiwiTerminalHint(String command) {
    return '설치: 터미널에서 $command';
  }

  @override
  String get indexStarting => '색인 시작 중';

  @override
  String get indexStepRead => '본문 읽기';

  @override
  String get indexStepEmbed => '임베딩·색인';

  @override
  String get indexStepFinish => '마무리';

  @override
  String get backendTranslocated =>
      'zaevis를 Applications 폴더로 옮긴 뒤 다시 여세요. (지금은 다운로드한 위치에서 임시로 실행 중이라 매일 수집 예약을 만들 수 없습니다)';

  @override
  String get backendNotInstalled => '앱 설치본이 아닙니다';

  @override
  String backendExitCode(int code) {
    return '종료 코드 $code';
  }

  @override
  String get backendUpdateInstalledOnly => '설치본에서만 업데이트할 수 있습니다.';

  @override
  String get backendUpdateUnsupportedOs => '이 운영체제에서는 자동 업데이트를 지원하지 않습니다.';

  @override
  String get backendWebNoRun => '브라우저에서는 실행할 수 없습니다';

  @override
  String get backendWebNoUpdate => '브라우저에서는 업데이트할 수 없습니다';

  @override
  String get onboardingSourceGit => 'git 커밋';

  @override
  String get onboardingSourceGitHint => '코드 폴더 아래 모든 저장소의 커밋 (작성자별로 표시)';

  @override
  String get onboardingSourceAgents => '에이전트 세션';

  @override
  String get onboardingSourceAgentsHint =>
      'Claude Code · Codex · Gemini CLI 대화: 요청→응답, 수정한 파일, 실행한 명령';

  @override
  String get onboardingSourceShell => '터미널 명령 이력';

  @override
  String get onboardingSourceShellHint =>
      'zsh 히스토리 (비밀값은 가림). 명령을 친 시각까지 남기려면 연결 탭에서 한 번 켭니다';

  @override
  String get onboardingSourceTranscripts => '회의 전사본';

  @override
  String get onboardingSourceTranscriptsHint =>
      '전사 서비스 내보내기 폴더, 앱 안 녹음의 whisperX 전사';

  @override
  String get onboardingNextConnect => '연결 탭에서 소스 확인';

  @override
  String get onboardingNextConnectHint =>
      '각 소스의 수집 결과를 보고, Slack·Obsidian 같은 외부 소스를 더 붙입니다.';

  @override
  String get onboardingNextMemory => '메모리 탭에서 기록';

  @override
  String get onboardingNextMemoryHint =>
      '⌘N(어느 앱에서든 ⌘⇧Space)으로 한 줄씩 남기면 검색·질문의 근거가 됩니다.';

  @override
  String get onboardingNextReports => '리포트 켜기';

  @override
  String get onboardingNextReportsHint =>
      '리포트 탭의 ⚙︎에서 일간·주간을 켜 두면 매일 수집 뒤 에이전트가 정리해 둡니다.';

  @override
  String get onboardingLogKiwi =>
      '한국어 형태소 분석기(Kiwi) 설치 — 첫 색인부터 조사·어미가 붙은 말도 찾습니다 (약 130MB)';

  @override
  String onboardingLogKiwiFailed(String error) {
    return 'Kiwi 설치 실패 — 나중에 설정 → 검색에서 다시 설치할 수 있습니다: $error';
  }

  @override
  String get onboardingLogServer => '서버 시작';

  @override
  String get onboardingLogCollect =>
      '첫 수집 시작 (지난 7일치, 끝나면 검색 색인까지 백그라운드에서 이어집니다)';

  @override
  String get onboardingPick => '선택';

  @override
  String get onboardingReady => '준비됐습니다';

  @override
  String get onboardingTitle => 'zaevis 시작하기';

  @override
  String get onboardingReadyBody =>
      '첫 수집이 돌고 있고, 끝나면 검색 색인까지 이어집니다. 모은 기록은 검색·질문, 메모리, 리포트 탭에서 보고, 연결 탭에서 소스를 관리합니다.';

  @override
  String get onboardingIntro =>
      '작업 기록을 어디에 모을지만 정하면 됩니다. 나머지는 앱이 알아서 설치하고 매일 모읍니다. 모은 기록은 검색하고(검색 탭), 근거를 달아 묻고(질문), 날짜순으로 보고(메모리), 일간·주간·월간으로 정리해(리포트) 봅니다.';

  @override
  String get onboardingNext => '다음에 할 것';

  @override
  String get onboardingOpenApp => '앱 열기';

  @override
  String get onboardingWorklogFolder => '기록을 모을 폴더 (worklog)';

  @override
  String get onboardingReposFolder => '코드 저장소들이 있는 폴더';

  @override
  String get onboardingSources => '모을 데이터소스';

  @override
  String get onboardingSourcesHint =>
      '연결 탭에서 언제든 바꾸거나, 커넥터(아무 명령)와 외부 소스(Slack·Notion·Obsidian…)를 더할 수 있습니다.';

  @override
  String get onboardingLanguage => '주로 쓰는 언어';

  @override
  String get onboardingLanguageHint =>
      '녹음을 이 언어로 전사합니다. 나중에 설정에서 바꾸거나 자동 감지로 둘 수 있습니다.';

  @override
  String onboardingDaily(String time) {
    return '매일 $time에 수집하고 검색 색인 갱신';
  }

  @override
  String get onboardingKiwiHint =>
      '키워드 검색이 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾게 합니다. 약 130MB 다운로드, 나중에 설정에서도 설치할 수 있습니다.';

  @override
  String get onboardingSettingUp => '설정 중…';

  @override
  String get onboardingStart => '시작';

  @override
  String onboardingFailed(String error) {
    return '설정에 실패했습니다: $error';
  }

  @override
  String get collectNeverCollected => '아직 수집 안 함';

  @override
  String get collectJustNow => '방금';

  @override
  String collectMinutesAgo(int count) {
    return '$count분 전';
  }

  @override
  String collectHoursAgo(int count) {
    return '$count시간 전';
  }

  @override
  String collectDaysAgo(int count) {
    return '$count일 전';
  }

  @override
  String get collectTranscriptionCancelled => '전사를 취소했습니다';

  @override
  String get collectTimestampsTitle => '셸 설정에 한 줄 추가';

  @override
  String collectTimestampsBody(String zdotdir, String line) {
    return '~/.zshrc(또는 $zdotdir/.zshrc) 끝에 다음 한 줄을 붙입니다. 이미 켜져 있으면 그대로 둡니다.\n\n$line\n\n새로 여는 터미널부터 명령을 친 시각이 남습니다. 시각이 없는 명령도 수집한 날에 모입니다.';
  }

  @override
  String collectTimestampsAdded(String file) {
    return '$file에 추가했습니다. 새 터미널부터 시각이 남습니다.';
  }

  @override
  String collectTimestampsAlready(String file) {
    return '$file에 이미 켜져 있습니다. 새 터미널부터 시각이 남습니다.';
  }

  @override
  String get collectPaneNow => '지금';

  @override
  String get collectPaneDaily => '매일';

  @override
  String get collectPaneOutside => '바깥';

  @override
  String get collectQuickTitle => '바로 넣기';

  @override
  String get collectQuickHint => '저장하는 즉시 worklog에 들어갑니다. 검색에는 다음 색인 뒤에 잡힙니다.';

  @override
  String get collectAddedToLog => '로그에 추가했습니다';

  @override
  String get collectOneLine => '한 줄 기록';

  @override
  String collectSavedToInbox(String file) {
    return 'inbox에 저장: $file';
  }

  @override
  String get collectPasteTranscript => '전사본 붙여넣기';

  @override
  String get collectRecord => '녹음하기';

  @override
  String collectQueuedRecordings(int count) {
    return '녹음 $count개를 전사 대기열에 넣었습니다';
  }

  @override
  String get collectUploadRecordings => '녹음 올리기 (whisperX)';

  @override
  String get collectSourcesTitle => '데이터소스';

  @override
  String get collectSourcesHint => '매일 자동으로 모읍니다. 켜고 끄거나, 지금 바로 모을 수 있습니다.';

  @override
  String get collectStarted => '수집을 시작했습니다 (끝나면 색인까지)';

  @override
  String get collectCollecting => '수집 중…';

  @override
  String get collectNow => '지금 수집';

  @override
  String collectSourceCollecting(String title) {
    return '$title 수집 중';
  }

  @override
  String collectSourceStarted(String title) {
    return '$title 수집을 시작했습니다';
  }

  @override
  String get collectDeleted => '삭제했습니다';

  @override
  String collectConnectorAdded(String name) {
    return '\"$name\" 커넥터를 추가하고 첫 수집을 시작했습니다. 결과는 카드에 표시됩니다.';
  }

  @override
  String get collectAddConnector => '커넥터 추가';

  @override
  String get collectAnyCommand =>
      'Markdown이나 텍스트를 출력하는 명령이면 무엇이든 데이터소스가 됩니다 — 폴더의 노트, 캘린더, 사내 도구의 내보내기 스크립트.';

  @override
  String get collectExternalTitle => '외부 소스 (AutoRAG)';

  @override
  String get collectExternalHint =>
      'Slack·Notion·Obsidian·GitHub 같은 곳을 AutoRAG가 직접 색인해 검색에 섞습니다. worklog에는 들어가지 않습니다.';

  @override
  String get collectSyncing => '동기화 중…';

  @override
  String collectInstallTask(String title, String bin) {
    return '$title 도구 설치 ($bin)';
  }

  @override
  String collectInstalled(String bin) {
    return '$bin 설치됨. 이제 그 도구에서 로그인·수집을 한 번 한 뒤 연결하세요.';
  }

  @override
  String collectExtOn(String title) {
    return '$title을(를) 켰습니다. 동기화를 시작합니다.';
  }

  @override
  String collectExtOff(String title) {
    return '$title을(를) 껐습니다';
  }

  @override
  String get collectSavedSyncing => '저장했습니다. 동기화를 시작합니다.';

  @override
  String collectExtConnected(String title) {
    return '$title을(를) 연결했습니다. 첫 동기화를 시작합니다.';
  }

  @override
  String get collectExtSyncStarted => '외부 소스 동기화를 시작했습니다';

  @override
  String collectExtRemoved(String title) {
    return '$title 연결을 지웠습니다';
  }

  @override
  String get collectNoExternal => '연결된 외부 소스가 없습니다.';

  @override
  String get collectInboxTitle => 'inbox — 다음 주간 정리에서 로그로 정리됩니다';

  @override
  String get collectTranscribeQueued => '전사 대기';

  @override
  String get collectCancelled => '취소했습니다';

  @override
  String get collectTranscribing => '전사 중…';

  @override
  String get collectTranscripts => '전사본';

  @override
  String get collectPendingAudio => '전사 대기 녹음';

  @override
  String get collectSessionNotes => 'Claude Code 세션 노트';

  @override
  String collectSpanHourMin(int hours, int minutes) {
    return '$hours시간 $minutes분';
  }

  @override
  String collectSpanMinSec(int minutes, int seconds) {
    return '$minutes분 $seconds초';
  }

  @override
  String collectSpanSec(int seconds) {
    return '$seconds초';
  }

  @override
  String get collectStartedChecking => '수집을 시작했습니다. 어느 단계인지 확인하는 중…';

  @override
  String collectNoResponse(String span) {
    return '응답이 없습니다 · 마지막 신호 $span 전';
  }

  @override
  String collectQuiet(String quiet, String total) {
    return '진행 중 · 출력 없이 $quiet · 전체 $total';
  }

  @override
  String collectRunning(String total) {
    return '진행 중 · 전체 $total';
  }

  @override
  String get collectStaleNote => '서버가 이 단계에서 더 이상 신호를 보내지 않습니다.';

  @override
  String get collectQuietNote =>
      '전사는 녹음이 길면 한동안 출력이 없습니다. 시간이 늘어나면 아직 그 단계에 있습니다.';

  @override
  String get collectCancelTranscription => '전사 취소';

  @override
  String get collectTimestampsOn => '시각 기록 켜기';

  @override
  String get collectTimestampsHint => '명령을 친 시각도 남기려면 켭니다. 켜지 않아도 명령은 모입니다.';

  @override
  String get collectOnePerLine => '한 줄에 하나씩';

  @override
  String get collectOnlyThis => '이것만 수집';

  @override
  String get collectEnvNone => '아직 없음';

  @override
  String get collectEnvStored => '저장됨 — 바꾸려면 새 값 입력';

  @override
  String get collectEnvInServer => '서버 환경에 있음';

  @override
  String collectNotInstalled(String bin) {
    return '미설치 — $bin 명령이 없습니다';
  }

  @override
  String get collectNotConnected => '연결 안 됨';

  @override
  String get collectOff => '꺼짐';

  @override
  String get collectSyncFailed => '동기화 실패';

  @override
  String get collectConnected => '연결됨';

  @override
  String collectSyncedAgo(String ago) {
    return '동기화 $ago';
  }

  @override
  String collectChunks(int count) {
    return '조각 $count개';
  }

  @override
  String get collectNeverSynced => '아직 동기화 안 함';

  @override
  String collectOutbound(String what) {
    return '밖으로 나가는 것: $what';
  }

  @override
  String collectAuth(String what) {
    return '로그인·토큰: $what';
  }

  @override
  String collectNeedsTool(String bin) {
    return '$bin 도구가 필요합니다. 설치하면 이 앱 안의 폴더(~/.zaevis/ext)에 들어가고, 관리자 권한은 필요 없습니다.';
  }

  @override
  String collectInstallBin(String bin) {
    return '$bin 설치';
  }

  @override
  String get collectInstallFirst => '먼저 터미널에서 설치하고 로그인·수집을 한 번 해 두세요:';

  @override
  String get collectInstallCopied => '설치 명령을 복사했습니다';

  @override
  String get collectCopyInstall => '설치 명령 복사';

  @override
  String collectNoArchive(String bin) {
    return '$bin의 아카이브가 아직 없습니다. 먼저 $bin으로 로그인·수집을 한 번 하세요.';
  }

  @override
  String get collectEnvHelper => '환경 변수 이름. 값은 아래 칸에';

  @override
  String collectTokenLabel(String name) {
    return '토큰 값 ($name)';
  }

  @override
  String get collectTokenHelper =>
      '~/.zaevis/secrets.json(소유자만 읽기)에 저장되고 검색 프로세스에만 전달됩니다. 다시 표시되지 않습니다.';

  @override
  String get collectNoteLabel => '메모 (선택)';

  @override
  String get collectNoteHelper => '이 연결이 무엇인지. 질문 모드의 에이전트에게도 보입니다.';

  @override
  String get collectConnect => '연결';

  @override
  String get collectSyncNow => '지금 동기화';

  @override
  String get collectRemoveConnection => '연결 삭제';

  @override
  String get collectPresetFolder => '폴더의 노트 (Markdown·텍스트)';

  @override
  String get collectPresetFolderHint =>
      '폴더 안에서 수집 구간에 수정된 .md/.txt 파일을 통째로 가져옵니다. Obsidian 볼트, 메모 폴더에 맞습니다.';

  @override
  String get collectPresetCalendar => 'macOS 캘린더 일정';

  @override
  String get collectPresetCalendarHint => '수집 구간의 캘린더 일정을 제목·시간·참석자와 함께 가져옵니다.';

  @override
  String get collectPresetCustom => '직접 입력';

  @override
  String get collectPresetCustomHint =>
      'Markdown을 출력하는 아무 명령. 스크립트, curl, 사내 CLI…';

  @override
  String get collectStep1 => '1. 무엇을 모을지 고르세요';

  @override
  String collectRequires(String what) {
    return '필요: $what';
  }

  @override
  String get collectStep2 => '2. 확인하고 고치세요';

  @override
  String get collectNameLabel => '이름 (영문 소문자·숫자·-)';

  @override
  String get collectCommandLabel => '명령';

  @override
  String get collectNotesFolderHelper => '~/Notes 를 실제 폴더로 바꾸세요';

  @override
  String get collectDescLabel => '설명 (선택)';

  @override
  String collectPlaceholderHelp(String dates, String times, String marker) {
    return '명령 안의 자리표시자는 수집 때 바뀝니다:\n  $dates  →  2026-10-20  (날짜만)\n  $times  →  2026-10-20T00:00:00.000Z  (ISO 시각)\n출력을 날짜별로 나누려면 줄 사이에 $marker 를 넣으세요. 없으면 수집한 날의 기록이 됩니다.\n추가하면 바로 한 번 수집해 결과를 카드에 보여 줍니다.';
  }

  @override
  String get collectNeedNameCommand => '이름과 명령을 채워 주세요';

  @override
  String get collectAddAndCollect => '추가하고 수집';

  @override
  String get settingsSectionGeneral => '일반';

  @override
  String get settingsSectionRecording => '녹음';

  @override
  String get settingsSectionDigest => '정리';

  @override
  String get settingsSectionCollect => '수집';

  @override
  String get settingsSectionShortcuts => '단축키';

  @override
  String get settingsSectionAdvanced => '고급';

  @override
  String get settingsKiwiInstallTask => '한국어 형태소 분석 (Kiwi) 설치';

  @override
  String get settingsKiwiReindexTitle => '처음부터 다시 색인할까요?';

  @override
  String get settingsKiwiReindexBody =>
      'Kiwi를 설치했습니다. 지금 있는 색인은 공백 기준으로 만든 것이라, 처음부터 다시 색인해야 조사·어미가 붙은 말도 찾습니다. 몇 분 걸리고, 창을 닫아도 계속됩니다.';

  @override
  String get settingsLater => '나중에';

  @override
  String get settingsReindex => '다시 색인';

  @override
  String get settingsReindexStarted => '처음부터 다시 색인을 시작했습니다';

  @override
  String get settingsMemoryAdded => '폴더를 색인에 넣었습니다. 처음부터 다시 색인합니다.';

  @override
  String get settingsMemoryDialogTitle => '색인할 폴더';

  @override
  String get settingsMemoryPathLabel => '폴더 경로';

  @override
  String get settingsAbout => '앱 정보';

  @override
  String get settingsDisplay => '화면';

  @override
  String get settingsTheme => '테마';

  @override
  String get settingsThemeHint => '시스템을 고르면 macOS·Windows의 밝게/어둡게 설정을 따릅니다.';

  @override
  String get settingsThemeLight => '밝게';

  @override
  String get settingsThemeDark => '어둡게';

  @override
  String get settingsTextScale => '글자 크기';

  @override
  String settingsTextScaleHint(int percent) {
    return '앱 전체 글자를 $percent%로 보여 줍니다.';
  }

  @override
  String get settingsGroupLanguage => '언어';

  @override
  String get settingsUserLanguage => '주로 쓰는 언어';

  @override
  String get settingsUserLanguageHint =>
      '처음 시작할 때 고른 언어입니다. 녹음 전사가 기본으로 이 언어를 씁니다.';

  @override
  String get settingsTranscribeLanguage => '전사 언어';

  @override
  String settingsTranscribeUser(String language) {
    return '주로 쓰는 언어($language)로 전사합니다. 일반에서 바꾸면 따라갑니다.';
  }

  @override
  String get settingsTranscribeAuto =>
      '녹음 앞부분으로 언어를 알아냅니다. 여러 언어 녹음에 맞지만, 다른 언어 낱말이 많이 섞이면 잘못 고를 수 있습니다.';

  @override
  String settingsTranscribeFixed(String language) {
    return '항상 $language로 전사합니다.';
  }

  @override
  String settingsTranscribeMine(String language) {
    return '내 언어 ($language)';
  }

  @override
  String get settingsAutoDetect => '자동 감지';

  @override
  String get settingsNotifications => '알림';

  @override
  String get settingsSystemNotifications => '시스템 알림';

  @override
  String get settingsSystemNotificationsHint =>
      '정리가 끝나 검토할 것이 생겼을 때, 수집이 실패했을 때, 녹음 전사가 끝났을 때 알립니다. 서버가 보내므로 앱 창이 닫혀 있어도 옵니다.';

  @override
  String get settingsVersion => '버전';

  @override
  String get settingsNotInstalledBuild => '설치본이 아닙니다 (개발 실행이나 웹)';

  @override
  String get settingsNoVersionInfo => '버전 정보 없음';

  @override
  String settingsBuiltOn(String date) {
    return '$date 빌드';
  }

  @override
  String get settingsInstalledOn => '설치한 날';

  @override
  String get settingsInstalledOnHint => '이 버전을 이 컴퓨터에서 처음 연 때';

  @override
  String get settingsTranscription => '전사';

  @override
  String get settingsWhisperx => 'whisperX (녹음 전사)';

  @override
  String get settingsInstalled => '설치됨';

  @override
  String get settingsWhisperxInstallHint =>
      '설치하면 녹음을 올릴 때 자동으로 전사합니다 (1~2GB 다운로드)';

  @override
  String get settingsWhisperxMissing =>
      '설치되지 않음 — 터미널에서 \'zaevis ext install whisperx\'';

  @override
  String get settingsWhisperxInstallTask => 'whisperX 설치';

  @override
  String get settingsInstall => '설치';

  @override
  String get settingsFastTranscribe => '빠르게 전사';

  @override
  String get settingsFastTranscribeHint =>
      '끄면 CPU 4코어만 써서 팬 소리가 작습니다. 켜면 모든 코어를 써서 약 1.4배 빠르지만 팬이 세게 돕니다.';

  @override
  String get settingsSpeakers => '화자';

  @override
  String get settingsIndex => '색인';

  @override
  String get settingsIndexOnInject => '넣자마자 색인';

  @override
  String get settingsIndexOnInjectHint =>
      '한 줄 기록이나 전사본을 넣으면 바로 검색 색인을 갱신합니다. 끄면 예약·수동 색인 때만 반영됩니다.';

  @override
  String get settingsLocalEmbedding => '의미 검색 (로컬 임베딩)';

  @override
  String get settingsLocalEmbeddingHint =>
      '이 맥에서 Qwen3-Embedding 모델을 돌려 뜻이 비슷한 기록도 찾습니다. 외부 서비스나 키는 쓰지 않습니다. 처음 켤 때 모델(1.1GB)을 내려받고 색인을 다시 만듭니다. 끄면 키워드 검색만 합니다.';

  @override
  String get settingsMemoryFolders => '색인 폴더';

  @override
  String get settingsMemoryFoldersHint =>
      '기록 폴더는 항상 색인됩니다. 노트가 다른 폴더에 있으면 추가하세요. 추가하거나 빼면 처음부터 다시 색인합니다.';

  @override
  String get settingsWorklogFolder => '기록 폴더';

  @override
  String get settingsRemove => '빼기';

  @override
  String get settingsAddFolder => '폴더 추가';

  @override
  String get settingsExternal => '외부 서비스';

  @override
  String get settingsScheduleUnsupported => '이 OS에서는 자동 예약을 지원하지 않습니다.';

  @override
  String get settingsScheduleNone => '예약 없음 — 시각을 저장하면 등록됩니다.';

  @override
  String settingsScheduleRunning(String time) {
    return '매일 $time 실행 중 (맥이 잠자기였으면 깨어날 때 실행)';
  }

  @override
  String get settingsScheduleNotLoaded => '등록됐지만 아직 로드되지 않음';

  @override
  String get settingsDaily => '매일 수집';

  @override
  String settingsDailyAt(String time) {
    return '실행 시각 $time';
  }

  @override
  String get settingsLastRun => '마지막 실행';

  @override
  String get settingsDefault => '기본값';

  @override
  String get settingsServer => '서버';

  @override
  String get settingsServerHint => '앱이 이야기하는 zaevis 서버입니다. 보통은 바꿀 일이 없습니다.';

  @override
  String get settingsServerAddress => '서버 주소';

  @override
  String get settingsApply => '적용';

  @override
  String get settingsThisComputer => '이 컴퓨터';

  @override
  String get settingsOpenInBrowser => '브라우저로 열기';

  @override
  String get settingsInstallCli => '터미널에서 zaevis 명령 쓰기';

  @override
  String get settingsInstallCliHint => '~/.local/bin 에 zaevis 명령을 등록합니다';

  @override
  String get settingsInstallCliTask => 'zaevis 명령 등록';

  @override
  String get settingsRestartServer => '서버 다시 시작';

  @override
  String get settingsOpenLogs => '로그 폴더 열기';

  @override
  String settingsDate(int year, int month, int day) {
    return '$year년 $month월 $day일';
  }

  @override
  String settingsUpdateDownloading(int percent) {
    return '받는 중 $percent%';
  }

  @override
  String get settingsUpdateInstalling => '설치하고 다시 여는 중…';

  @override
  String get settingsUpdateChecking => '새 버전을 확인하는 중…';

  @override
  String settingsUpdateAvailable(String version) {
    return '새 버전이 있습니다: $version';
  }

  @override
  String settingsUpdateAvailableBuilt(String version, String date) {
    return '새 버전이 있습니다: $version ($date 빌드)';
  }

  @override
  String get settingsUpdate => '업데이트';

  @override
  String get settingsUpdateNoAsset => '이 기종용 설치 파일이 없습니다';

  @override
  String settingsUpdateCheckFailed(String error) {
    return '확인하지 못했습니다: $error';
  }

  @override
  String get settingsCheckAgain => '다시 확인';

  @override
  String get settingsUpdateNotChecked => '아직 확인하지 않았습니다';

  @override
  String settingsUpToDate(String time) {
    return '최신 버전입니다 · $time 확인';
  }

  @override
  String get settingsCheckUpdate => '업데이트 확인';

  @override
  String settingsKiwiNoRelease(String path) {
    return '이 플랫폼용 Kiwi 릴리스가 없습니다. 직접 받아 $path에 두거나 KIWI_LIBRARY_PATH·KIWI_MODEL_PATH를 설정하세요.';
  }

  @override
  String settingsKiwiInstallHint(int mb) {
    return '설치하면 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾습니다. 키워드 검색이 한국어 형태소 단위가 됩니다 (${mb}MB 다운로드, 설치 뒤 처음부터 다시 색인).';
  }

  @override
  String get settingsKiwiMissing =>
      '설치되지 않음 — 터미널에서 \'zaevis ext install kiwi\' 뒤 처음부터 다시 색인';

  @override
  String get settingsKiwiTitle => '한국어 형태소 분석 (Kiwi)';

  @override
  String get settingsRerankTitle => '검색 결과 재정렬 (OpenRouter)';

  @override
  String settingsRerankOn(String model) {
    return '검색 상위 25개 문단을 OpenRouter의 $model 모델로 다시 정렬합니다. 켜면 검색어와 그 문단이 외부로 나갑니다.';
  }

  @override
  String get settingsRerankNoKey =>
      '켜려면 아래에 OpenRouter API 키를 저장하세요. 키가 없으면 켜도 아무것도 전송되지 않습니다.';

  @override
  String get settingsRerankEnabled => '재정렬을 켰습니다';

  @override
  String get settingsRerankNoKeySent => '켰지만 키가 없어 전송되지 않습니다';

  @override
  String get settingsRerankDisabled => '재정렬을 껐습니다';

  @override
  String get settingsRerankKey => 'OpenRouter API 키';

  @override
  String settingsRerankKeySaved(String hint) {
    return '저장됨 •••• $hint';
  }

  @override
  String get settingsRerankKeyHelper =>
      '새 키를 넣고 저장하면 바뀝니다. 키는 ~/.zaevis/secrets.json(소유자만 읽기)에만 저장됩니다.';

  @override
  String get settingsKeySaved => '키를 저장했습니다';

  @override
  String get settingsTestConnection => '연결 확인';

  @override
  String get settingsKeyCleared => '키를 지웠습니다';

  @override
  String get settingsDeleteKey => '키 삭제';

  @override
  String settingsRerankExternal(String requests) {
    return '지금 외부로 나가는 요청: $requests';
  }

  @override
  String get settingsDigestStarted =>
      '정리를 시작했습니다. 지금까지의 기록을 먼저 수집한 뒤 로그로 정리합니다(몇 분).';

  @override
  String get settingsAgentAuto => '자동 (할당량이면 다음 서비스)';

  @override
  String settingsQuotaSkipped(String names) {
    return '$names 할당량으로 건너뜀';
  }

  @override
  String get settingsAgentOrder => '에이전트 순서';

  @override
  String get settingsAgentOrderHint =>
      'inbox의 전사본·세션 노트와 매일 수집한 원본을 읽어 로그 줄·프로젝트 상태·월간 정리를 씁니다. 블록을 왼쪽부터 시도하고, 할당량으로 막히면 다음 블록으로 넘깁니다. 끌어다 놓아 순서를 바꿉니다.';

  @override
  String get settingsOpenRouterModel => 'OpenRouter 모델';

  @override
  String get settingsRun => '실행';

  @override
  String get settingsReviewFirst => '프로젝트 갱신은 검토 후 적용';

  @override
  String get settingsReviewOn =>
      '로그 줄은 바로 들어가고, 프로젝트 페이지와 월간 정리는 제안으로 남아 검토한 뒤 적용합니다.';

  @override
  String get settingsReviewOff => '끄면 프로젝트 페이지와 월간 정리도 바로 worklog에 들어갑니다.';

  @override
  String get settingsWeekly => '매주 월요일 주간 정리 (프로젝트 갱신)';

  @override
  String settingsWeeklyNext(String next) {
    return '다음 실행: $next (매일 수집 뒤에 이어서)';
  }

  @override
  String get settingsNextMonday => '다음 월요일';

  @override
  String get settingsWeeklyOff => '끄면 프로젝트 갱신은 아래 \'주간 정리\' 버튼으로만 합니다';

  @override
  String settingsDigestRunning(String agent) {
    return '정리 중… ($agent)';
  }

  @override
  String get settingsDigestNow => '지금 정리하기';

  @override
  String get settingsNoAgent =>
      '쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI를 설치하거나 검색 → 외부 서비스에서 OpenRouter 키를 저장하세요.';

  @override
  String settingsDigestBy(String agent) {
    return '지금까지의 기록을 수집해 로그 줄로 옮깁니다 · $agent';
  }

  @override
  String settingsPendingReviews(int count) {
    return '검토 대기 $count건';
  }

  @override
  String settingsProposalCounts(
      int lines, int projects, int summaries, int processed) {
    return '로그 $lines줄 · 프로젝트 $projects개 · 월간 정리 $summaries개 · inbox $processed개';
  }

  @override
  String get settingsReview => '검토하기';

  @override
  String get settingsLastDigest => '마지막 정리';

  @override
  String get settingsStatusPendingReview => '검토 대기';

  @override
  String get settingsInUse => '사용';

  @override
  String get settingsIncluded => '순서에 포함';

  @override
  String get settingsSkipped => '건너뜀';

  @override
  String get settingsHotkeyTitle => '전역 단축키 바꾸기';

  @override
  String get settingsHotkeyHint =>
      '쓰고 싶은 조합을 지금 누르세요. 수정키(⌘·⌃·⌥·⇧ 또는 Ctrl·Alt·Shift)와 글자·숫자·F키·Space를 조합합니다.';

  @override
  String get settingsHotkeyNeedsModifier => '수정키와 함께 눌러야 합니다';

  @override
  String get settingsHotkeyPress => '여기에서 키를 누르세요';

  @override
  String settingsHotkeyDefault(String key) {
    return '기본값: $key';
  }

  @override
  String get settingsSpeakersAfter =>
      '글이 먼저 저장되고, 말한 사람은 그 뒤에 같은 파일에 [A], [B]처럼 붙습니다. 원문 화면에서 이름을 바꿀 수 있습니다.';

  @override
  String get settingsSpeakersNeedWhisperx =>
      'whisperX를 설치하면 쓸 수 있습니다. 계정은 필요 없습니다.';

  @override
  String get settingsSpeakersOff => '꺼져 있습니다. 녹음 글만 저장합니다.';

  @override
  String settingsSpeakersHf(String after) {
    return 'Hugging Face pyannote 모델로 구분합니다. $after';
  }

  @override
  String settingsSpeakersReady(String after) {
    return '계정 없이 이 맥에서 구분합니다. $after';
  }

  @override
  String settingsSpeakersInstalling(int mb) {
    return '화자 모델을 준비하는 중… (약 ${mb}MB)';
  }

  @override
  String settingsSpeakersFailed(String error) {
    return '화자 모델을 준비하지 못했습니다: $error';
  }

  @override
  String get settingsUnknownError => '알 수 없는 오류';

  @override
  String settingsSpeakersIdle(int mb) {
    return '계정 없이 이 맥에서 구분합니다. 첫 녹음 때 화자 모델(약 ${mb}MB)과 한국어 정렬 모델(약 1.2GB)을 한 번 받습니다.';
  }

  @override
  String get settingsSpeakerLabel => '화자 구분';

  @override
  String get settingsPrepareAgain => '다시 준비';

  @override
  String get settingsHfChecking => '로그인 상태를 확인하는 중…';

  @override
  String settingsHfCode(String code) {
    return '브라우저에서 Hugging Face에 로그인하고 코드 $code 를 확인하세요.';
  }

  @override
  String get settingsHfAccount => '계정';

  @override
  String settingsHfNeedsAccept(String user) {
    return '$user 으로 연결됨. 화자 모델을 쓰려면 페이지에서 사용에 동의해야 합니다.';
  }

  @override
  String settingsHfConnected(String user) {
    return '$user 으로 연결됨. 녹음 글은 먼저 저장되고, 말한 사람은 그 뒤에 같은 파일에 붙습니다.';
  }

  @override
  String get settingsHfHint =>
      '로그인하지 않아도 화자 구분은 됩니다. 로그인하고 모델 사용에 동의하면 pyannote 원본으로 구분합니다. 구분은 글이 저장된 뒤에 이어집니다.';

  @override
  String get settingsHfTitle => 'Hugging Face 모델로 구분 (선택)';

  @override
  String get settingsHfAcceptPage => '동의 페이지';

  @override
  String get settingsDisconnect => '연결 해제';

  @override
  String get settingsLogin => '로그인';

  @override
  String get railTitle => '서비스 순서';

  @override
  String railRunning(String title) {
    return '$title · 작성 중';
  }

  @override
  String railWrote(String title) {
    return '$title · 작성';
  }

  @override
  String railQuota(String title) {
    return '$title · 할당량';
  }

  @override
  String railError(String title) {
    return '$title · 실패';
  }

  @override
  String railLogin(String title) {
    return '$title · 로그인';
  }

  @override
  String railMetered(String title) {
    return '$title · 사용량';
  }

  @override
  String get uiServerOffline => 'server 폴더에서 `npm start`로 서버를 실행했는지 확인하세요.';

  @override
  String get uiTagDecision => '결정';

  @override
  String get uiTagBlocked => '막힘';

  @override
  String get uiTagLearned => '배움';

  @override
  String uiTaskFailed(String error) {
    return '실패: $error';
  }

  @override
  String get uiDownloading => '받는 중';

  @override
  String uiTaskClose(String status) {
    return '$status · 닫기';
  }

  @override
  String get uiWeakMatch => '약한 일치';

  @override
  String get uiDownloadFile => '파일 내려받기';

  @override
  String uiSavedTo(String path) {
    return '저장했습니다: $path';
  }

  @override
  String uiSaveFailed(String error) {
    return '저장하지 못했습니다: $error';
  }

  @override
  String get homeStarting => 'zaevis 준비 중…';

  @override
  String homeStartFailed(String error) {
    return '서버를 시작하지 못했습니다.\n$error';
  }

  @override
  String homeServerLog(String path) {
    return '로그: $path';
  }

  @override
  String get homeTabSearch => '검색';

  @override
  String get homeTabSearchHint => '기록을 찾고, 묻고, 파일을 내려받습니다';

  @override
  String get homeTabMemory => '메모리';

  @override
  String get homeTabMemoryHint => '기록 · 하루 · 프로젝트 상태 · 수집된 원본 — 이 앱이 아는 것 전부';

  @override
  String get homeTabReports => '리포트';

  @override
  String get homeTabReportsHint => '일간 · 주간 · 월간 리포트';

  @override
  String get homeTabConnect => '연결';

  @override
  String get homeTabConnectHint => '데이터소스와 외부 서비스 연결, inbox, 바로 넣기';

  @override
  String get homeLogAdded => '로그에 추가했습니다';

  @override
  String get homeMenuSettings => '설정…';

  @override
  String get homeMenuLog => '기록';

  @override
  String get homeNewLog => '한 줄 기록';

  @override
  String get homeRecord => '녹음';

  @override
  String get homeMenuView => '보기';

  @override
  String get homeSearchIndex => '검색 색인';

  @override
  String get homeTagline => '작업 기록 · 지식';

  @override
  String get homeIndex => '색인';

  @override
  String get shortcutSearch => '검색으로 이동해 입력';

  @override
  String get shortcutNewLog => '한 줄 기록';

  @override
  String get shortcutRecord => '녹음';

  @override
  String get shortcutTabs => '검색 · 메모리 · 리포트 · 연결 탭';

  @override
  String get shortcutSettings => '설정';

  @override
  String get shortcutGlobal => '어디서든 창을 띄우고 한 줄 기록 (전역)';

  @override
  String apiCannotConnect(String url) {
    return '서버에 연결할 수 없습니다: $url';
  }

  @override
  String get apiNotFound => '찾을 수 없습니다';

  @override
  String get apiRequestFailed => '요청이 실패했습니다';

  @override
  String get apiBadResponse => '응답 형식이 올바르지 않습니다';

  @override
  String apiUploadFailed(String url) {
    return '업로드에 실패했습니다: $url';
  }

  @override
  String get apiSaveFileTitle => '파일 저장';

  @override
  String get apiSaveUnsupported => '이 환경에서는 파일을 저장할 수 없습니다';

  @override
  String get updateAppNotInImage => '이미지 안에서 zaevis.app을 찾지 못했습니다.';

  @override
  String get updateReplaceFailed => '앱을 교체하지 못했습니다.';

  @override
  String get updateQuarantineFailed => '격리 표시를 지우지 못했습니다. 터미널에서 실행하세요.';

  @override
  String get updateMountFailed => '디스크 이미지를 열지 못했습니다.';

  @override
  String updateDownloadFailed(int status) {
    return '설치 파일을 받지 못했습니다 ($status)';
  }

  @override
  String updateGithubStatus(int status) {
    return 'GitHub 응답 $status';
  }

  @override
  String get updateBadRelease => '릴리스 정보를 읽지 못했습니다';

  @override
  String get updateAvailable => '새 버전이 있습니다';

  @override
  String get updateButton => '업데이트';

  @override
  String updateDownloadingPercent(int percent) {
    return '받는 중 $percent%';
  }

  @override
  String get updateDownloading => '받는 중';

  @override
  String get updateInstalling => '설치하고 다시 여는 중…';

  @override
  String get updateNoInstaller => '이 기종용 설치 파일이 없습니다';

  @override
  String get updateLater => '나중에';

  @override
  String get updateNotice => '알림';

  @override
  String get updateFolderTitle => '매일 18:30에 폴더 접근을 묻습니다';

  @override
  String get updateFolderBody =>
      '데스크탑, 문서, 다운로드, 사진, 음악, 보관함을 저장소 탐색이 하나씩 열고 있습니다. 커밋을 모으는 데는 필요 없습니다.';

  @override
  String get updateFolderApply => '한 번에 빼기';

  @override
  String get modelSourceGit => 'git 커밋';

  @override
  String get modelSourceAgentSessions => '에이전트 세션';

  @override
  String get modelSourceClaudeCode => 'Claude Code 세션';

  @override
  String get modelSourceShell => '셸 명령';

  @override
  String get modelSourceTranscripts => '전사본';

  @override
  String get modelSourceSessionNotes => '세션 노트';

  @override
  String get modelTokenizerMorphemes =>
      '형태소 분석 (Kiwi) — 인증서를 → 인증서처럼 조사·어미가 붙은 말도 찾습니다';

  @override
  String get modelTokenizerNeedsReindex =>
      'Kiwi 설치됨 — 처음부터 다시 색인하면 형태소 분석이 켜집니다';

  @override
  String get modelTokenizerNextIndex => '아직 색인 전 — 다음 색인부터 형태소 분석';

  @override
  String get modelTokenizerSimple =>
      '공백 기준 — 조사·어미가 붙은 말(인증서를)은 검색어(인증서)와 맞지 않습니다';

  @override
  String modelEmbeddingReady(String model, String device) {
    return '켜짐 — $model ($device)';
  }

  @override
  String get modelEmbeddingLocalModel => '로컬 모델';

  @override
  String get modelEmbeddingStarting => '시작 중… 처음에는 모델(1.1GB)을 내려받습니다';

  @override
  String modelEmbeddingFailed(String error) {
    return '실패: $error';
  }

  @override
  String get modelEmbeddingOff => '꺼짐 — 키워드 검색만';

  @override
  String get modelEmbeddingUnavailable => '사용 불가 (minsync 없음)';

  @override
  String modelLoginNeeded(String hint) {
    return '로그인 필요: $hint';
  }

  @override
  String get modelLoginInTerminal => '터미널에서 로그인';

  @override
  String modelProgressFiles(int scanned, int total) {
    return '$scanned/$total 파일';
  }

  @override
  String modelProgressChunks(int count) {
    return '$count개';
  }

  @override
  String get modelProgressParsed => '본문 읽는 중';

  @override
  String get modelProgressEmbedding => '임베딩·색인 중';

  @override
  String get modelProgressDatasources => '커넥터 색인 중';

  @override
  String get modelProgressKeywords => '키워드 색인 정리 중';

  @override
  String get modelProgressFileNames => '파일 이름 색인 중';

  @override
  String get modelProgressFinalizing => '마무리 중';

  @override
  String get modelProgressPreparing => '준비 중';

  @override
  String get modelKindDaily => '일간';

  @override
  String get modelKindWeekly => '주간';

  @override
  String get modelKindMonthly => '월간';

  @override
  String get modelKindDailyWord => '일간';

  @override
  String get modelKindWeeklyWord => '주간';

  @override
  String get modelKindMonthlyWord => '월간';

  @override
  String get modelWeekdayMon => '월';

  @override
  String get modelWeekdayTue => '화';

  @override
  String get modelWeekdayWed => '수';

  @override
  String get modelWeekdayThu => '목';

  @override
  String get modelWeekdayFri => '금';

  @override
  String get modelWeekdaySat => '토';

  @override
  String get modelWeekdaySun => '일';

  @override
  String get modelToday => '오늘';

  @override
  String get modelYesterday => '어제';

  @override
  String get modelThisWeek => '이번 주';

  @override
  String get modelLastWeek => '지난주';

  @override
  String get modelThisMonth => '이번 달';

  @override
  String get modelLastMonth => '지난달';

  @override
  String get reportsNone => '리포트가 없습니다';

  @override
  String get reportsSettings => '리포트 설정';

  @override
  String reportsEmpty(String kind) {
    return '아직 $kind 리포트가 없습니다.\n\"지금 만들기\"로 바로 만들거나, 설정(⚙︎)에서 요일을 켜 두면 매일 수집 뒤 자동으로 만듭니다.';
  }

  @override
  String reportsPeriodNoService(String period) {
    return '$period · 서비스 없음';
  }

  @override
  String get reportsMakeNow => '지금 만들기';

  @override
  String get reportsNoServiceWas => '사용 가능한 서비스가 없었습니다';

  @override
  String get reportsFailed => '리포트를 만들지 못했습니다';

  @override
  String get reportsRemake => '다시 만들기';

  @override
  String reportsWrittenBy(String agent, String detail) {
    return '리포트는 $agent가 씁니다 · $detail';
  }

  @override
  String get reportsNoAgent =>
      '쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.';

  @override
  String reportsRunning(String kind, String period, String agent) {
    return '$kind 리포트 $period 만드는 중… $agent 수십 초에서 몇 분 걸립니다.';
  }

  @override
  String get reportsNoService => '사용 가능한 서비스 없음';

  @override
  String get reportsDigest => '정리';

  @override
  String get reportsDaily => '일간 리포트';

  @override
  String get reportsDailyHint => '고른 요일의 하루를 그날 수집 뒤에 정리합니다 (아침에 돌면 전날).';

  @override
  String get reportsWeekdays => '주중';

  @override
  String get reportsWeekend => '주말';

  @override
  String get reportsEveryday => '매일';

  @override
  String get reportsWeekly => '주간 리포트';

  @override
  String get reportsWeeklyHint => '고른 요일에 그 전날이 든 주(월~일)를 정리합니다. 월요일이면 지난주.';

  @override
  String reportsWeekdayName(String day) {
    return '$day요일';
  }

  @override
  String get reportsMonthly => '월간 리포트';

  @override
  String get reportsMonthlyHint =>
      '매달 고른 날에 지난달을 정리합니다 (summaries/YYYY-MM.md, 월간 정리 자리).';

  @override
  String reportsMonthDay(int day) {
    return '$day일';
  }

  @override
  String get recordPreparing => '전사 준비 중';

  @override
  String get recordTranscribing => '전사 중…';

  @override
  String get recordMicDenied =>
      '마이크 접근이 허용되지 않았습니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 zaevis를 켜 주세요.';

  @override
  String recordError(String error) {
    return '녹음 오류: $error';
  }

  @override
  String recordStartFailed(String error) {
    return '녹음을 시작하지 못했습니다: $error';
  }

  @override
  String get recordTranscribeFailed => '전사 실패';

  @override
  String get recordTranscribeFailedLong => '전사에 실패했습니다';

  @override
  String get recordQueued => '전사 대기';

  @override
  String get recordCancelling => '취소하는 중';

  @override
  String get recordTitle => '녹음';

  @override
  String get recordUploading => '올리는 중…';

  @override
  String get recordTapToStart => '눌러서 녹음 시작';

  @override
  String get recordHintRecording =>
      '중지하면 inbox에 올라가고, whisperX가 설치돼 있으면 바로 전사합니다.';

  @override
  String get recordHintTranscribing => '오른쪽 위를 누르면 전사는 이어집니다. 녹음은 inbox에 남습니다.';

  @override
  String get recordHintIdle =>
      '16kHz 모노 WAV로 저장합니다. 1분에 약 2MB. 첫 녹음 때 마이크 권한을 묻습니다.';

  @override
  String get recordCancelTranscription => '전사 취소';

  @override
  String get recordStopUpload => '중지하고 올리기';

  @override
  String get recordStart => '녹음 시작';

  @override
  String recordQueuedToast(String file) {
    return '녹음을 전사 대기열에 넣었습니다: $file';
  }

  @override
  String get trailRecognizing => '인식 중';

  @override
  String trailRecognizingDetail(String detail) {
    return '인식 중 · $detail';
  }

  @override
  String get trailSpeakersQueued => '대기 · 곧 화자를 붙입니다';

  @override
  String trailSpeakersRunning(String detail) {
    return '화자 붙이는 중 · $detail';
  }

  @override
  String get trailQueued => '대기 · 곧 전사를 시작합니다';

  @override
  String get trailTranscribing => '전사 중';

  @override
  String trailFailed(String error) {
    return '전사 실패 · $error';
  }

  @override
  String get trailCanRetry => '다시 시도할 수 있습니다';

  @override
  String get trailNextCollect => '대기 · 다음 수집에서 전사됩니다';

  @override
  String get trailLinked => '출처 연결 · 정리에 반영된 전사입니다.';

  @override
  String get trailIndexing => '색인 중 · 끝나면 검색됩니다';

  @override
  String get trailWaitingDigest => '검색 가능 · 정리 대기. 주간 정리 뒤에 메모리 출처가 됩니다';

  @override
  String get trailSaved => '글 저장 · 다음 색인에 들어갑니다';

  @override
  String trailFilteredOut(int total) {
    return '전체 $total건 중 이 기간·출처에는 없습니다.';
  }

  @override
  String get trailSearchIndexing => '색인 중입니다. 끝나면 다시 찾습니다.';

  @override
  String trailMore(int count) {
    return '외 $count개';
  }

  @override
  String trailPendingTranscripts(int count) {
    return '전사 $count개가 방금 저장됐습니다. 색인이 끝나면 검색됩니다.';
  }

  @override
  String trailNoResultsLatin(String query) {
    return '\"$query\"에 대한 결과가 없습니다. 기록은 한글로 남아 있는 경우가 많습니다. 한글로 물어보세요.';
  }

  @override
  String trailNoResults(String query) {
    return '\"$query\"에 대한 결과가 없습니다.';
  }

  @override
  String get inputEditLine => '줄 편집';

  @override
  String get inputNewLog => '한 줄 기록';

  @override
  String get inputLogHint => '무엇을 했고, 왜 그렇게 했는지';

  @override
  String get inputDate => '날짜';

  @override
  String inputDigestLine(String source) {
    return '정리가 쓴 줄입니다. 출처($source)는 그대로 남습니다.';
  }

  @override
  String get inputProject => '프로젝트 (선택)';

  @override
  String get inputPasteTranscript => '전사본 붙여넣기';

  @override
  String get inputTitle => '제목';

  @override
  String get inputTitleHint => '주간 정리 회의';

  @override
  String get inputPasteHint => '전사 서비스에서 복사한 내용을 붙여넣으세요';

  @override
  String get voiceStart => '말로 하기';

  @override
  String get voiceStop => '말 끝내기';

  @override
  String voiceListening(String elapsed) {
    return '듣는 중 $elapsed · 다시 누르면 보냅니다';
  }

  @override
  String get voiceConverting => '말을 글자로 바꾸는 중…';

  @override
  String get voiceNothing => '알아들은 말이 없습니다. 다시 말해 주세요.';

  @override
  String voiceFailed(String error) {
    return '음성을 글자로 바꾸지 못했습니다: $error';
  }

  @override
  String apiVoiceFailed(String url) {
    return '음성을 보내지 못했습니다: $url';
  }

  @override
  String get knTitle => '지식화 현황';

  @override
  String get knStepCollect => '수집';

  @override
  String get knStepWaiting => '정리 대기';

  @override
  String get knStepReview => '검토';

  @override
  String get knStepKnowledge => '지식';

  @override
  String get knStepReports => '리포트';

  @override
  String get knNone => '없음';

  @override
  String knCollectValue(int count) {
    return '날짜 파일 $count개';
  }

  @override
  String knLatest(String day) {
    return '최근 $day';
  }

  @override
  String knWaitingValue(int days) {
    return '원본 $days일 치';
  }

  @override
  String knWaitingFiles(int files) {
    return '전사본·세션 $files개';
  }

  @override
  String knLastDigest(String day) {
    return '마지막 정리 $day';
  }

  @override
  String get knNeverDigested => '아직 정리 안 함';

  @override
  String knReviewValue(int lines, int projects) {
    return '로그 $lines줄 · 프로젝트 $projects개';
  }

  @override
  String get knReviewNone => '기다리는 제안 없음';

  @override
  String knKnowledgeValue(int lines) {
    return '로그 $lines줄';
  }

  @override
  String knKnowledgeSub(int projects, int summaries) {
    return '프로젝트 $projects · 월간 정리 $summaries';
  }

  @override
  String knReportsValue(int m, int w, int d) {
    return '월간 $m · 주간 $w · 일간 $d';
  }

  @override
  String knReportsOn(String kinds) {
    return '자동: $kinds';
  }

  @override
  String get knReportsOff => '자동 리포트 꺼짐';

  @override
  String get knKindDaily => '일간';

  @override
  String get knKindWeekly => '주간';

  @override
  String get knKindMonthly => '월간';

  @override
  String get knNextRunning =>
      '정리하는 중입니다. 로그 줄은 바로 들어가고, 프로젝트 갱신이 있으면 검토할 제안이 생깁니다.';

  @override
  String knNextReview(int days, int lines, int projects) {
    return '정리 제안이 $days일째 검토를 기다립니다 — 로그 $lines줄, 프로젝트 $projects개. 검토해 적용해야 검색·질문·리포트의 근거가 됩니다.';
  }

  @override
  String knNextReviewToday(int lines, int projects) {
    return '정리 제안이 검토를 기다립니다 — 로그 $lines줄, 프로젝트 $projects개. 검토해 적용해야 검색·질문·리포트의 근거가 됩니다.';
  }

  @override
  String get knNextCollectFailed =>
      '마지막 매일 수집이 실패했습니다. 연결 탭에서 어떤 소스가 실패했는지 보세요.';

  @override
  String get knNextNothing => '아직 모은 기록이 없습니다. 연결 탭에서 소스를 켜고 지금 수집해 보세요.';

  @override
  String get knNextNoAgent =>
      '정리할 원본이 쌓였지만 정리할 에이전트가 없습니다. Claude Code 같은 CLI에 로그인하거나 OpenRouter 키를 저장하세요.';

  @override
  String knNextDigest(int days, int files) {
    return '마지막 정리 뒤 원본 $days일 치와 전사본·세션 $files개가 쌓였습니다. 정리하면 로그 줄이 됩니다.';
  }

  @override
  String get knNextReports => '리포트를 켜 두면 매주 이 기록으로 한 일·결정·다음 할 일을 정리해 둡니다.';

  @override
  String get knNextAllSet => '모두 정리돼 있습니다.';

  @override
  String knNextAllSetWhen(String day) {
    return '모두 정리돼 있습니다. 다음 자동 정리 $day.';
  }

  @override
  String get knActionReview => '검토하기';

  @override
  String get knActionConnect => '연결 탭 열기';

  @override
  String get knActionSettings => '설정 열기';

  @override
  String get knActionDigest => '지금 정리하기';

  @override
  String get knActionReports => '리포트 설정';

  @override
  String get knDigestStarted =>
      '정리를 시작했습니다. 지금까지의 기록을 먼저 수집한 뒤 로그로 정리합니다(몇 분).';

  @override
  String get knShowSteps => '단계 보기';

  @override
  String get knHideSteps => '단계 숨기기';

  @override
  String reviewGroupsTitle(int projects, int lines) {
    return '프로젝트 $projects개 · 로그 $lines줄';
  }

  @override
  String get reviewGroupsHint =>
      '프로젝트마다 묶었습니다. 프로젝트를 체크하면 그 로그 줄과 프로젝트 페이지가 함께 들어갑니다. 펼쳐서 줄마다 고를 수도 있습니다.';

  @override
  String get reviewNoProject => '프로젝트 없음';

  @override
  String reviewGroupLines(int chosen, int lines) {
    return '로그 $chosen/$lines줄';
  }

  @override
  String reviewGroupPage(String badge) {
    return '페이지 $badge';
  }

  @override
  String get onbFirstDigestTitle => '첫 정리 해 보기';

  @override
  String onbFirstDigestBody(String agent) {
    return '$agent가 방금 모은 원본을 읽고 로그 줄로 정리합니다. 몇 분 걸리고, 앱을 열면 메모리 탭 맨 위에 진행 상황이 보입니다. 앞으로는 매일 수집 뒤 자동으로 정리됩니다.';
  }

  @override
  String get onbFirstDigestButton => '첫 정리 시작';

  @override
  String get onbFirstDigestStarted =>
      '첫 정리를 시작했습니다. 앱을 열면 메모리 탭 맨 위에 진행 상황이 보이고, 끝나면 로그 줄이 바로 들어가 있습니다.';

  @override
  String get onbFirstDigestNoAgent =>
      '정리할 에이전트가 없어 첫 정리는 건너뜁니다. Claude Code 같은 CLI에 로그인한 뒤 메모리 탭의 \'지금 정리하기\'로 하면 됩니다.';

  @override
  String askBasis(int knowledge, int raw) {
    return '근거: 정리된 기록 $knowledge · 원본 $raw';
  }

  @override
  String get askBasisRawOnly =>
      '정리된 기록이 없어 원본만 근거로 썼습니다. 메모리 탭에서 정리하면 근거가 짧고 분명해집니다.';

  @override
  String get askSourceKnowledge => '정리된 기록';

  @override
  String get askSourceRaw => '원본';

  @override
  String get settingsDailyOn => '매일 수집 뒤 그날 기록을 로그 줄로 옮깁니다. 검토 없이 바로 들어갑니다.';

  @override
  String get settingsDailyOff => '끄면 월요일 주간 정리와 \'지금 정리하기\'로만 로그가 생깁니다.';

  @override
  String get settingsWeeklyNow => '주간 정리';

  @override
  String get settingsWeeklyStarted => '주간 정리를 시작했습니다. 프로젝트 갱신은 검토할 제안으로 남습니다.';

  @override
  String get knNextAllSetDaily => '모두 정리돼 있습니다. 매일 수집 뒤 그날 치가 로그로 정리됩니다.';

  @override
  String get settingsDailyDigest => '매일 정리';
}
