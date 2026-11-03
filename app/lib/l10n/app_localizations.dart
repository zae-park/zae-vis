import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko')
  ];

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get commonRetry;

  /// No description provided for @commonDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get commonDone;

  /// No description provided for @commonFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패'**
  String get commonFailed;

  /// No description provided for @commonAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get commonAdd;

  /// No description provided for @commonClear.
  ///
  /// In ko, this message translates to:
  /// **'지우기'**
  String get commonClear;

  /// No description provided for @commonDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get commonDelete;

  /// No description provided for @commonChange.
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get commonChange;

  /// No description provided for @commonDownload.
  ///
  /// In ko, this message translates to:
  /// **'내려받기'**
  String get commonDownload;

  /// No description provided for @commonSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get commonSettings;

  /// No description provided for @commonSearch.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get commonSearch;

  /// No description provided for @commonNone.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get commonNone;

  /// No description provided for @commonSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장했습니다'**
  String get commonSaved;

  /// No description provided for @commonCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In ko, this message translates to:
  /// **'복사했습니다'**
  String get commonCopied;

  /// No description provided for @commonError.
  ///
  /// In ko, this message translates to:
  /// **'오류: {error}'**
  String commonError(String error);

  /// No description provided for @settingsLanguage.
  ///
  /// In ko, this message translates to:
  /// **'화면 언어'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageHint.
  ///
  /// In ko, this message translates to:
  /// **'앱의 메뉴·버튼 글자를 이 언어로 보여 줍니다. 시스템은 운영체제 언어를 따릅니다. 서버가 보내는 메시지는 아직 한국어로만 나옵니다.'**
  String get settingsLanguageHint;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get settingsLanguageSystem;

  /// No description provided for @languageKorean.
  ///
  /// In ko, this message translates to:
  /// **'한국어'**
  String get languageKorean;

  /// No description provided for @languageEnglish.
  ///
  /// In ko, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @textScaleSmall.
  ///
  /// In ko, this message translates to:
  /// **'작게'**
  String get textScaleSmall;

  /// No description provided for @textScaleDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본'**
  String get textScaleDefault;

  /// No description provided for @textScaleLarger.
  ///
  /// In ko, this message translates to:
  /// **'조금 크게'**
  String get textScaleLarger;

  /// No description provided for @textScaleLarge.
  ///
  /// In ko, this message translates to:
  /// **'크게'**
  String get textScaleLarge;

  /// No description provided for @textScaleHuge.
  ///
  /// In ko, this message translates to:
  /// **'아주 크게'**
  String get textScaleHuge;

  /// No description provided for @askQuotaHandoff.
  ///
  /// In ko, this message translates to:
  /// **'{skips} 할당량 → {writer}가 작성'**
  String askQuotaHandoff(String skips, String writer);

  /// No description provided for @askHintClarify.
  ///
  /// In ko, this message translates to:
  /// **'위 질문에 답해 주세요 (고르거나 직접 적기)'**
  String get askHintClarify;

  /// No description provided for @askHintContinue.
  ///
  /// In ko, this message translates to:
  /// **'이어서… (\"그건 왜?\", \"[2] 내려받기\"처럼 짧게 이어도 됩니다)'**
  String get askHintContinue;

  /// No description provided for @askHintFirst.
  ///
  /// In ko, this message translates to:
  /// **'찾을 말, 질문, 또는 \"11월 2일 전사본 내려받기\"'**
  String get askHintFirst;

  /// No description provided for @askAnswering.
  ///
  /// In ko, this message translates to:
  /// **'답하는 중'**
  String get askAnswering;

  /// No description provided for @askSearching.
  ///
  /// In ko, this message translates to:
  /// **'찾는 중'**
  String get askSearching;

  /// No description provided for @askSend.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get askSend;

  /// No description provided for @askNewConversation.
  ///
  /// In ko, this message translates to:
  /// **'새 대화'**
  String get askNewConversation;

  /// No description provided for @askHistory.
  ///
  /// In ko, this message translates to:
  /// **'이전 대화'**
  String get askHistory;

  /// No description provided for @askConversationMeta.
  ///
  /// In ko, this message translates to:
  /// **'{turns}턴 · {when}'**
  String askConversationMeta(int turns, String when);

  /// No description provided for @askDeleteConversation.
  ///
  /// In ko, this message translates to:
  /// **'이 대화 지우기'**
  String get askDeleteConversation;

  /// No description provided for @askIntro.
  ///
  /// In ko, this message translates to:
  /// **'기록에 말을 거세요\n단어를 넣으면 로그 · 프로젝트 · 리포트 · 전사본 · 수집 원본에서 바로 찾습니다. \"색인은 왜 미뤘지?\"처럼 물으면 찾은 문단만 근거로 에이전트가 출처 [번호]를 달아 답합니다. \"11월 2일 전사본 내려받기\"처럼 말하면 그 파일을 내려받을 수 있습니다. 에이전트는 파일을 읽기만 합니다.'**
  String get askIntro;

  /// No description provided for @askAnswerBy.
  ///
  /// In ko, this message translates to:
  /// **'답은 {agent}가 씁니다 · {detail}'**
  String askAnswerBy(String agent, String detail);

  /// No description provided for @askNoAgent.
  ///
  /// In ko, this message translates to:
  /// **'답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.'**
  String get askNoAgent;

  /// No description provided for @askOpenSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get askOpenSettings;

  /// No description provided for @askStopping.
  ///
  /// In ko, this message translates to:
  /// **'멈추는 중…'**
  String get askStopping;

  /// No description provided for @askWriting.
  ///
  /// In ko, this message translates to:
  /// **'{agent}가 기록을 읽고 답을 쓰는 중… (수십 초)'**
  String askWriting(String agent);

  /// No description provided for @askAgentFallback.
  ///
  /// In ko, this message translates to:
  /// **'에이전트'**
  String get askAgentFallback;

  /// No description provided for @askStop.
  ///
  /// In ko, this message translates to:
  /// **'멈추기'**
  String get askStop;

  /// No description provided for @askClarifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'되묻기'**
  String get askClarifyTitle;

  /// No description provided for @askClarifyDone.
  ///
  /// In ko, this message translates to:
  /// **'{who} · 기록이 여러 갈래라 되물었습니다'**
  String askClarifyDone(String who);

  /// No description provided for @askClarifyPrompt.
  ///
  /// In ko, this message translates to:
  /// **'고르거나 아래에 직접 적어 주세요 · {who}'**
  String askClarifyPrompt(String who);

  /// No description provided for @askSources.
  ///
  /// In ko, this message translates to:
  /// **'근거'**
  String get askSources;

  /// No description provided for @askAnswerMeta.
  ///
  /// In ko, this message translates to:
  /// **'{who} · {seconds}초 · 발췌 {count}개만 근거로 썼습니다'**
  String askAnswerMeta(String who, String seconds, int count);

  /// No description provided for @askSearchingEllipsis.
  ///
  /// In ko, this message translates to:
  /// **'찾는 중…'**
  String get askSearchingEllipsis;

  /// No description provided for @askSeeAllFound.
  ///
  /// In ko, this message translates to:
  /// **'찾은 기록 {count}건 모두 보기'**
  String askSeeAllFound(int count);

  /// No description provided for @askFound.
  ///
  /// In ko, this message translates to:
  /// **'찾은 기록 {count}건'**
  String askFound(int count);

  /// No description provided for @askGetAnswer.
  ///
  /// In ko, this message translates to:
  /// **'답 받기'**
  String get askGetAnswer;

  /// No description provided for @askSeeAll.
  ///
  /// In ko, this message translates to:
  /// **'모두 보기 ({count}건)'**
  String askSeeAll(int count);

  /// No description provided for @askOneFile.
  ///
  /// In ko, this message translates to:
  /// **'이 파일입니다.'**
  String get askOneFile;

  /// No description provided for @askFiles.
  ///
  /// In ko, this message translates to:
  /// **'파일 {count}개입니다.'**
  String askFiles(int count);

  /// No description provided for @askOpen.
  ///
  /// In ko, this message translates to:
  /// **'열기'**
  String get askOpen;

  /// No description provided for @askStopped.
  ///
  /// In ko, this message translates to:
  /// **'멈췄습니다'**
  String get askStopped;

  /// No description provided for @askAskAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 묻기'**
  String get askAskAgain;

  /// No description provided for @askTooltipMore.
  ///
  /// In ko, this message translates to:
  /// **'누르면 전체 발췌와 원문'**
  String get askTooltipMore;

  /// No description provided for @askSourceIndex.
  ///
  /// In ko, this message translates to:
  /// **'근거 {index} / {total}'**
  String askSourceIndex(int index, int total);

  /// No description provided for @askPrevSource.
  ///
  /// In ko, this message translates to:
  /// **'이전 근거'**
  String get askPrevSource;

  /// No description provided for @askNextSource.
  ///
  /// In ko, this message translates to:
  /// **'다음 근거'**
  String get askNextSource;

  /// No description provided for @askNoExcerpt.
  ///
  /// In ko, this message translates to:
  /// **'(발췌 없음)'**
  String get askNoExcerpt;

  /// No description provided for @askOpenOriginal.
  ///
  /// In ko, this message translates to:
  /// **'원문 열기'**
  String get askOpenOriginal;

  /// No description provided for @memoryLayerLog.
  ///
  /// In ko, this message translates to:
  /// **'기록'**
  String get memoryLayerLog;

  /// No description provided for @memoryLayerDay.
  ///
  /// In ko, this message translates to:
  /// **'하루'**
  String get memoryLayerDay;

  /// No description provided for @memoryLayerOrigins.
  ///
  /// In ko, this message translates to:
  /// **'원본'**
  String get memoryLayerOrigins;

  /// No description provided for @memoryLayerProjects.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get memoryLayerProjects;

  /// No description provided for @memoryHideFlow.
  ///
  /// In ko, this message translates to:
  /// **'흐름 설명 숨기기'**
  String get memoryHideFlow;

  /// No description provided for @memoryShowFlow.
  ///
  /// In ko, this message translates to:
  /// **'내 기록이 어떻게 쓰이는지'**
  String get memoryShowFlow;

  /// No description provided for @memoryMine.
  ///
  /// In ko, this message translates to:
  /// **'내가 쓴 줄'**
  String get memoryMine;

  /// No description provided for @memoryFlowMineBody.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록·녹음·전사본. 정리 에이전트는 고치지 못하고 검토를 거쳐 제안만 합니다.'**
  String get memoryFlowMineBody;

  /// No description provided for @memoryFlowDigestTitle.
  ///
  /// In ko, this message translates to:
  /// **'정리가 쓴 줄'**
  String get memoryFlowDigestTitle;

  /// No description provided for @memoryFlowDigestBody.
  ///
  /// In ko, this message translates to:
  /// **'수집된 원본에서 에이전트가 뽑은 줄. 출처를 누르면 원본이 열립니다.'**
  String get memoryFlowDigestBody;

  /// No description provided for @memoryFlowUseTitle.
  ///
  /// In ko, this message translates to:
  /// **'쓰임'**
  String get memoryFlowUseTitle;

  /// No description provided for @memoryFlowUseBody.
  ///
  /// In ko, this message translates to:
  /// **'검색·질문·리포트가 이 줄들과 원본을 근거로 씁니다.'**
  String get memoryFlowUseBody;

  /// No description provided for @memoryFlowSameDayTitle.
  ///
  /// In ko, this message translates to:
  /// **'같은 날'**
  String get memoryFlowSameDayTitle;

  /// No description provided for @memoryFlowSameDayBody.
  ///
  /// In ko, this message translates to:
  /// **'내가 쓴 줄과 수집된 원본을 날짜 하나의 카드로 모읍니다.'**
  String get memoryFlowSameDayBody;

  /// No description provided for @memoryFlowLinkedBody.
  ///
  /// In ko, this message translates to:
  /// **'정리가 원본에서 뽑은 줄은 그 파일과 같은 카드에 붙습니다.'**
  String get memoryFlowLinkedBody;

  /// No description provided for @memoryFlowOneRecordTitle.
  ///
  /// In ko, this message translates to:
  /// **'한 기록'**
  String get memoryFlowOneRecordTitle;

  /// No description provided for @memoryFlowOneRecordBody.
  ///
  /// In ko, this message translates to:
  /// **'같은 카드에 있으면 한 로그·한 검색으로 관리되고 있습니다.'**
  String get memoryFlowOneRecordBody;

  /// No description provided for @memoryFlowDailyTitle.
  ///
  /// In ko, this message translates to:
  /// **'매일 수집'**
  String get memoryFlowDailyTitle;

  /// No description provided for @memoryFlowDailyBody.
  ///
  /// In ko, this message translates to:
  /// **'git·에이전트 세션·셸·전사본·커넥터가 날짜별 파일로 쌓입니다.'**
  String get memoryFlowDailyBody;

  /// No description provided for @memoryFlowDigestStepBody.
  ///
  /// In ko, this message translates to:
  /// **'주간 정리가 이 파일을 읽어 기록 줄과 프로젝트 상태를 씁니다 (검토 뒤 적용).'**
  String get memoryFlowDigestStepBody;

  /// No description provided for @memoryFlowSearchBody.
  ///
  /// In ko, this message translates to:
  /// **'원본도 그대로 색인되어 검색·질문에 잡힙니다.'**
  String get memoryFlowSearchBody;

  /// No description provided for @memoryFlowProjectPagesTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로젝트 페이지'**
  String get memoryFlowProjectPagesTitle;

  /// No description provided for @memoryFlowProjectPagesBody.
  ///
  /// In ko, this message translates to:
  /// **'정리 에이전트가 프로젝트마다 현재 상태·결정·열린 문제를 갱신합니다.'**
  String get memoryFlowProjectPagesBody;

  /// No description provided for @memoryFlowLinkTitle.
  ///
  /// In ko, this message translates to:
  /// **'기록과 연결'**
  String get memoryFlowLinkTitle;

  /// No description provided for @memoryFlowLinkBody.
  ///
  /// In ko, this message translates to:
  /// **'기록 줄의 [[프로젝트]] 링크가 이 페이지로 옵니다.'**
  String get memoryFlowLinkBody;

  /// No description provided for @memoryOriginsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 수집된 원본이 없습니다\n연결 탭에서 \"지금 수집\"을 누르거나 매일 수집을 기다리면 날짜별 파일이 여기 쌓입니다.'**
  String get memoryOriginsEmpty;

  /// No description provided for @memoryOriginsCount.
  ///
  /// In ko, this message translates to:
  /// **'{files}개 파일 · {days}일'**
  String memoryOriginsCount(int files, int days);

  /// No description provided for @memoryCitedBy.
  ///
  /// In ko, this message translates to:
  /// **'기록 {count}줄의 근거'**
  String memoryCitedBy(int count);

  /// No description provided for @memoryNotDigested.
  ///
  /// In ko, this message translates to:
  /// **'아직 정리 안 됨'**
  String get memoryNotDigested;

  /// No description provided for @memoryInboxPending.
  ///
  /// In ko, this message translates to:
  /// **'inbox (아직 정리 전)'**
  String get memoryInboxPending;

  /// No description provided for @memoryProcessed.
  ///
  /// In ko, this message translates to:
  /// **'정리됨'**
  String get memoryProcessed;

  /// No description provided for @memoryNoteMineFilesLinked.
  ///
  /// In ko, this message translates to:
  /// **'내 기록과 수집 원본이 같은 날에 있고, 정리가 그 원본에서 줄을 남겼습니다'**
  String get memoryNoteMineFilesLinked;

  /// No description provided for @memoryNoteMineFiles.
  ///
  /// In ko, this message translates to:
  /// **'내 기록과 수집 원본이 같은 날로 묶여 있습니다'**
  String get memoryNoteMineFiles;

  /// No description provided for @memoryNoteLinked.
  ///
  /// In ko, this message translates to:
  /// **'수집한 원본에서 쓴 줄이 그 파일과 같은 하루에 있습니다'**
  String get memoryNoteLinked;

  /// No description provided for @memoryNoteMineOnly.
  ///
  /// In ko, this message translates to:
  /// **'내가 쓴 줄만 있습니다. 이 날 수집된 원본은 없습니다'**
  String get memoryNoteMineOnly;

  /// No description provided for @memoryNoteFilesOnly.
  ///
  /// In ko, this message translates to:
  /// **'수집된 원본만 있습니다. 아직 기록 줄로 이어지지 않았습니다'**
  String get memoryNoteFilesOnly;

  /// No description provided for @memoryNoteFilesDigest.
  ///
  /// In ko, this message translates to:
  /// **'수집 원본과 정리 줄이 같은 날에 있습니다'**
  String get memoryNoteFilesDigest;

  /// No description provided for @memoryNoteDigestOnly.
  ///
  /// In ko, this message translates to:
  /// **'정리 줄만 있습니다'**
  String get memoryNoteDigestOnly;

  /// No description provided for @memoryDayEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 기록도 수집된 원본도 없습니다\n한 줄 기록이나 연결 탭의 수집이 쌓이면 날짜마다 한 카드로 모입니다.'**
  String get memoryDayEmpty;

  /// No description provided for @memoryDaySummary.
  ///
  /// In ko, this message translates to:
  /// **'내 기록 {mine}줄 · 정리 {digest}줄 · 수집 {files}개 파일'**
  String memoryDaySummary(int mine, int digest, int files);

  /// No description provided for @memoryDayTogether.
  ///
  /// In ko, this message translates to:
  /// **'{days}일은 한 줄과 수집이 함께 있습니다'**
  String memoryDayTogether(int days);

  /// No description provided for @memoryDayLinked.
  ///
  /// In ko, this message translates to:
  /// **'{days}일은 원본에서 줄로 이어졌습니다'**
  String memoryDayLinked(int days);

  /// No description provided for @memoryJoined.
  ///
  /// In ko, this message translates to:
  /// **'함께'**
  String get memoryJoined;

  /// No description provided for @memoryLinked.
  ///
  /// In ko, this message translates to:
  /// **'이어짐'**
  String get memoryLinked;

  /// No description provided for @memoryOneSide.
  ///
  /// In ko, this message translates to:
  /// **'한쪽'**
  String get memoryOneSide;

  /// No description provided for @memoryCollected.
  ///
  /// In ko, this message translates to:
  /// **'수집된 원본'**
  String get memoryCollected;

  /// No description provided for @memoryLinesFromFiles.
  ///
  /// In ko, this message translates to:
  /// **'이 원본에서 남긴 줄'**
  String get memoryLinesFromFiles;

  /// No description provided for @memoryDayDigest.
  ///
  /// In ko, this message translates to:
  /// **'이 날의 정리'**
  String get memoryDayDigest;

  /// No description provided for @memoryProjectStatus.
  ///
  /// In ko, this message translates to:
  /// **'프로젝트 상태'**
  String get memoryProjectStatus;

  /// No description provided for @memoryRefresh.
  ///
  /// In ko, this message translates to:
  /// **'새로고침'**
  String get memoryRefresh;

  /// No description provided for @memoryProjectsHint.
  ///
  /// In ko, this message translates to:
  /// **'정리 에이전트가 프로젝트마다 갱신하는 현재 상태 · 결정 · 열린 문제'**
  String get memoryProjectsHint;

  /// No description provided for @memoryProjectsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 프로젝트 페이지가 없습니다\n정리가 돌면 기록의 [[프로젝트]]마다 페이지를 만듭니다.'**
  String get memoryProjectsEmpty;

  /// No description provided for @logEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 로그가 없습니다. log/YYYY-MM.md에 한 줄을 적거나 주간 정리를 기다려 주세요.'**
  String get logEmpty;

  /// No description provided for @logProposalBanner.
  ///
  /// In ko, this message translates to:
  /// **'정리 제안 {count}건이 검토를 기다립니다 — 로그 {lines}줄. 고른 줄만 worklog에 들어갑니다.'**
  String logProposalBanner(int count, int lines);

  /// No description provided for @logReview.
  ///
  /// In ko, this message translates to:
  /// **'검토하기'**
  String get logReview;

  /// No description provided for @logOnlyMine.
  ///
  /// In ko, this message translates to:
  /// **'내가 쓴 줄만'**
  String get logOnlyMine;

  /// No description provided for @logNoMatch.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 로그가 없습니다.'**
  String get logNoMatch;

  /// No description provided for @logEdited.
  ///
  /// In ko, this message translates to:
  /// **'줄을 고쳤습니다'**
  String get logEdited;

  /// No description provided for @logOriginNotFound.
  ///
  /// In ko, this message translates to:
  /// **'원본 파일을 찾지 못했습니다: {src}'**
  String logOriginNotFound(String src);

  /// No description provided for @logDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 줄을 지울까요?'**
  String get logDeleteTitle;

  /// No description provided for @logDeleted.
  ///
  /// In ko, this message translates to:
  /// **'줄을 지웠습니다'**
  String get logDeleted;

  /// No description provided for @logByDigestTip.
  ///
  /// In ko, this message translates to:
  /// **'정리 에이전트가 원본에서 뽑아 쓴 줄 — 출처를 누르면 원본이 열립니다'**
  String get logByDigestTip;

  /// No description provided for @logMineTip.
  ///
  /// In ko, this message translates to:
  /// **'내가 쓴 줄 — 정리 에이전트는 이 줄을 고치지 않습니다 (검토를 거쳐 제안만 합니다)'**
  String get logMineTip;

  /// No description provided for @logDigest.
  ///
  /// In ko, this message translates to:
  /// **'정리'**
  String get logDigest;

  /// No description provided for @logMine.
  ///
  /// In ko, this message translates to:
  /// **'내 기록'**
  String get logMine;

  /// No description provided for @logSource.
  ///
  /// In ko, this message translates to:
  /// **'출처 {source}'**
  String logSource(String source);

  /// No description provided for @logMenu.
  ///
  /// In ko, this message translates to:
  /// **'줄 메뉴'**
  String get logMenu;

  /// No description provided for @logEdit.
  ///
  /// In ko, this message translates to:
  /// **'편집'**
  String get logEdit;

  /// No description provided for @reviewApplied.
  ///
  /// In ko, this message translates to:
  /// **'적용했습니다: 로그 {lines}줄 · 프로젝트 {projects}개'**
  String reviewApplied(int lines, int projects);

  /// No description provided for @reviewDismissTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 정리 결과를 버릴까요?'**
  String get reviewDismissTitle;

  /// No description provided for @reviewDismissBody.
  ///
  /// In ko, this message translates to:
  /// **'worklog에는 아무것도 쓰지 않습니다. 다음 정리에서 같은 원본을 다시 읽습니다.'**
  String get reviewDismissBody;

  /// No description provided for @reviewDismiss.
  ///
  /// In ko, this message translates to:
  /// **'버리기'**
  String get reviewDismiss;

  /// No description provided for @reviewDismissed.
  ///
  /// In ko, this message translates to:
  /// **'버렸습니다'**
  String get reviewDismissed;

  /// No description provided for @reviewTitle.
  ///
  /// In ko, this message translates to:
  /// **'정리 결과 검토'**
  String get reviewTitle;

  /// No description provided for @reviewIntro.
  ///
  /// In ko, this message translates to:
  /// **'에이전트가 쓰려던 내용입니다. 남길 것만 고르고 적용하세요. 고르지 않은 것은 worklog에 들어가지 않습니다.'**
  String get reviewIntro;

  /// No description provided for @reviewRemoved.
  ///
  /// In ko, this message translates to:
  /// **'에이전트가 지우려던 줄 {count}개 — 적용해도 지워지지 않습니다'**
  String reviewRemoved(int count);

  /// No description provided for @reviewLogLines.
  ///
  /// In ko, this message translates to:
  /// **'로그 줄 ({chosen}/{total})'**
  String reviewLogLines(int chosen, int total);

  /// No description provided for @reviewNoNewLines.
  ///
  /// In ko, this message translates to:
  /// **'새 줄 없음'**
  String get reviewNoNewLines;

  /// No description provided for @reviewDeselectAll.
  ///
  /// In ko, this message translates to:
  /// **'모두 해제'**
  String get reviewDeselectAll;

  /// No description provided for @reviewSelectAll.
  ///
  /// In ko, this message translates to:
  /// **'모두 선택'**
  String get reviewSelectAll;

  /// No description provided for @reviewProjects.
  ///
  /// In ko, this message translates to:
  /// **'프로젝트 ({chosen}/{total})'**
  String reviewProjects(int chosen, int total);

  /// No description provided for @reviewNoProjects.
  ///
  /// In ko, this message translates to:
  /// **'바뀐 프로젝트 없음'**
  String get reviewNoProjects;

  /// No description provided for @reviewNewFile.
  ///
  /// In ko, this message translates to:
  /// **'새 파일'**
  String get reviewNewFile;

  /// No description provided for @reviewChanged.
  ///
  /// In ko, this message translates to:
  /// **'변경'**
  String get reviewChanged;

  /// No description provided for @reviewSummaries.
  ///
  /// In ko, this message translates to:
  /// **'월간 정리 ({count})'**
  String reviewSummaries(int count);

  /// No description provided for @reviewNoSummaries.
  ///
  /// In ko, this message translates to:
  /// **'바뀐 정리 없음'**
  String get reviewNoSummaries;

  /// No description provided for @reviewApplySummaries.
  ///
  /// In ko, this message translates to:
  /// **'월간 정리 변경을 적용'**
  String get reviewApplySummaries;

  /// No description provided for @reviewProcessed.
  ///
  /// In ko, this message translates to:
  /// **'처리된 inbox 파일 ({count})'**
  String reviewProcessed(int count);

  /// No description provided for @reviewMoveProcessed.
  ///
  /// In ko, this message translates to:
  /// **'읽은 inbox 파일을 processed/로 옮김'**
  String get reviewMoveProcessed;

  /// No description provided for @reviewMore.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}'**
  String reviewMore(int count);

  /// No description provided for @reviewProcessedHint.
  ///
  /// In ko, this message translates to:
  /// **'끄면 다음 정리에서 다시 읽습니다.'**
  String get reviewProcessedHint;

  /// No description provided for @reviewAgentReport.
  ///
  /// In ko, this message translates to:
  /// **'에이전트 보고'**
  String get reviewAgentReport;

  /// No description provided for @reviewSelected.
  ///
  /// In ko, this message translates to:
  /// **'선택 {count}개'**
  String reviewSelected(int count);

  /// No description provided for @reviewApply.
  ///
  /// In ko, this message translates to:
  /// **'선택한 것 적용'**
  String get reviewApply;

  /// No description provided for @reviewStatusApplied.
  ///
  /// In ko, this message translates to:
  /// **'적용됨'**
  String get reviewStatusApplied;

  /// No description provided for @reviewStatusDismissed.
  ///
  /// In ko, this message translates to:
  /// **'버림'**
  String get reviewStatusDismissed;

  /// No description provided for @reviewLineCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}줄'**
  String reviewLineCount(int count);

  /// No description provided for @reviewPrevLineCount.
  ///
  /// In ko, this message translates to:
  /// **'(이전 {count}줄)'**
  String reviewPrevLineCount(int count);

  /// No description provided for @reviewProposed.
  ///
  /// In ko, this message translates to:
  /// **'제안'**
  String get reviewProposed;

  /// No description provided for @reviewCurrent.
  ///
  /// In ko, this message translates to:
  /// **'현재'**
  String get reviewCurrent;

  /// No description provided for @searchPeriodAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get searchPeriodAll;

  /// No description provided for @searchPeriodWeek.
  ///
  /// In ko, this message translates to:
  /// **'7일'**
  String get searchPeriodWeek;

  /// No description provided for @searchPeriodMonth.
  ///
  /// In ko, this message translates to:
  /// **'30일'**
  String get searchPeriodMonth;

  /// No description provided for @searchPeriodThisMonth.
  ///
  /// In ko, this message translates to:
  /// **'이번 달'**
  String get searchPeriodThisMonth;

  /// No description provided for @searchResultsTitle.
  ///
  /// In ko, this message translates to:
  /// **'\"{query}\" 검색 결과'**
  String searchResultsTitle(String query);

  /// No description provided for @searchClearFilters.
  ///
  /// In ko, this message translates to:
  /// **'필터 지우기'**
  String get searchClearFilters;

  /// No description provided for @searchCount.
  ///
  /// In ko, this message translates to:
  /// **'{total}건'**
  String searchCount(int total);

  /// No description provided for @searchCountOf.
  ///
  /// In ko, this message translates to:
  /// **'{shown} / {total}건'**
  String searchCountOf(int shown, int total);

  /// No description provided for @searchNoIndex.
  ///
  /// In ko, this message translates to:
  /// **'아직 색인이 없습니다. 색인을 먼저 만들어 주세요.'**
  String get searchNoIndex;

  /// No description provided for @searchFailed.
  ///
  /// In ko, this message translates to:
  /// **'검색에 실패했습니다'**
  String get searchFailed;

  /// No description provided for @searchOpenIndex.
  ///
  /// In ko, this message translates to:
  /// **'색인 상태 열기'**
  String get searchOpenIndex;

  /// No description provided for @fileSpeakerNameTitle.
  ///
  /// In ko, this message translates to:
  /// **'[{label}] 이름'**
  String fileSpeakerNameTitle(String label);

  /// No description provided for @fileSpeakerNameHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 재박'**
  String get fileSpeakerNameHint;

  /// No description provided for @fileSpeakerRenamed.
  ///
  /// In ko, this message translates to:
  /// **'[{from}]을 [{to}](으)로 바꿨습니다'**
  String fileSpeakerRenamed(String from, String to);

  /// No description provided for @fileSpeakers.
  ///
  /// In ko, this message translates to:
  /// **'화자'**
  String get fileSpeakers;

  /// No description provided for @fileNameSpeaker.
  ///
  /// In ko, this message translates to:
  /// **'이름 붙이기'**
  String get fileNameSpeaker;

  /// No description provided for @fileSpeakersHint.
  ///
  /// In ko, this message translates to:
  /// **'누르면 이름을 붙입니다. 이 파일에 바로 반영됩니다.'**
  String get fileSpeakersHint;

  /// No description provided for @fileSpeakersDone.
  ///
  /// In ko, this message translates to:
  /// **'화자를 붙였습니다'**
  String get fileSpeakersDone;

  /// No description provided for @fileRelabelTitle.
  ///
  /// In ko, this message translates to:
  /// **'화자를 다시 붙일까요?'**
  String get fileRelabelTitle;

  /// No description provided for @fileLabelTitle.
  ///
  /// In ko, this message translates to:
  /// **'화자를 붙일까요?'**
  String get fileLabelTitle;

  /// No description provided for @fileLabelBody.
  ///
  /// In ko, this message translates to:
  /// **'남겨 둔 원본 녹음을 다시 인식해 말한 사람마다 [A], [B]로 나눕니다. 녹음 길이만큼 걸리고 그동안 CPU를 씁니다.'**
  String get fileLabelBody;

  /// No description provided for @fileLabelBodyNames.
  ///
  /// In ko, this message translates to:
  /// **'붙여 둔 이름은 A, B로 돌아갑니다.'**
  String get fileLabelBodyNames;

  /// No description provided for @fileLabelBodyReplace.
  ///
  /// In ko, this message translates to:
  /// **'이 파일의 본문이 새 글로 바뀝니다.'**
  String get fileLabelBodyReplace;

  /// No description provided for @fileLabelConfirm.
  ///
  /// In ko, this message translates to:
  /// **'붙이기'**
  String get fileLabelConfirm;

  /// No description provided for @fileLabelQueued.
  ///
  /// In ko, this message translates to:
  /// **'화자 붙이기 대기 중'**
  String get fileLabelQueued;

  /// No description provided for @fileLabeling.
  ///
  /// In ko, this message translates to:
  /// **'화자 붙이는 중 · {line}'**
  String fileLabeling(String line);

  /// No description provided for @fileRelabel.
  ///
  /// In ko, this message translates to:
  /// **'화자 다시 붙이기'**
  String get fileRelabel;

  /// No description provided for @fileLabel.
  ///
  /// In ko, this message translates to:
  /// **'화자 붙이기'**
  String get fileLabel;

  /// No description provided for @fileNoSpeakers.
  ///
  /// In ko, this message translates to:
  /// **'말한 사람이 표시되지 않은 전사본입니다.'**
  String get fileNoSpeakers;

  /// No description provided for @fileLastFailed.
  ///
  /// In ko, this message translates to:
  /// **'지난번 실패: {error}'**
  String fileLastFailed(String error);

  /// No description provided for @projectsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'projects/ 폴더에 프로젝트 파일이 없습니다.'**
  String get projectsEmpty;

  /// No description provided for @indexKiwiInstallTitle.
  ///
  /// In ko, this message translates to:
  /// **'한국어 형태소 분석 (Kiwi) 설치'**
  String get indexKiwiInstallTitle;

  /// No description provided for @indexTitle.
  ///
  /// In ko, this message translates to:
  /// **'검색 색인 (AutoRAG Lite)'**
  String get indexTitle;

  /// No description provided for @indexStatus.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get indexStatus;

  /// No description provided for @indexDone.
  ///
  /// In ko, this message translates to:
  /// **'색인 완료'**
  String get indexDone;

  /// No description provided for @indexFreshness.
  ///
  /// In ko, this message translates to:
  /// **'최신 여부'**
  String get indexFreshness;

  /// No description provided for @indexStale.
  ///
  /// In ko, this message translates to:
  /// **'새 파일이 있음 — 다시 색인 필요'**
  String get indexStale;

  /// No description provided for @indexUpToDate.
  ///
  /// In ko, this message translates to:
  /// **'최신'**
  String get indexUpToDate;

  /// No description provided for @indexSemantic.
  ///
  /// In ko, this message translates to:
  /// **'의미 검색'**
  String get indexSemantic;

  /// No description provided for @indexLastError.
  ///
  /// In ko, this message translates to:
  /// **'마지막 오류'**
  String get indexLastError;

  /// No description provided for @indexMoreMessages.
  ///
  /// In ko, this message translates to:
  /// **'· 외 {count}건'**
  String indexMoreMessages(int count);

  /// No description provided for @indexRefreshing.
  ///
  /// In ko, this message translates to:
  /// **'색인 중…'**
  String get indexRefreshing;

  /// No description provided for @indexRefresh.
  ///
  /// In ko, this message translates to:
  /// **'색인 갱신'**
  String get indexRefresh;

  /// No description provided for @indexRebuild.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시'**
  String get indexRebuild;

  /// No description provided for @indexKeepsRunning.
  ///
  /// In ko, this message translates to:
  /// **'창을 닫아도 색인은 계속됩니다.'**
  String get indexKeepsRunning;

  /// No description provided for @indexFirstSlow.
  ///
  /// In ko, this message translates to:
  /// **'처음 색인은 임베딩을 만드느라 몇 분 걸릴 수 있습니다.'**
  String get indexFirstSlow;

  /// No description provided for @indexStateReady.
  ///
  /// In ko, this message translates to:
  /// **'준비됨'**
  String get indexStateReady;

  /// No description provided for @indexStateNever.
  ///
  /// In ko, this message translates to:
  /// **'아직 색인 안 함'**
  String get indexStateNever;

  /// No description provided for @indexStateIdle.
  ///
  /// In ko, this message translates to:
  /// **'대기'**
  String get indexStateIdle;

  /// No description provided for @indexStateNotConfigured.
  ///
  /// In ko, this message translates to:
  /// **'AutoRAG 미설정'**
  String get indexStateNotConfigured;

  /// No description provided for @indexStateUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'연결 실패'**
  String get indexStateUnavailable;

  /// No description provided for @indexKeywords.
  ///
  /// In ko, this message translates to:
  /// **'키워드 분석'**
  String get indexKeywords;

  /// No description provided for @indexInstallKiwi.
  ///
  /// In ko, this message translates to:
  /// **'Kiwi 설치'**
  String get indexInstallKiwi;

  /// No description provided for @indexKiwiTerminalHint.
  ///
  /// In ko, this message translates to:
  /// **'설치: 터미널에서 {command}'**
  String indexKiwiTerminalHint(String command);

  /// No description provided for @indexStarting.
  ///
  /// In ko, this message translates to:
  /// **'색인 시작 중'**
  String get indexStarting;

  /// No description provided for @indexStepRead.
  ///
  /// In ko, this message translates to:
  /// **'본문 읽기'**
  String get indexStepRead;

  /// No description provided for @indexStepEmbed.
  ///
  /// In ko, this message translates to:
  /// **'임베딩·색인'**
  String get indexStepEmbed;

  /// No description provided for @indexStepFinish.
  ///
  /// In ko, this message translates to:
  /// **'마무리'**
  String get indexStepFinish;

  /// No description provided for @backendTranslocated.
  ///
  /// In ko, this message translates to:
  /// **'zaevis를 Applications 폴더로 옮긴 뒤 다시 여세요. (지금은 다운로드한 위치에서 임시로 실행 중이라 매일 수집 예약을 만들 수 없습니다)'**
  String get backendTranslocated;

  /// No description provided for @backendNotInstalled.
  ///
  /// In ko, this message translates to:
  /// **'앱 설치본이 아닙니다'**
  String get backendNotInstalled;

  /// No description provided for @backendExitCode.
  ///
  /// In ko, this message translates to:
  /// **'종료 코드 {code}'**
  String backendExitCode(int code);

  /// No description provided for @backendUpdateInstalledOnly.
  ///
  /// In ko, this message translates to:
  /// **'설치본에서만 업데이트할 수 있습니다.'**
  String get backendUpdateInstalledOnly;

  /// No description provided for @backendUpdateUnsupportedOs.
  ///
  /// In ko, this message translates to:
  /// **'이 운영체제에서는 자동 업데이트를 지원하지 않습니다.'**
  String get backendUpdateUnsupportedOs;

  /// No description provided for @backendWebNoRun.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서는 실행할 수 없습니다'**
  String get backendWebNoRun;

  /// No description provided for @backendWebNoUpdate.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서는 업데이트할 수 없습니다'**
  String get backendWebNoUpdate;

  /// No description provided for @onboardingSourceGit.
  ///
  /// In ko, this message translates to:
  /// **'git 커밋'**
  String get onboardingSourceGit;

  /// No description provided for @onboardingSourceGitHint.
  ///
  /// In ko, this message translates to:
  /// **'코드 폴더 아래 모든 저장소의 커밋 (작성자별로 표시)'**
  String get onboardingSourceGitHint;

  /// No description provided for @onboardingSourceAgents.
  ///
  /// In ko, this message translates to:
  /// **'에이전트 세션'**
  String get onboardingSourceAgents;

  /// No description provided for @onboardingSourceAgentsHint.
  ///
  /// In ko, this message translates to:
  /// **'Claude Code · Codex · Gemini CLI 대화: 요청→응답, 수정한 파일, 실행한 명령'**
  String get onboardingSourceAgentsHint;

  /// No description provided for @onboardingSourceShell.
  ///
  /// In ko, this message translates to:
  /// **'터미널 명령 이력'**
  String get onboardingSourceShell;

  /// No description provided for @onboardingSourceShellHint.
  ///
  /// In ko, this message translates to:
  /// **'zsh 히스토리 (비밀값은 가림). 명령을 친 시각까지 남기려면 연결 탭에서 한 번 켭니다'**
  String get onboardingSourceShellHint;

  /// No description provided for @onboardingSourceTranscripts.
  ///
  /// In ko, this message translates to:
  /// **'회의 전사본'**
  String get onboardingSourceTranscripts;

  /// No description provided for @onboardingSourceTranscriptsHint.
  ///
  /// In ko, this message translates to:
  /// **'전사 서비스 내보내기 폴더, 앱 안 녹음의 whisperX 전사'**
  String get onboardingSourceTranscriptsHint;

  /// No description provided for @onboardingNextConnect.
  ///
  /// In ko, this message translates to:
  /// **'연결 탭에서 소스 확인'**
  String get onboardingNextConnect;

  /// No description provided for @onboardingNextConnectHint.
  ///
  /// In ko, this message translates to:
  /// **'각 소스의 수집 결과를 보고, Slack·Obsidian 같은 외부 소스를 더 붙입니다.'**
  String get onboardingNextConnectHint;

  /// No description provided for @onboardingNextMemory.
  ///
  /// In ko, this message translates to:
  /// **'메모리 탭에서 기록'**
  String get onboardingNextMemory;

  /// No description provided for @onboardingNextMemoryHint.
  ///
  /// In ko, this message translates to:
  /// **'⌘N(어느 앱에서든 ⌘⇧Space)으로 한 줄씩 남기면 검색·질문의 근거가 됩니다.'**
  String get onboardingNextMemoryHint;

  /// No description provided for @onboardingNextReports.
  ///
  /// In ko, this message translates to:
  /// **'리포트 켜기'**
  String get onboardingNextReports;

  /// No description provided for @onboardingNextReportsHint.
  ///
  /// In ko, this message translates to:
  /// **'리포트 탭의 ⚙︎에서 일간·주간을 켜 두면 매일 수집 뒤 에이전트가 정리해 둡니다.'**
  String get onboardingNextReportsHint;

  /// No description provided for @onboardingLogKiwi.
  ///
  /// In ko, this message translates to:
  /// **'한국어 형태소 분석기(Kiwi) 설치 — 첫 색인부터 조사·어미가 붙은 말도 찾습니다 (약 130MB)'**
  String get onboardingLogKiwi;

  /// No description provided for @onboardingLogKiwiFailed.
  ///
  /// In ko, this message translates to:
  /// **'Kiwi 설치 실패 — 나중에 설정 → 검색에서 다시 설치할 수 있습니다: {error}'**
  String onboardingLogKiwiFailed(String error);

  /// No description provided for @onboardingLogServer.
  ///
  /// In ko, this message translates to:
  /// **'서버 시작'**
  String get onboardingLogServer;

  /// No description provided for @onboardingLogCollect.
  ///
  /// In ko, this message translates to:
  /// **'첫 수집 시작 (지난 7일치, 끝나면 검색 색인까지 백그라운드에서 이어집니다)'**
  String get onboardingLogCollect;

  /// No description provided for @onboardingPick.
  ///
  /// In ko, this message translates to:
  /// **'선택'**
  String get onboardingPick;

  /// No description provided for @onboardingReady.
  ///
  /// In ko, this message translates to:
  /// **'준비됐습니다'**
  String get onboardingReady;

  /// No description provided for @onboardingTitle.
  ///
  /// In ko, this message translates to:
  /// **'zaevis 시작하기'**
  String get onboardingTitle;

  /// No description provided for @onboardingReadyBody.
  ///
  /// In ko, this message translates to:
  /// **'첫 수집이 돌고 있고, 끝나면 검색 색인까지 이어집니다. 모은 기록은 검색·질문, 메모리, 리포트 탭에서 보고, 연결 탭에서 소스를 관리합니다.'**
  String get onboardingReadyBody;

  /// No description provided for @onboardingIntro.
  ///
  /// In ko, this message translates to:
  /// **'작업 기록을 어디에 모을지만 정하면 됩니다. 나머지는 앱이 알아서 설치하고 매일 모읍니다. 모은 기록은 검색하고(검색 탭), 근거를 달아 묻고(질문), 날짜순으로 보고(메모리), 일간·주간·월간으로 정리해(리포트) 봅니다.'**
  String get onboardingIntro;

  /// No description provided for @onboardingNext.
  ///
  /// In ko, this message translates to:
  /// **'다음에 할 것'**
  String get onboardingNext;

  /// No description provided for @onboardingOpenApp.
  ///
  /// In ko, this message translates to:
  /// **'앱 열기'**
  String get onboardingOpenApp;

  /// No description provided for @onboardingWorklogFolder.
  ///
  /// In ko, this message translates to:
  /// **'기록을 모을 폴더 (worklog)'**
  String get onboardingWorklogFolder;

  /// No description provided for @onboardingReposFolder.
  ///
  /// In ko, this message translates to:
  /// **'코드 저장소들이 있는 폴더'**
  String get onboardingReposFolder;

  /// No description provided for @onboardingSources.
  ///
  /// In ko, this message translates to:
  /// **'모을 데이터소스'**
  String get onboardingSources;

  /// No description provided for @onboardingSourcesHint.
  ///
  /// In ko, this message translates to:
  /// **'연결 탭에서 언제든 바꾸거나, 커넥터(아무 명령)와 외부 소스(Slack·Notion·Obsidian…)를 더할 수 있습니다.'**
  String get onboardingSourcesHint;

  /// No description provided for @onboardingLanguage.
  ///
  /// In ko, this message translates to:
  /// **'주로 쓰는 언어'**
  String get onboardingLanguage;

  /// No description provided for @onboardingLanguageHint.
  ///
  /// In ko, this message translates to:
  /// **'녹음을 이 언어로 전사합니다. 나중에 설정에서 바꾸거나 자동 감지로 둘 수 있습니다.'**
  String get onboardingLanguageHint;

  /// No description provided for @onboardingDaily.
  ///
  /// In ko, this message translates to:
  /// **'매일 {time}에 수집하고 검색 색인 갱신'**
  String onboardingDaily(String time);

  /// No description provided for @onboardingKiwiHint.
  ///
  /// In ko, this message translates to:
  /// **'키워드 검색이 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾게 합니다. 약 130MB 다운로드, 나중에 설정에서도 설치할 수 있습니다.'**
  String get onboardingKiwiHint;

  /// No description provided for @onboardingSettingUp.
  ///
  /// In ko, this message translates to:
  /// **'설정 중…'**
  String get onboardingSettingUp;

  /// No description provided for @onboardingStart.
  ///
  /// In ko, this message translates to:
  /// **'시작'**
  String get onboardingStart;

  /// No description provided for @onboardingFailed.
  ///
  /// In ko, this message translates to:
  /// **'설정에 실패했습니다: {error}'**
  String onboardingFailed(String error);

  /// No description provided for @collectNeverCollected.
  ///
  /// In ko, this message translates to:
  /// **'아직 수집 안 함'**
  String get collectNeverCollected;

  /// No description provided for @collectJustNow.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get collectJustNow;

  /// No description provided for @collectMinutesAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count}분 전'**
  String collectMinutesAgo(int count);

  /// No description provided for @collectHoursAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count}시간 전'**
  String collectHoursAgo(int count);

  /// No description provided for @collectDaysAgo.
  ///
  /// In ko, this message translates to:
  /// **'{count}일 전'**
  String collectDaysAgo(int count);

  /// No description provided for @collectTranscriptionCancelled.
  ///
  /// In ko, this message translates to:
  /// **'전사를 취소했습니다'**
  String get collectTranscriptionCancelled;

  /// No description provided for @collectTimestampsTitle.
  ///
  /// In ko, this message translates to:
  /// **'셸 설정에 한 줄 추가'**
  String get collectTimestampsTitle;

  /// No description provided for @collectTimestampsBody.
  ///
  /// In ko, this message translates to:
  /// **'~/.zshrc(또는 {zdotdir}/.zshrc) 끝에 다음 한 줄을 붙입니다. 이미 켜져 있으면 그대로 둡니다.\n\n{line}\n\n새로 여는 터미널부터 명령을 친 시각이 남습니다. 시각이 없는 명령도 수집한 날에 모입니다.'**
  String collectTimestampsBody(String zdotdir, String line);

  /// No description provided for @collectTimestampsAdded.
  ///
  /// In ko, this message translates to:
  /// **'{file}에 추가했습니다. 새 터미널부터 시각이 남습니다.'**
  String collectTimestampsAdded(String file);

  /// No description provided for @collectTimestampsAlready.
  ///
  /// In ko, this message translates to:
  /// **'{file}에 이미 켜져 있습니다. 새 터미널부터 시각이 남습니다.'**
  String collectTimestampsAlready(String file);

  /// No description provided for @collectPaneNow.
  ///
  /// In ko, this message translates to:
  /// **'지금'**
  String get collectPaneNow;

  /// No description provided for @collectPaneDaily.
  ///
  /// In ko, this message translates to:
  /// **'매일'**
  String get collectPaneDaily;

  /// No description provided for @collectPaneOutside.
  ///
  /// In ko, this message translates to:
  /// **'바깥'**
  String get collectPaneOutside;

  /// No description provided for @collectQuickTitle.
  ///
  /// In ko, this message translates to:
  /// **'바로 넣기'**
  String get collectQuickTitle;

  /// No description provided for @collectQuickHint.
  ///
  /// In ko, this message translates to:
  /// **'저장하는 즉시 worklog에 들어갑니다. 검색에는 다음 색인 뒤에 잡힙니다.'**
  String get collectQuickHint;

  /// No description provided for @collectAddedToLog.
  ///
  /// In ko, this message translates to:
  /// **'로그에 추가했습니다'**
  String get collectAddedToLog;

  /// No description provided for @collectOneLine.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록'**
  String get collectOneLine;

  /// No description provided for @collectSavedToInbox.
  ///
  /// In ko, this message translates to:
  /// **'inbox에 저장: {file}'**
  String collectSavedToInbox(String file);

  /// No description provided for @collectPasteTranscript.
  ///
  /// In ko, this message translates to:
  /// **'전사본 붙여넣기'**
  String get collectPasteTranscript;

  /// No description provided for @collectRecord.
  ///
  /// In ko, this message translates to:
  /// **'녹음하기'**
  String get collectRecord;

  /// No description provided for @collectQueuedRecordings.
  ///
  /// In ko, this message translates to:
  /// **'녹음 {count}개를 전사 대기열에 넣었습니다'**
  String collectQueuedRecordings(int count);

  /// No description provided for @collectUploadRecordings.
  ///
  /// In ko, this message translates to:
  /// **'녹음 올리기 (whisperX)'**
  String get collectUploadRecordings;

  /// No description provided for @collectSourcesTitle.
  ///
  /// In ko, this message translates to:
  /// **'데이터소스'**
  String get collectSourcesTitle;

  /// No description provided for @collectSourcesHint.
  ///
  /// In ko, this message translates to:
  /// **'매일 자동으로 모읍니다. 켜고 끄거나, 지금 바로 모을 수 있습니다.'**
  String get collectSourcesHint;

  /// No description provided for @collectStarted.
  ///
  /// In ko, this message translates to:
  /// **'수집을 시작했습니다 (끝나면 색인까지)'**
  String get collectStarted;

  /// No description provided for @collectCollecting.
  ///
  /// In ko, this message translates to:
  /// **'수집 중…'**
  String get collectCollecting;

  /// No description provided for @collectNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 수집'**
  String get collectNow;

  /// No description provided for @collectSourceCollecting.
  ///
  /// In ko, this message translates to:
  /// **'{title} 수집 중'**
  String collectSourceCollecting(String title);

  /// No description provided for @collectSourceStarted.
  ///
  /// In ko, this message translates to:
  /// **'{title} 수집을 시작했습니다'**
  String collectSourceStarted(String title);

  /// No description provided for @collectDeleted.
  ///
  /// In ko, this message translates to:
  /// **'삭제했습니다'**
  String get collectDeleted;

  /// No description provided for @collectConnectorAdded.
  ///
  /// In ko, this message translates to:
  /// **'\"{name}\" 커넥터를 추가하고 첫 수집을 시작했습니다. 결과는 카드에 표시됩니다.'**
  String collectConnectorAdded(String name);

  /// No description provided for @collectAddConnector.
  ///
  /// In ko, this message translates to:
  /// **'커넥터 추가'**
  String get collectAddConnector;

  /// No description provided for @collectAnyCommand.
  ///
  /// In ko, this message translates to:
  /// **'Markdown이나 텍스트를 출력하는 명령이면 무엇이든 데이터소스가 됩니다 — 폴더의 노트, 캘린더, 사내 도구의 내보내기 스크립트.'**
  String get collectAnyCommand;

  /// No description provided for @collectExternalTitle.
  ///
  /// In ko, this message translates to:
  /// **'외부 소스 (AutoRAG)'**
  String get collectExternalTitle;

  /// No description provided for @collectExternalHint.
  ///
  /// In ko, this message translates to:
  /// **'Slack·Notion·Obsidian·GitHub 같은 곳을 AutoRAG가 직접 색인해 검색에 섞습니다. worklog에는 들어가지 않습니다.'**
  String get collectExternalHint;

  /// No description provided for @collectSyncing.
  ///
  /// In ko, this message translates to:
  /// **'동기화 중…'**
  String get collectSyncing;

  /// No description provided for @collectInstallTask.
  ///
  /// In ko, this message translates to:
  /// **'{title} 도구 설치 ({bin})'**
  String collectInstallTask(String title, String bin);

  /// No description provided for @collectInstalled.
  ///
  /// In ko, this message translates to:
  /// **'{bin} 설치됨. 이제 그 도구에서 로그인·수집을 한 번 한 뒤 연결하세요.'**
  String collectInstalled(String bin);

  /// No description provided for @collectExtOn.
  ///
  /// In ko, this message translates to:
  /// **'{title}을(를) 켰습니다. 동기화를 시작합니다.'**
  String collectExtOn(String title);

  /// No description provided for @collectExtOff.
  ///
  /// In ko, this message translates to:
  /// **'{title}을(를) 껐습니다'**
  String collectExtOff(String title);

  /// No description provided for @collectSavedSyncing.
  ///
  /// In ko, this message translates to:
  /// **'저장했습니다. 동기화를 시작합니다.'**
  String get collectSavedSyncing;

  /// No description provided for @collectExtConnected.
  ///
  /// In ko, this message translates to:
  /// **'{title}을(를) 연결했습니다. 첫 동기화를 시작합니다.'**
  String collectExtConnected(String title);

  /// No description provided for @collectExtSyncStarted.
  ///
  /// In ko, this message translates to:
  /// **'외부 소스 동기화를 시작했습니다'**
  String get collectExtSyncStarted;

  /// No description provided for @collectExtRemoved.
  ///
  /// In ko, this message translates to:
  /// **'{title} 연결을 지웠습니다'**
  String collectExtRemoved(String title);

  /// No description provided for @collectNoExternal.
  ///
  /// In ko, this message translates to:
  /// **'연결된 외부 소스가 없습니다.'**
  String get collectNoExternal;

  /// No description provided for @collectInboxTitle.
  ///
  /// In ko, this message translates to:
  /// **'inbox — 다음 주간 정리에서 로그로 정리됩니다'**
  String get collectInboxTitle;

  /// No description provided for @collectTranscribeQueued.
  ///
  /// In ko, this message translates to:
  /// **'전사 대기'**
  String get collectTranscribeQueued;

  /// No description provided for @collectCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소했습니다'**
  String get collectCancelled;

  /// No description provided for @collectTranscribing.
  ///
  /// In ko, this message translates to:
  /// **'전사 중…'**
  String get collectTranscribing;

  /// No description provided for @collectTranscripts.
  ///
  /// In ko, this message translates to:
  /// **'전사본'**
  String get collectTranscripts;

  /// No description provided for @collectPendingAudio.
  ///
  /// In ko, this message translates to:
  /// **'전사 대기 녹음'**
  String get collectPendingAudio;

  /// No description provided for @collectSessionNotes.
  ///
  /// In ko, this message translates to:
  /// **'Claude Code 세션 노트'**
  String get collectSessionNotes;

  /// No description provided for @collectSpanHourMin.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 {minutes}분'**
  String collectSpanHourMin(int hours, int minutes);

  /// No description provided for @collectSpanMinSec.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 {seconds}초'**
  String collectSpanMinSec(int minutes, int seconds);

  /// No description provided for @collectSpanSec.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초'**
  String collectSpanSec(int seconds);

  /// No description provided for @collectStartedChecking.
  ///
  /// In ko, this message translates to:
  /// **'수집을 시작했습니다. 어느 단계인지 확인하는 중…'**
  String get collectStartedChecking;

  /// No description provided for @collectNoResponse.
  ///
  /// In ko, this message translates to:
  /// **'응답이 없습니다 · 마지막 신호 {span} 전'**
  String collectNoResponse(String span);

  /// No description provided for @collectQuiet.
  ///
  /// In ko, this message translates to:
  /// **'진행 중 · 출력 없이 {quiet} · 전체 {total}'**
  String collectQuiet(String quiet, String total);

  /// No description provided for @collectRunning.
  ///
  /// In ko, this message translates to:
  /// **'진행 중 · 전체 {total}'**
  String collectRunning(String total);

  /// No description provided for @collectStaleNote.
  ///
  /// In ko, this message translates to:
  /// **'서버가 이 단계에서 더 이상 신호를 보내지 않습니다.'**
  String get collectStaleNote;

  /// No description provided for @collectQuietNote.
  ///
  /// In ko, this message translates to:
  /// **'전사는 녹음이 길면 한동안 출력이 없습니다. 시간이 늘어나면 아직 그 단계에 있습니다.'**
  String get collectQuietNote;

  /// No description provided for @collectCancelTranscription.
  ///
  /// In ko, this message translates to:
  /// **'전사 취소'**
  String get collectCancelTranscription;

  /// No description provided for @collectTimestampsOn.
  ///
  /// In ko, this message translates to:
  /// **'시각 기록 켜기'**
  String get collectTimestampsOn;

  /// No description provided for @collectTimestampsHint.
  ///
  /// In ko, this message translates to:
  /// **'명령을 친 시각도 남기려면 켭니다. 켜지 않아도 명령은 모입니다.'**
  String get collectTimestampsHint;

  /// No description provided for @collectOnePerLine.
  ///
  /// In ko, this message translates to:
  /// **'한 줄에 하나씩'**
  String get collectOnePerLine;

  /// No description provided for @collectOnlyThis.
  ///
  /// In ko, this message translates to:
  /// **'이것만 수집'**
  String get collectOnlyThis;

  /// No description provided for @collectEnvNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 없음'**
  String get collectEnvNone;

  /// No description provided for @collectEnvStored.
  ///
  /// In ko, this message translates to:
  /// **'저장됨 — 바꾸려면 새 값 입력'**
  String get collectEnvStored;

  /// No description provided for @collectEnvInServer.
  ///
  /// In ko, this message translates to:
  /// **'서버 환경에 있음'**
  String get collectEnvInServer;

  /// No description provided for @collectNotInstalled.
  ///
  /// In ko, this message translates to:
  /// **'미설치 — {bin} 명령이 없습니다'**
  String collectNotInstalled(String bin);

  /// No description provided for @collectNotConnected.
  ///
  /// In ko, this message translates to:
  /// **'연결 안 됨'**
  String get collectNotConnected;

  /// No description provided for @collectOff.
  ///
  /// In ko, this message translates to:
  /// **'꺼짐'**
  String get collectOff;

  /// No description provided for @collectSyncFailed.
  ///
  /// In ko, this message translates to:
  /// **'동기화 실패'**
  String get collectSyncFailed;

  /// No description provided for @collectConnected.
  ///
  /// In ko, this message translates to:
  /// **'연결됨'**
  String get collectConnected;

  /// No description provided for @collectSyncedAgo.
  ///
  /// In ko, this message translates to:
  /// **'동기화 {ago}'**
  String collectSyncedAgo(String ago);

  /// No description provided for @collectChunks.
  ///
  /// In ko, this message translates to:
  /// **'조각 {count}개'**
  String collectChunks(int count);

  /// No description provided for @collectNeverSynced.
  ///
  /// In ko, this message translates to:
  /// **'아직 동기화 안 함'**
  String get collectNeverSynced;

  /// No description provided for @collectOutbound.
  ///
  /// In ko, this message translates to:
  /// **'밖으로 나가는 것: {what}'**
  String collectOutbound(String what);

  /// No description provided for @collectAuth.
  ///
  /// In ko, this message translates to:
  /// **'로그인·토큰: {what}'**
  String collectAuth(String what);

  /// No description provided for @collectNeedsTool.
  ///
  /// In ko, this message translates to:
  /// **'{bin} 도구가 필요합니다. 설치하면 이 앱 안의 폴더(~/.zaevis/ext)에 들어가고, 관리자 권한은 필요 없습니다.'**
  String collectNeedsTool(String bin);

  /// No description provided for @collectInstallBin.
  ///
  /// In ko, this message translates to:
  /// **'{bin} 설치'**
  String collectInstallBin(String bin);

  /// No description provided for @collectInstallFirst.
  ///
  /// In ko, this message translates to:
  /// **'먼저 터미널에서 설치하고 로그인·수집을 한 번 해 두세요:'**
  String get collectInstallFirst;

  /// No description provided for @collectInstallCopied.
  ///
  /// In ko, this message translates to:
  /// **'설치 명령을 복사했습니다'**
  String get collectInstallCopied;

  /// No description provided for @collectCopyInstall.
  ///
  /// In ko, this message translates to:
  /// **'설치 명령 복사'**
  String get collectCopyInstall;

  /// No description provided for @collectNoArchive.
  ///
  /// In ko, this message translates to:
  /// **'{bin}의 아카이브가 아직 없습니다. 먼저 {bin}으로 로그인·수집을 한 번 하세요.'**
  String collectNoArchive(String bin);

  /// No description provided for @collectEnvHelper.
  ///
  /// In ko, this message translates to:
  /// **'환경 변수 이름. 값은 아래 칸에'**
  String get collectEnvHelper;

  /// No description provided for @collectTokenLabel.
  ///
  /// In ko, this message translates to:
  /// **'토큰 값 ({name})'**
  String collectTokenLabel(String name);

  /// No description provided for @collectTokenHelper.
  ///
  /// In ko, this message translates to:
  /// **'~/.zaevis/secrets.json(소유자만 읽기)에 저장되고 검색 프로세스에만 전달됩니다. 다시 표시되지 않습니다.'**
  String get collectTokenHelper;

  /// No description provided for @collectNoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'메모 (선택)'**
  String get collectNoteLabel;

  /// No description provided for @collectNoteHelper.
  ///
  /// In ko, this message translates to:
  /// **'이 연결이 무엇인지. 질문 모드의 에이전트에게도 보입니다.'**
  String get collectNoteHelper;

  /// No description provided for @collectConnect.
  ///
  /// In ko, this message translates to:
  /// **'연결'**
  String get collectConnect;

  /// No description provided for @collectSyncNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 동기화'**
  String get collectSyncNow;

  /// No description provided for @collectRemoveConnection.
  ///
  /// In ko, this message translates to:
  /// **'연결 삭제'**
  String get collectRemoveConnection;

  /// No description provided for @collectPresetFolder.
  ///
  /// In ko, this message translates to:
  /// **'폴더의 노트 (Markdown·텍스트)'**
  String get collectPresetFolder;

  /// No description provided for @collectPresetFolderHint.
  ///
  /// In ko, this message translates to:
  /// **'폴더 안에서 수집 구간에 수정된 .md/.txt 파일을 통째로 가져옵니다. Obsidian 볼트, 메모 폴더에 맞습니다.'**
  String get collectPresetFolderHint;

  /// No description provided for @collectPresetCalendar.
  ///
  /// In ko, this message translates to:
  /// **'macOS 캘린더 일정'**
  String get collectPresetCalendar;

  /// No description provided for @collectPresetCalendarHint.
  ///
  /// In ko, this message translates to:
  /// **'수집 구간의 캘린더 일정을 제목·시간·참석자와 함께 가져옵니다.'**
  String get collectPresetCalendarHint;

  /// No description provided for @collectPresetCustom.
  ///
  /// In ko, this message translates to:
  /// **'직접 입력'**
  String get collectPresetCustom;

  /// No description provided for @collectPresetCustomHint.
  ///
  /// In ko, this message translates to:
  /// **'Markdown을 출력하는 아무 명령. 스크립트, curl, 사내 CLI…'**
  String get collectPresetCustomHint;

  /// No description provided for @collectStep1.
  ///
  /// In ko, this message translates to:
  /// **'1. 무엇을 모을지 고르세요'**
  String get collectStep1;

  /// No description provided for @collectRequires.
  ///
  /// In ko, this message translates to:
  /// **'필요: {what}'**
  String collectRequires(String what);

  /// No description provided for @collectStep2.
  ///
  /// In ko, this message translates to:
  /// **'2. 확인하고 고치세요'**
  String get collectStep2;

  /// No description provided for @collectNameLabel.
  ///
  /// In ko, this message translates to:
  /// **'이름 (영문 소문자·숫자·-)'**
  String get collectNameLabel;

  /// No description provided for @collectCommandLabel.
  ///
  /// In ko, this message translates to:
  /// **'명령'**
  String get collectCommandLabel;

  /// No description provided for @collectNotesFolderHelper.
  ///
  /// In ko, this message translates to:
  /// **'~/Notes 를 실제 폴더로 바꾸세요'**
  String get collectNotesFolderHelper;

  /// No description provided for @collectDescLabel.
  ///
  /// In ko, this message translates to:
  /// **'설명 (선택)'**
  String get collectDescLabel;

  /// No description provided for @collectPlaceholderHelp.
  ///
  /// In ko, this message translates to:
  /// **'명령 안의 자리표시자는 수집 때 바뀝니다:\n  {dates}  →  2026-10-20  (날짜만)\n  {times}  →  2026-10-20T00:00:00.000Z  (ISO 시각)\n출력을 날짜별로 나누려면 줄 사이에 {marker} 를 넣으세요. 없으면 수집한 날의 기록이 됩니다.\n추가하면 바로 한 번 수집해 결과를 카드에 보여 줍니다.'**
  String collectPlaceholderHelp(String dates, String times, String marker);

  /// No description provided for @collectNeedNameCommand.
  ///
  /// In ko, this message translates to:
  /// **'이름과 명령을 채워 주세요'**
  String get collectNeedNameCommand;

  /// No description provided for @collectAddAndCollect.
  ///
  /// In ko, this message translates to:
  /// **'추가하고 수집'**
  String get collectAddAndCollect;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In ko, this message translates to:
  /// **'일반'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsSectionRecording.
  ///
  /// In ko, this message translates to:
  /// **'녹음'**
  String get settingsSectionRecording;

  /// No description provided for @settingsSectionDigest.
  ///
  /// In ko, this message translates to:
  /// **'정리'**
  String get settingsSectionDigest;

  /// No description provided for @settingsSectionCollect.
  ///
  /// In ko, this message translates to:
  /// **'수집'**
  String get settingsSectionCollect;

  /// No description provided for @settingsSectionShortcuts.
  ///
  /// In ko, this message translates to:
  /// **'단축키'**
  String get settingsSectionShortcuts;

  /// No description provided for @settingsSectionAdvanced.
  ///
  /// In ko, this message translates to:
  /// **'고급'**
  String get settingsSectionAdvanced;

  /// No description provided for @settingsKiwiInstallTask.
  ///
  /// In ko, this message translates to:
  /// **'한국어 형태소 분석 (Kiwi) 설치'**
  String get settingsKiwiInstallTask;

  /// No description provided for @settingsKiwiReindexTitle.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시 색인할까요?'**
  String get settingsKiwiReindexTitle;

  /// No description provided for @settingsKiwiReindexBody.
  ///
  /// In ko, this message translates to:
  /// **'Kiwi를 설치했습니다. 지금 있는 색인은 공백 기준으로 만든 것이라, 처음부터 다시 색인해야 조사·어미가 붙은 말도 찾습니다. 몇 분 걸리고, 창을 닫아도 계속됩니다.'**
  String get settingsKiwiReindexBody;

  /// No description provided for @settingsLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get settingsLater;

  /// No description provided for @settingsReindex.
  ///
  /// In ko, this message translates to:
  /// **'다시 색인'**
  String get settingsReindex;

  /// No description provided for @settingsReindexStarted.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시 색인을 시작했습니다'**
  String get settingsReindexStarted;

  /// No description provided for @settingsMemoryAdded.
  ///
  /// In ko, this message translates to:
  /// **'폴더를 색인에 넣었습니다. 처음부터 다시 색인합니다.'**
  String get settingsMemoryAdded;

  /// No description provided for @settingsMemoryDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'색인할 폴더'**
  String get settingsMemoryDialogTitle;

  /// No description provided for @settingsMemoryPathLabel.
  ///
  /// In ko, this message translates to:
  /// **'폴더 경로'**
  String get settingsMemoryPathLabel;

  /// No description provided for @settingsAbout.
  ///
  /// In ko, this message translates to:
  /// **'앱 정보'**
  String get settingsAbout;

  /// No description provided for @settingsDisplay.
  ///
  /// In ko, this message translates to:
  /// **'화면'**
  String get settingsDisplay;

  /// No description provided for @settingsTheme.
  ///
  /// In ko, this message translates to:
  /// **'테마'**
  String get settingsTheme;

  /// No description provided for @settingsThemeHint.
  ///
  /// In ko, this message translates to:
  /// **'시스템을 고르면 macOS·Windows의 밝게/어둡게 설정을 따릅니다.'**
  String get settingsThemeHint;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ko, this message translates to:
  /// **'밝게'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ko, this message translates to:
  /// **'어둡게'**
  String get settingsThemeDark;

  /// No description provided for @settingsTextScale.
  ///
  /// In ko, this message translates to:
  /// **'글자 크기'**
  String get settingsTextScale;

  /// No description provided for @settingsTextScaleHint.
  ///
  /// In ko, this message translates to:
  /// **'앱 전체 글자를 {percent}%로 보여 줍니다.'**
  String settingsTextScaleHint(int percent);

  /// No description provided for @settingsGroupLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get settingsGroupLanguage;

  /// No description provided for @settingsUserLanguage.
  ///
  /// In ko, this message translates to:
  /// **'주로 쓰는 언어'**
  String get settingsUserLanguage;

  /// No description provided for @settingsUserLanguageHint.
  ///
  /// In ko, this message translates to:
  /// **'처음 시작할 때 고른 언어입니다. 녹음 전사가 기본으로 이 언어를 씁니다.'**
  String get settingsUserLanguageHint;

  /// No description provided for @settingsTranscribeLanguage.
  ///
  /// In ko, this message translates to:
  /// **'전사 언어'**
  String get settingsTranscribeLanguage;

  /// No description provided for @settingsTranscribeUser.
  ///
  /// In ko, this message translates to:
  /// **'주로 쓰는 언어({language})로 전사합니다. 일반에서 바꾸면 따라갑니다.'**
  String settingsTranscribeUser(String language);

  /// No description provided for @settingsTranscribeAuto.
  ///
  /// In ko, this message translates to:
  /// **'녹음 앞부분으로 언어를 알아냅니다. 여러 언어 녹음에 맞지만, 다른 언어 낱말이 많이 섞이면 잘못 고를 수 있습니다.'**
  String get settingsTranscribeAuto;

  /// No description provided for @settingsTranscribeFixed.
  ///
  /// In ko, this message translates to:
  /// **'항상 {language}로 전사합니다.'**
  String settingsTranscribeFixed(String language);

  /// No description provided for @settingsTranscribeMine.
  ///
  /// In ko, this message translates to:
  /// **'내 언어 ({language})'**
  String settingsTranscribeMine(String language);

  /// No description provided for @settingsAutoDetect.
  ///
  /// In ko, this message translates to:
  /// **'자동 감지'**
  String get settingsAutoDetect;

  /// No description provided for @settingsNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get settingsNotifications;

  /// No description provided for @settingsSystemNotifications.
  ///
  /// In ko, this message translates to:
  /// **'시스템 알림'**
  String get settingsSystemNotifications;

  /// No description provided for @settingsSystemNotificationsHint.
  ///
  /// In ko, this message translates to:
  /// **'정리가 끝나 검토할 것이 생겼을 때, 수집이 실패했을 때, 녹음 전사가 끝났을 때 알립니다. 서버가 보내므로 앱 창이 닫혀 있어도 옵니다.'**
  String get settingsSystemNotificationsHint;

  /// No description provided for @settingsVersion.
  ///
  /// In ko, this message translates to:
  /// **'버전'**
  String get settingsVersion;

  /// No description provided for @settingsNotInstalledBuild.
  ///
  /// In ko, this message translates to:
  /// **'설치본이 아닙니다 (개발 실행이나 웹)'**
  String get settingsNotInstalledBuild;

  /// No description provided for @settingsNoVersionInfo.
  ///
  /// In ko, this message translates to:
  /// **'버전 정보 없음'**
  String get settingsNoVersionInfo;

  /// No description provided for @settingsBuiltOn.
  ///
  /// In ko, this message translates to:
  /// **'{date} 빌드'**
  String settingsBuiltOn(String date);

  /// No description provided for @settingsInstalledOn.
  ///
  /// In ko, this message translates to:
  /// **'설치한 날'**
  String get settingsInstalledOn;

  /// No description provided for @settingsInstalledOnHint.
  ///
  /// In ko, this message translates to:
  /// **'이 버전을 이 컴퓨터에서 처음 연 때'**
  String get settingsInstalledOnHint;

  /// No description provided for @settingsTranscription.
  ///
  /// In ko, this message translates to:
  /// **'전사'**
  String get settingsTranscription;

  /// No description provided for @settingsWhisperx.
  ///
  /// In ko, this message translates to:
  /// **'whisperX (녹음 전사)'**
  String get settingsWhisperx;

  /// No description provided for @settingsInstalled.
  ///
  /// In ko, this message translates to:
  /// **'설치됨'**
  String get settingsInstalled;

  /// No description provided for @settingsWhisperxInstallHint.
  ///
  /// In ko, this message translates to:
  /// **'설치하면 녹음을 올릴 때 자동으로 전사합니다 (1~2GB 다운로드)'**
  String get settingsWhisperxInstallHint;

  /// No description provided for @settingsWhisperxMissing.
  ///
  /// In ko, this message translates to:
  /// **'설치되지 않음 — 터미널에서 \'zaevis ext install whisperx\''**
  String get settingsWhisperxMissing;

  /// No description provided for @settingsWhisperxInstallTask.
  ///
  /// In ko, this message translates to:
  /// **'whisperX 설치'**
  String get settingsWhisperxInstallTask;

  /// No description provided for @settingsInstall.
  ///
  /// In ko, this message translates to:
  /// **'설치'**
  String get settingsInstall;

  /// No description provided for @settingsFastTranscribe.
  ///
  /// In ko, this message translates to:
  /// **'빠르게 전사'**
  String get settingsFastTranscribe;

  /// No description provided for @settingsFastTranscribeHint.
  ///
  /// In ko, this message translates to:
  /// **'끄면 CPU 4코어만 써서 팬 소리가 작습니다. 켜면 모든 코어를 써서 약 1.4배 빠르지만 팬이 세게 돕니다.'**
  String get settingsFastTranscribeHint;

  /// No description provided for @settingsSpeakers.
  ///
  /// In ko, this message translates to:
  /// **'화자'**
  String get settingsSpeakers;

  /// No description provided for @settingsIndex.
  ///
  /// In ko, this message translates to:
  /// **'색인'**
  String get settingsIndex;

  /// No description provided for @settingsIndexOnInject.
  ///
  /// In ko, this message translates to:
  /// **'넣자마자 색인'**
  String get settingsIndexOnInject;

  /// No description provided for @settingsIndexOnInjectHint.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록이나 전사본을 넣으면 바로 검색 색인을 갱신합니다. 끄면 예약·수동 색인 때만 반영됩니다.'**
  String get settingsIndexOnInjectHint;

  /// No description provided for @settingsLocalEmbedding.
  ///
  /// In ko, this message translates to:
  /// **'의미 검색 (로컬 임베딩)'**
  String get settingsLocalEmbedding;

  /// No description provided for @settingsLocalEmbeddingHint.
  ///
  /// In ko, this message translates to:
  /// **'이 맥에서 Qwen3-Embedding 모델을 돌려 뜻이 비슷한 기록도 찾습니다. 외부 서비스나 키는 쓰지 않습니다. 처음 켤 때 모델(1.1GB)을 내려받고 색인을 다시 만듭니다. 끄면 키워드 검색만 합니다.'**
  String get settingsLocalEmbeddingHint;

  /// No description provided for @settingsMemoryFolders.
  ///
  /// In ko, this message translates to:
  /// **'색인 폴더'**
  String get settingsMemoryFolders;

  /// No description provided for @settingsMemoryFoldersHint.
  ///
  /// In ko, this message translates to:
  /// **'기록 폴더는 항상 색인됩니다. 노트가 다른 폴더에 있으면 추가하세요. 추가하거나 빼면 처음부터 다시 색인합니다.'**
  String get settingsMemoryFoldersHint;

  /// No description provided for @settingsWorklogFolder.
  ///
  /// In ko, this message translates to:
  /// **'기록 폴더'**
  String get settingsWorklogFolder;

  /// No description provided for @settingsRemove.
  ///
  /// In ko, this message translates to:
  /// **'빼기'**
  String get settingsRemove;

  /// No description provided for @settingsAddFolder.
  ///
  /// In ko, this message translates to:
  /// **'폴더 추가'**
  String get settingsAddFolder;

  /// No description provided for @settingsExternal.
  ///
  /// In ko, this message translates to:
  /// **'외부 서비스'**
  String get settingsExternal;

  /// No description provided for @settingsScheduleUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'이 OS에서는 자동 예약을 지원하지 않습니다.'**
  String get settingsScheduleUnsupported;

  /// No description provided for @settingsScheduleNone.
  ///
  /// In ko, this message translates to:
  /// **'예약 없음 — 시각을 저장하면 등록됩니다.'**
  String get settingsScheduleNone;

  /// No description provided for @settingsScheduleRunning.
  ///
  /// In ko, this message translates to:
  /// **'매일 {time} 실행 중 (맥이 잠자기였으면 깨어날 때 실행)'**
  String settingsScheduleRunning(String time);

  /// No description provided for @settingsScheduleNotLoaded.
  ///
  /// In ko, this message translates to:
  /// **'등록됐지만 아직 로드되지 않음'**
  String get settingsScheduleNotLoaded;

  /// No description provided for @settingsDaily.
  ///
  /// In ko, this message translates to:
  /// **'매일 수집'**
  String get settingsDaily;

  /// No description provided for @settingsDailyAt.
  ///
  /// In ko, this message translates to:
  /// **'실행 시각 {time}'**
  String settingsDailyAt(String time);

  /// No description provided for @settingsLastRun.
  ///
  /// In ko, this message translates to:
  /// **'마지막 실행'**
  String get settingsLastRun;

  /// No description provided for @settingsDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본값'**
  String get settingsDefault;

  /// No description provided for @settingsServer.
  ///
  /// In ko, this message translates to:
  /// **'서버'**
  String get settingsServer;

  /// No description provided for @settingsServerHint.
  ///
  /// In ko, this message translates to:
  /// **'앱이 이야기하는 zaevis 서버입니다. 보통은 바꿀 일이 없습니다.'**
  String get settingsServerHint;

  /// No description provided for @settingsServerAddress.
  ///
  /// In ko, this message translates to:
  /// **'서버 주소'**
  String get settingsServerAddress;

  /// No description provided for @settingsApply.
  ///
  /// In ko, this message translates to:
  /// **'적용'**
  String get settingsApply;

  /// No description provided for @settingsThisComputer.
  ///
  /// In ko, this message translates to:
  /// **'이 컴퓨터'**
  String get settingsThisComputer;

  /// No description provided for @settingsOpenInBrowser.
  ///
  /// In ko, this message translates to:
  /// **'브라우저로 열기'**
  String get settingsOpenInBrowser;

  /// No description provided for @settingsInstallCli.
  ///
  /// In ko, this message translates to:
  /// **'터미널에서 zaevis 명령 쓰기'**
  String get settingsInstallCli;

  /// No description provided for @settingsInstallCliHint.
  ///
  /// In ko, this message translates to:
  /// **'~/.local/bin 에 zaevis 명령을 등록합니다'**
  String get settingsInstallCliHint;

  /// No description provided for @settingsInstallCliTask.
  ///
  /// In ko, this message translates to:
  /// **'zaevis 명령 등록'**
  String get settingsInstallCliTask;

  /// No description provided for @settingsRestartServer.
  ///
  /// In ko, this message translates to:
  /// **'서버 다시 시작'**
  String get settingsRestartServer;

  /// No description provided for @settingsOpenLogs.
  ///
  /// In ko, this message translates to:
  /// **'로그 폴더 열기'**
  String get settingsOpenLogs;

  /// No description provided for @settingsDate.
  ///
  /// In ko, this message translates to:
  /// **'{year}년 {month}월 {day}일'**
  String settingsDate(int year, int month, int day);

  /// No description provided for @settingsUpdateDownloading.
  ///
  /// In ko, this message translates to:
  /// **'받는 중 {percent}%'**
  String settingsUpdateDownloading(int percent);

  /// No description provided for @settingsUpdateInstalling.
  ///
  /// In ko, this message translates to:
  /// **'설치하고 다시 여는 중…'**
  String get settingsUpdateInstalling;

  /// No description provided for @settingsUpdateChecking.
  ///
  /// In ko, this message translates to:
  /// **'새 버전을 확인하는 중…'**
  String get settingsUpdateChecking;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 있습니다: {version}'**
  String settingsUpdateAvailable(String version);

  /// No description provided for @settingsUpdateAvailableBuilt.
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 있습니다: {version} ({date} 빌드)'**
  String settingsUpdateAvailableBuilt(String version, String date);

  /// No description provided for @settingsUpdate.
  ///
  /// In ko, this message translates to:
  /// **'업데이트'**
  String get settingsUpdate;

  /// No description provided for @settingsUpdateNoAsset.
  ///
  /// In ko, this message translates to:
  /// **'이 기종용 설치 파일이 없습니다'**
  String get settingsUpdateNoAsset;

  /// No description provided for @settingsUpdateCheckFailed.
  ///
  /// In ko, this message translates to:
  /// **'확인하지 못했습니다: {error}'**
  String settingsUpdateCheckFailed(String error);

  /// No description provided for @settingsCheckAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 확인'**
  String get settingsCheckAgain;

  /// No description provided for @settingsUpdateNotChecked.
  ///
  /// In ko, this message translates to:
  /// **'아직 확인하지 않았습니다'**
  String get settingsUpdateNotChecked;

  /// No description provided for @settingsUpToDate.
  ///
  /// In ko, this message translates to:
  /// **'최신 버전입니다 · {time} 확인'**
  String settingsUpToDate(String time);

  /// No description provided for @settingsCheckUpdate.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 확인'**
  String get settingsCheckUpdate;

  /// No description provided for @settingsKiwiNoRelease.
  ///
  /// In ko, this message translates to:
  /// **'이 플랫폼용 Kiwi 릴리스가 없습니다. 직접 받아 {path}에 두거나 KIWI_LIBRARY_PATH·KIWI_MODEL_PATH를 설정하세요.'**
  String settingsKiwiNoRelease(String path);

  /// No description provided for @settingsKiwiInstallHint.
  ///
  /// In ko, this message translates to:
  /// **'설치하면 조사·어미가 붙은 말(인증서를)도 검색어(인증서)로 찾습니다. 키워드 검색이 한국어 형태소 단위가 됩니다 ({mb}MB 다운로드, 설치 뒤 처음부터 다시 색인).'**
  String settingsKiwiInstallHint(int mb);

  /// No description provided for @settingsKiwiMissing.
  ///
  /// In ko, this message translates to:
  /// **'설치되지 않음 — 터미널에서 \'zaevis ext install kiwi\' 뒤 처음부터 다시 색인'**
  String get settingsKiwiMissing;

  /// No description provided for @settingsKiwiTitle.
  ///
  /// In ko, this message translates to:
  /// **'한국어 형태소 분석 (Kiwi)'**
  String get settingsKiwiTitle;

  /// No description provided for @settingsRerankTitle.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과 재정렬 (OpenRouter)'**
  String get settingsRerankTitle;

  /// No description provided for @settingsRerankOn.
  ///
  /// In ko, this message translates to:
  /// **'검색 상위 25개 문단을 OpenRouter의 {model} 모델로 다시 정렬합니다. 켜면 검색어와 그 문단이 외부로 나갑니다.'**
  String settingsRerankOn(String model);

  /// No description provided for @settingsRerankNoKey.
  ///
  /// In ko, this message translates to:
  /// **'켜려면 아래에 OpenRouter API 키를 저장하세요. 키가 없으면 켜도 아무것도 전송되지 않습니다.'**
  String get settingsRerankNoKey;

  /// No description provided for @settingsRerankEnabled.
  ///
  /// In ko, this message translates to:
  /// **'재정렬을 켰습니다'**
  String get settingsRerankEnabled;

  /// No description provided for @settingsRerankNoKeySent.
  ///
  /// In ko, this message translates to:
  /// **'켰지만 키가 없어 전송되지 않습니다'**
  String get settingsRerankNoKeySent;

  /// No description provided for @settingsRerankDisabled.
  ///
  /// In ko, this message translates to:
  /// **'재정렬을 껐습니다'**
  String get settingsRerankDisabled;

  /// No description provided for @settingsRerankKey.
  ///
  /// In ko, this message translates to:
  /// **'OpenRouter API 키'**
  String get settingsRerankKey;

  /// No description provided for @settingsRerankKeySaved.
  ///
  /// In ko, this message translates to:
  /// **'저장됨 •••• {hint}'**
  String settingsRerankKeySaved(String hint);

  /// No description provided for @settingsRerankKeyHelper.
  ///
  /// In ko, this message translates to:
  /// **'새 키를 넣고 저장하면 바뀝니다. 키는 ~/.zaevis/secrets.json(소유자만 읽기)에만 저장됩니다.'**
  String get settingsRerankKeyHelper;

  /// No description provided for @settingsKeySaved.
  ///
  /// In ko, this message translates to:
  /// **'키를 저장했습니다'**
  String get settingsKeySaved;

  /// No description provided for @settingsTestConnection.
  ///
  /// In ko, this message translates to:
  /// **'연결 확인'**
  String get settingsTestConnection;

  /// No description provided for @settingsKeyCleared.
  ///
  /// In ko, this message translates to:
  /// **'키를 지웠습니다'**
  String get settingsKeyCleared;

  /// No description provided for @settingsDeleteKey.
  ///
  /// In ko, this message translates to:
  /// **'키 삭제'**
  String get settingsDeleteKey;

  /// No description provided for @settingsRerankExternal.
  ///
  /// In ko, this message translates to:
  /// **'지금 외부로 나가는 요청: {requests}'**
  String settingsRerankExternal(String requests);

  /// No description provided for @settingsDigestStarted.
  ///
  /// In ko, this message translates to:
  /// **'정리를 시작했습니다. 몇 분 걸립니다.'**
  String get settingsDigestStarted;

  /// No description provided for @settingsAgentAuto.
  ///
  /// In ko, this message translates to:
  /// **'자동 (할당량이면 다음 서비스)'**
  String get settingsAgentAuto;

  /// No description provided for @settingsQuotaSkipped.
  ///
  /// In ko, this message translates to:
  /// **'{names} 할당량으로 건너뜀'**
  String settingsQuotaSkipped(String names);

  /// No description provided for @settingsAgentOrder.
  ///
  /// In ko, this message translates to:
  /// **'에이전트 순서'**
  String get settingsAgentOrder;

  /// No description provided for @settingsAgentOrderHint.
  ///
  /// In ko, this message translates to:
  /// **'inbox의 전사본·세션 노트와 매일 수집한 원본을 읽어 로그 줄·프로젝트 상태·월간 정리를 씁니다. 블록을 왼쪽부터 시도하고, 할당량으로 막히면 다음 블록으로 넘깁니다. 끌어다 놓아 순서를 바꿉니다.'**
  String get settingsAgentOrderHint;

  /// No description provided for @settingsOpenRouterModel.
  ///
  /// In ko, this message translates to:
  /// **'OpenRouter 모델'**
  String get settingsOpenRouterModel;

  /// No description provided for @settingsRun.
  ///
  /// In ko, this message translates to:
  /// **'실행'**
  String get settingsRun;

  /// No description provided for @settingsReviewFirst.
  ///
  /// In ko, this message translates to:
  /// **'적용 전에 검토'**
  String get settingsReviewFirst;

  /// No description provided for @settingsReviewOn.
  ///
  /// In ko, this message translates to:
  /// **'정리 결과를 바로 쓰지 않고 제안으로 둡니다. 로그 탭이나 아래에서 줄마다 골라 적용합니다.'**
  String get settingsReviewOn;

  /// No description provided for @settingsReviewOff.
  ///
  /// In ko, this message translates to:
  /// **'끄면 에이전트가 쓴 내용이 바로 worklog에 들어갑니다.'**
  String get settingsReviewOff;

  /// No description provided for @settingsWeekly.
  ///
  /// In ko, this message translates to:
  /// **'매주 월요일 자동 정리'**
  String get settingsWeekly;

  /// No description provided for @settingsWeeklyNext.
  ///
  /// In ko, this message translates to:
  /// **'다음 실행: {next} (매일 수집 뒤에 이어서)'**
  String settingsWeeklyNext(String next);

  /// No description provided for @settingsNextMonday.
  ///
  /// In ko, this message translates to:
  /// **'다음 월요일'**
  String get settingsNextMonday;

  /// No description provided for @settingsWeeklyOff.
  ///
  /// In ko, this message translates to:
  /// **'끄면 아래 버튼으로만 실행합니다'**
  String get settingsWeeklyOff;

  /// No description provided for @settingsDigestRunning.
  ///
  /// In ko, this message translates to:
  /// **'정리 중… ({agent})'**
  String settingsDigestRunning(String agent);

  /// No description provided for @settingsDigestNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 정리하기'**
  String get settingsDigestNow;

  /// No description provided for @settingsNoAgent.
  ///
  /// In ko, this message translates to:
  /// **'쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI를 설치하거나 검색 → 외부 서비스에서 OpenRouter 키를 저장하세요.'**
  String get settingsNoAgent;

  /// No description provided for @settingsDigestBy.
  ///
  /// In ko, this message translates to:
  /// **'{agent}가 정리합니다. 몇 분 걸립니다.'**
  String settingsDigestBy(String agent);

  /// No description provided for @settingsPendingReviews.
  ///
  /// In ko, this message translates to:
  /// **'검토 대기 {count}건'**
  String settingsPendingReviews(int count);

  /// No description provided for @settingsProposalCounts.
  ///
  /// In ko, this message translates to:
  /// **'로그 {lines}줄 · 프로젝트 {projects}개 · 월간 정리 {summaries}개 · inbox {processed}개'**
  String settingsProposalCounts(
      int lines, int projects, int summaries, int processed);

  /// No description provided for @settingsReview.
  ///
  /// In ko, this message translates to:
  /// **'검토하기'**
  String get settingsReview;

  /// No description provided for @settingsLastDigest.
  ///
  /// In ko, this message translates to:
  /// **'마지막 정리'**
  String get settingsLastDigest;

  /// No description provided for @settingsStatusPendingReview.
  ///
  /// In ko, this message translates to:
  /// **'검토 대기'**
  String get settingsStatusPendingReview;

  /// No description provided for @settingsInUse.
  ///
  /// In ko, this message translates to:
  /// **'사용'**
  String get settingsInUse;

  /// No description provided for @settingsIncluded.
  ///
  /// In ko, this message translates to:
  /// **'순서에 포함'**
  String get settingsIncluded;

  /// No description provided for @settingsSkipped.
  ///
  /// In ko, this message translates to:
  /// **'건너뜀'**
  String get settingsSkipped;

  /// No description provided for @settingsHotkeyTitle.
  ///
  /// In ko, this message translates to:
  /// **'전역 단축키 바꾸기'**
  String get settingsHotkeyTitle;

  /// No description provided for @settingsHotkeyHint.
  ///
  /// In ko, this message translates to:
  /// **'쓰고 싶은 조합을 지금 누르세요. 수정키(⌘·⌃·⌥·⇧ 또는 Ctrl·Alt·Shift)와 글자·숫자·F키·Space를 조합합니다.'**
  String get settingsHotkeyHint;

  /// No description provided for @settingsHotkeyNeedsModifier.
  ///
  /// In ko, this message translates to:
  /// **'수정키와 함께 눌러야 합니다'**
  String get settingsHotkeyNeedsModifier;

  /// No description provided for @settingsHotkeyPress.
  ///
  /// In ko, this message translates to:
  /// **'여기에서 키를 누르세요'**
  String get settingsHotkeyPress;

  /// No description provided for @settingsHotkeyDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본값: {key}'**
  String settingsHotkeyDefault(String key);

  /// No description provided for @settingsSpeakersAfter.
  ///
  /// In ko, this message translates to:
  /// **'글이 먼저 저장되고, 말한 사람은 그 뒤에 같은 파일에 [A], [B]처럼 붙습니다. 원문 화면에서 이름을 바꿀 수 있습니다.'**
  String get settingsSpeakersAfter;

  /// No description provided for @settingsSpeakersNeedWhisperx.
  ///
  /// In ko, this message translates to:
  /// **'whisperX를 설치하면 쓸 수 있습니다. 계정은 필요 없습니다.'**
  String get settingsSpeakersNeedWhisperx;

  /// No description provided for @settingsSpeakersOff.
  ///
  /// In ko, this message translates to:
  /// **'꺼져 있습니다. 녹음 글만 저장합니다.'**
  String get settingsSpeakersOff;

  /// No description provided for @settingsSpeakersHf.
  ///
  /// In ko, this message translates to:
  /// **'Hugging Face pyannote 모델로 구분합니다. {after}'**
  String settingsSpeakersHf(String after);

  /// No description provided for @settingsSpeakersReady.
  ///
  /// In ko, this message translates to:
  /// **'계정 없이 이 맥에서 구분합니다. {after}'**
  String settingsSpeakersReady(String after);

  /// No description provided for @settingsSpeakersInstalling.
  ///
  /// In ko, this message translates to:
  /// **'화자 모델을 준비하는 중… (약 {mb}MB)'**
  String settingsSpeakersInstalling(int mb);

  /// No description provided for @settingsSpeakersFailed.
  ///
  /// In ko, this message translates to:
  /// **'화자 모델을 준비하지 못했습니다: {error}'**
  String settingsSpeakersFailed(String error);

  /// No description provided for @settingsUnknownError.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 오류'**
  String get settingsUnknownError;

  /// No description provided for @settingsSpeakersIdle.
  ///
  /// In ko, this message translates to:
  /// **'계정 없이 이 맥에서 구분합니다. 첫 녹음 때 화자 모델(약 {mb}MB)과 한국어 정렬 모델(약 1.2GB)을 한 번 받습니다.'**
  String settingsSpeakersIdle(int mb);

  /// No description provided for @settingsSpeakerLabel.
  ///
  /// In ko, this message translates to:
  /// **'화자 구분'**
  String get settingsSpeakerLabel;

  /// No description provided for @settingsPrepareAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 준비'**
  String get settingsPrepareAgain;

  /// No description provided for @settingsHfChecking.
  ///
  /// In ko, this message translates to:
  /// **'로그인 상태를 확인하는 중…'**
  String get settingsHfChecking;

  /// No description provided for @settingsHfCode.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 Hugging Face에 로그인하고 코드 {code} 를 확인하세요.'**
  String settingsHfCode(String code);

  /// No description provided for @settingsHfAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get settingsHfAccount;

  /// No description provided for @settingsHfNeedsAccept.
  ///
  /// In ko, this message translates to:
  /// **'{user} 으로 연결됨. 화자 모델을 쓰려면 페이지에서 사용에 동의해야 합니다.'**
  String settingsHfNeedsAccept(String user);

  /// No description provided for @settingsHfConnected.
  ///
  /// In ko, this message translates to:
  /// **'{user} 으로 연결됨. 녹음 글은 먼저 저장되고, 말한 사람은 그 뒤에 같은 파일에 붙습니다.'**
  String settingsHfConnected(String user);

  /// No description provided for @settingsHfHint.
  ///
  /// In ko, this message translates to:
  /// **'로그인하지 않아도 화자 구분은 됩니다. 로그인하고 모델 사용에 동의하면 pyannote 원본으로 구분합니다. 구분은 글이 저장된 뒤에 이어집니다.'**
  String get settingsHfHint;

  /// No description provided for @settingsHfTitle.
  ///
  /// In ko, this message translates to:
  /// **'Hugging Face 모델로 구분 (선택)'**
  String get settingsHfTitle;

  /// No description provided for @settingsHfAcceptPage.
  ///
  /// In ko, this message translates to:
  /// **'동의 페이지'**
  String get settingsHfAcceptPage;

  /// No description provided for @settingsDisconnect.
  ///
  /// In ko, this message translates to:
  /// **'연결 해제'**
  String get settingsDisconnect;

  /// No description provided for @settingsLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get settingsLogin;

  /// No description provided for @railTitle.
  ///
  /// In ko, this message translates to:
  /// **'서비스 순서'**
  String get railTitle;

  /// No description provided for @railRunning.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 작성 중'**
  String railRunning(String title);

  /// No description provided for @railWrote.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 작성'**
  String railWrote(String title);

  /// No description provided for @railQuota.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 할당량'**
  String railQuota(String title);

  /// No description provided for @railError.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 실패'**
  String railError(String title);

  /// No description provided for @railLogin.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 로그인'**
  String railLogin(String title);

  /// No description provided for @railMetered.
  ///
  /// In ko, this message translates to:
  /// **'{title} · 사용량'**
  String railMetered(String title);

  /// No description provided for @uiServerOffline.
  ///
  /// In ko, this message translates to:
  /// **'server 폴더에서 `npm start`로 서버를 실행했는지 확인하세요.'**
  String get uiServerOffline;

  /// No description provided for @uiTagDecision.
  ///
  /// In ko, this message translates to:
  /// **'결정'**
  String get uiTagDecision;

  /// No description provided for @uiTagBlocked.
  ///
  /// In ko, this message translates to:
  /// **'막힘'**
  String get uiTagBlocked;

  /// No description provided for @uiTagLearned.
  ///
  /// In ko, this message translates to:
  /// **'배움'**
  String get uiTagLearned;

  /// No description provided for @uiTaskFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패: {error}'**
  String uiTaskFailed(String error);

  /// No description provided for @uiDownloading.
  ///
  /// In ko, this message translates to:
  /// **'받는 중'**
  String get uiDownloading;

  /// No description provided for @uiTaskClose.
  ///
  /// In ko, this message translates to:
  /// **'{status} · 닫기'**
  String uiTaskClose(String status);

  /// No description provided for @uiWeakMatch.
  ///
  /// In ko, this message translates to:
  /// **'약한 일치'**
  String get uiWeakMatch;

  /// No description provided for @uiDownloadFile.
  ///
  /// In ko, this message translates to:
  /// **'파일 내려받기'**
  String get uiDownloadFile;

  /// No description provided for @uiSavedTo.
  ///
  /// In ko, this message translates to:
  /// **'저장했습니다: {path}'**
  String uiSavedTo(String path);

  /// No description provided for @uiSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했습니다: {error}'**
  String uiSaveFailed(String error);

  /// No description provided for @homeStarting.
  ///
  /// In ko, this message translates to:
  /// **'zaevis 준비 중…'**
  String get homeStarting;

  /// No description provided for @homeStartFailed.
  ///
  /// In ko, this message translates to:
  /// **'서버를 시작하지 못했습니다.\n{error}'**
  String homeStartFailed(String error);

  /// No description provided for @homeServerLog.
  ///
  /// In ko, this message translates to:
  /// **'로그: {path}'**
  String homeServerLog(String path);

  /// No description provided for @homeTabSearch.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get homeTabSearch;

  /// No description provided for @homeTabSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'기록을 찾고, 묻고, 파일을 내려받습니다'**
  String get homeTabSearchHint;

  /// No description provided for @homeTabMemory.
  ///
  /// In ko, this message translates to:
  /// **'메모리'**
  String get homeTabMemory;

  /// No description provided for @homeTabMemoryHint.
  ///
  /// In ko, this message translates to:
  /// **'기록 · 하루 · 프로젝트 상태 · 수집된 원본 — 이 앱이 아는 것 전부'**
  String get homeTabMemoryHint;

  /// No description provided for @homeTabReports.
  ///
  /// In ko, this message translates to:
  /// **'리포트'**
  String get homeTabReports;

  /// No description provided for @homeTabReportsHint.
  ///
  /// In ko, this message translates to:
  /// **'일간 · 주간 · 월간 리포트'**
  String get homeTabReportsHint;

  /// No description provided for @homeTabConnect.
  ///
  /// In ko, this message translates to:
  /// **'연결'**
  String get homeTabConnect;

  /// No description provided for @homeTabConnectHint.
  ///
  /// In ko, this message translates to:
  /// **'데이터소스와 외부 서비스 연결, inbox, 바로 넣기'**
  String get homeTabConnectHint;

  /// No description provided for @homeLogAdded.
  ///
  /// In ko, this message translates to:
  /// **'로그에 추가했습니다'**
  String get homeLogAdded;

  /// No description provided for @homeMenuSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정…'**
  String get homeMenuSettings;

  /// No description provided for @homeMenuLog.
  ///
  /// In ko, this message translates to:
  /// **'기록'**
  String get homeMenuLog;

  /// No description provided for @homeNewLog.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록'**
  String get homeNewLog;

  /// No description provided for @homeRecord.
  ///
  /// In ko, this message translates to:
  /// **'녹음'**
  String get homeRecord;

  /// No description provided for @homeMenuView.
  ///
  /// In ko, this message translates to:
  /// **'보기'**
  String get homeMenuView;

  /// No description provided for @homeSearchIndex.
  ///
  /// In ko, this message translates to:
  /// **'검색 색인'**
  String get homeSearchIndex;

  /// No description provided for @homeTagline.
  ///
  /// In ko, this message translates to:
  /// **'작업 기록 · 지식'**
  String get homeTagline;

  /// No description provided for @homeIndex.
  ///
  /// In ko, this message translates to:
  /// **'색인'**
  String get homeIndex;

  /// No description provided for @shortcutSearch.
  ///
  /// In ko, this message translates to:
  /// **'검색으로 이동해 입력'**
  String get shortcutSearch;

  /// No description provided for @shortcutNewLog.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록'**
  String get shortcutNewLog;

  /// No description provided for @shortcutRecord.
  ///
  /// In ko, this message translates to:
  /// **'녹음'**
  String get shortcutRecord;

  /// No description provided for @shortcutTabs.
  ///
  /// In ko, this message translates to:
  /// **'검색 · 메모리 · 리포트 · 연결 탭'**
  String get shortcutTabs;

  /// No description provided for @shortcutSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get shortcutSettings;

  /// No description provided for @shortcutGlobal.
  ///
  /// In ko, this message translates to:
  /// **'어디서든 창을 띄우고 한 줄 기록 (전역)'**
  String get shortcutGlobal;

  /// No description provided for @apiCannotConnect.
  ///
  /// In ko, this message translates to:
  /// **'서버에 연결할 수 없습니다: {url}'**
  String apiCannotConnect(String url);

  /// No description provided for @apiNotFound.
  ///
  /// In ko, this message translates to:
  /// **'찾을 수 없습니다'**
  String get apiNotFound;

  /// No description provided for @apiRequestFailed.
  ///
  /// In ko, this message translates to:
  /// **'요청이 실패했습니다'**
  String get apiRequestFailed;

  /// No description provided for @apiBadResponse.
  ///
  /// In ko, this message translates to:
  /// **'응답 형식이 올바르지 않습니다'**
  String get apiBadResponse;

  /// No description provided for @apiUploadFailed.
  ///
  /// In ko, this message translates to:
  /// **'업로드에 실패했습니다: {url}'**
  String apiUploadFailed(String url);

  /// No description provided for @apiSaveFileTitle.
  ///
  /// In ko, this message translates to:
  /// **'파일 저장'**
  String get apiSaveFileTitle;

  /// No description provided for @apiSaveUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'이 환경에서는 파일을 저장할 수 없습니다'**
  String get apiSaveUnsupported;

  /// No description provided for @updateAppNotInImage.
  ///
  /// In ko, this message translates to:
  /// **'이미지 안에서 zaevis.app을 찾지 못했습니다.'**
  String get updateAppNotInImage;

  /// No description provided for @updateReplaceFailed.
  ///
  /// In ko, this message translates to:
  /// **'앱을 교체하지 못했습니다.'**
  String get updateReplaceFailed;

  /// No description provided for @updateQuarantineFailed.
  ///
  /// In ko, this message translates to:
  /// **'격리 표시를 지우지 못했습니다. 터미널에서 실행하세요.'**
  String get updateQuarantineFailed;

  /// No description provided for @updateMountFailed.
  ///
  /// In ko, this message translates to:
  /// **'디스크 이미지를 열지 못했습니다.'**
  String get updateMountFailed;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In ko, this message translates to:
  /// **'설치 파일을 받지 못했습니다 ({status})'**
  String updateDownloadFailed(int status);

  /// No description provided for @updateGithubStatus.
  ///
  /// In ko, this message translates to:
  /// **'GitHub 응답 {status}'**
  String updateGithubStatus(int status);

  /// No description provided for @updateBadRelease.
  ///
  /// In ko, this message translates to:
  /// **'릴리스 정보를 읽지 못했습니다'**
  String get updateBadRelease;

  /// No description provided for @updateAvailable.
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 있습니다'**
  String get updateAvailable;

  /// No description provided for @updateButton.
  ///
  /// In ko, this message translates to:
  /// **'업데이트'**
  String get updateButton;

  /// No description provided for @updateDownloadingPercent.
  ///
  /// In ko, this message translates to:
  /// **'받는 중 {percent}%'**
  String updateDownloadingPercent(int percent);

  /// No description provided for @updateDownloading.
  ///
  /// In ko, this message translates to:
  /// **'받는 중'**
  String get updateDownloading;

  /// No description provided for @updateInstalling.
  ///
  /// In ko, this message translates to:
  /// **'설치하고 다시 여는 중…'**
  String get updateInstalling;

  /// No description provided for @updateNoInstaller.
  ///
  /// In ko, this message translates to:
  /// **'이 기종용 설치 파일이 없습니다'**
  String get updateNoInstaller;

  /// No description provided for @updateLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get updateLater;

  /// No description provided for @updateNotice.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get updateNotice;

  /// No description provided for @updateFolderTitle.
  ///
  /// In ko, this message translates to:
  /// **'매일 18:30에 폴더 접근을 묻습니다'**
  String get updateFolderTitle;

  /// No description provided for @updateFolderBody.
  ///
  /// In ko, this message translates to:
  /// **'데스크탑, 문서, 다운로드, 사진, 음악, 보관함을 저장소 탐색이 하나씩 열고 있습니다. 커밋을 모으는 데는 필요 없습니다.'**
  String get updateFolderBody;

  /// No description provided for @updateFolderApply.
  ///
  /// In ko, this message translates to:
  /// **'한 번에 빼기'**
  String get updateFolderApply;

  /// No description provided for @modelSourceGit.
  ///
  /// In ko, this message translates to:
  /// **'git 커밋'**
  String get modelSourceGit;

  /// No description provided for @modelSourceAgentSessions.
  ///
  /// In ko, this message translates to:
  /// **'에이전트 세션'**
  String get modelSourceAgentSessions;

  /// No description provided for @modelSourceClaudeCode.
  ///
  /// In ko, this message translates to:
  /// **'Claude Code 세션'**
  String get modelSourceClaudeCode;

  /// No description provided for @modelSourceShell.
  ///
  /// In ko, this message translates to:
  /// **'셸 명령'**
  String get modelSourceShell;

  /// No description provided for @modelSourceTranscripts.
  ///
  /// In ko, this message translates to:
  /// **'전사본'**
  String get modelSourceTranscripts;

  /// No description provided for @modelSourceSessionNotes.
  ///
  /// In ko, this message translates to:
  /// **'세션 노트'**
  String get modelSourceSessionNotes;

  /// No description provided for @modelTokenizerMorphemes.
  ///
  /// In ko, this message translates to:
  /// **'형태소 분석 (Kiwi) — 인증서를 → 인증서처럼 조사·어미가 붙은 말도 찾습니다'**
  String get modelTokenizerMorphemes;

  /// No description provided for @modelTokenizerNeedsReindex.
  ///
  /// In ko, this message translates to:
  /// **'Kiwi 설치됨 — 처음부터 다시 색인하면 형태소 분석이 켜집니다'**
  String get modelTokenizerNeedsReindex;

  /// No description provided for @modelTokenizerNextIndex.
  ///
  /// In ko, this message translates to:
  /// **'아직 색인 전 — 다음 색인부터 형태소 분석'**
  String get modelTokenizerNextIndex;

  /// No description provided for @modelTokenizerSimple.
  ///
  /// In ko, this message translates to:
  /// **'공백 기준 — 조사·어미가 붙은 말(인증서를)은 검색어(인증서)와 맞지 않습니다'**
  String get modelTokenizerSimple;

  /// No description provided for @modelEmbeddingReady.
  ///
  /// In ko, this message translates to:
  /// **'켜짐 — {model} ({device})'**
  String modelEmbeddingReady(String model, String device);

  /// No description provided for @modelEmbeddingLocalModel.
  ///
  /// In ko, this message translates to:
  /// **'로컬 모델'**
  String get modelEmbeddingLocalModel;

  /// No description provided for @modelEmbeddingStarting.
  ///
  /// In ko, this message translates to:
  /// **'시작 중… 처음에는 모델(1.1GB)을 내려받습니다'**
  String get modelEmbeddingStarting;

  /// No description provided for @modelEmbeddingFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패: {error}'**
  String modelEmbeddingFailed(String error);

  /// No description provided for @modelEmbeddingOff.
  ///
  /// In ko, this message translates to:
  /// **'꺼짐 — 키워드 검색만'**
  String get modelEmbeddingOff;

  /// No description provided for @modelEmbeddingUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'사용 불가 (minsync 없음)'**
  String get modelEmbeddingUnavailable;

  /// No description provided for @modelLoginNeeded.
  ///
  /// In ko, this message translates to:
  /// **'로그인 필요: {hint}'**
  String modelLoginNeeded(String hint);

  /// No description provided for @modelLoginInTerminal.
  ///
  /// In ko, this message translates to:
  /// **'터미널에서 로그인'**
  String get modelLoginInTerminal;

  /// No description provided for @modelProgressFiles.
  ///
  /// In ko, this message translates to:
  /// **'{scanned}/{total} 파일'**
  String modelProgressFiles(int scanned, int total);

  /// No description provided for @modelProgressChunks.
  ///
  /// In ko, this message translates to:
  /// **'{count}개'**
  String modelProgressChunks(int count);

  /// No description provided for @modelProgressParsed.
  ///
  /// In ko, this message translates to:
  /// **'본문 읽는 중'**
  String get modelProgressParsed;

  /// No description provided for @modelProgressEmbedding.
  ///
  /// In ko, this message translates to:
  /// **'임베딩·색인 중'**
  String get modelProgressEmbedding;

  /// No description provided for @modelProgressDatasources.
  ///
  /// In ko, this message translates to:
  /// **'커넥터 색인 중'**
  String get modelProgressDatasources;

  /// No description provided for @modelProgressKeywords.
  ///
  /// In ko, this message translates to:
  /// **'키워드 색인 정리 중'**
  String get modelProgressKeywords;

  /// No description provided for @modelProgressFileNames.
  ///
  /// In ko, this message translates to:
  /// **'파일 이름 색인 중'**
  String get modelProgressFileNames;

  /// No description provided for @modelProgressFinalizing.
  ///
  /// In ko, this message translates to:
  /// **'마무리 중'**
  String get modelProgressFinalizing;

  /// No description provided for @modelProgressPreparing.
  ///
  /// In ko, this message translates to:
  /// **'준비 중'**
  String get modelProgressPreparing;

  /// No description provided for @modelKindDaily.
  ///
  /// In ko, this message translates to:
  /// **'일간'**
  String get modelKindDaily;

  /// No description provided for @modelKindWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간'**
  String get modelKindWeekly;

  /// No description provided for @modelKindMonthly.
  ///
  /// In ko, this message translates to:
  /// **'월간'**
  String get modelKindMonthly;

  /// No description provided for @modelKindDailyWord.
  ///
  /// In ko, this message translates to:
  /// **'일간'**
  String get modelKindDailyWord;

  /// No description provided for @modelKindWeeklyWord.
  ///
  /// In ko, this message translates to:
  /// **'주간'**
  String get modelKindWeeklyWord;

  /// No description provided for @modelKindMonthlyWord.
  ///
  /// In ko, this message translates to:
  /// **'월간'**
  String get modelKindMonthlyWord;

  /// No description provided for @modelWeekdayMon.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get modelWeekdayMon;

  /// No description provided for @modelWeekdayTue.
  ///
  /// In ko, this message translates to:
  /// **'화'**
  String get modelWeekdayTue;

  /// No description provided for @modelWeekdayWed.
  ///
  /// In ko, this message translates to:
  /// **'수'**
  String get modelWeekdayWed;

  /// No description provided for @modelWeekdayThu.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get modelWeekdayThu;

  /// No description provided for @modelWeekdayFri.
  ///
  /// In ko, this message translates to:
  /// **'금'**
  String get modelWeekdayFri;

  /// No description provided for @modelWeekdaySat.
  ///
  /// In ko, this message translates to:
  /// **'토'**
  String get modelWeekdaySat;

  /// No description provided for @modelWeekdaySun.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get modelWeekdaySun;

  /// No description provided for @modelToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get modelToday;

  /// No description provided for @modelYesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get modelYesterday;

  /// No description provided for @modelThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get modelThisWeek;

  /// No description provided for @modelLastWeek.
  ///
  /// In ko, this message translates to:
  /// **'지난주'**
  String get modelLastWeek;

  /// No description provided for @modelThisMonth.
  ///
  /// In ko, this message translates to:
  /// **'이번 달'**
  String get modelThisMonth;

  /// No description provided for @modelLastMonth.
  ///
  /// In ko, this message translates to:
  /// **'지난달'**
  String get modelLastMonth;

  /// No description provided for @reportsNone.
  ///
  /// In ko, this message translates to:
  /// **'리포트가 없습니다'**
  String get reportsNone;

  /// No description provided for @reportsSettings.
  ///
  /// In ko, this message translates to:
  /// **'리포트 설정'**
  String get reportsSettings;

  /// No description provided for @reportsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 {kind} 리포트가 없습니다.\n\"지금 만들기\"로 바로 만들거나, 설정(⚙︎)에서 요일을 켜 두면 매일 수집 뒤 자동으로 만듭니다.'**
  String reportsEmpty(String kind);

  /// No description provided for @reportsPeriodNoService.
  ///
  /// In ko, this message translates to:
  /// **'{period} · 서비스 없음'**
  String reportsPeriodNoService(String period);

  /// No description provided for @reportsMakeNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 만들기'**
  String get reportsMakeNow;

  /// No description provided for @reportsNoServiceWas.
  ///
  /// In ko, this message translates to:
  /// **'사용 가능한 서비스가 없었습니다'**
  String get reportsNoServiceWas;

  /// No description provided for @reportsFailed.
  ///
  /// In ko, this message translates to:
  /// **'리포트를 만들지 못했습니다'**
  String get reportsFailed;

  /// No description provided for @reportsRemake.
  ///
  /// In ko, this message translates to:
  /// **'다시 만들기'**
  String get reportsRemake;

  /// No description provided for @reportsWrittenBy.
  ///
  /// In ko, this message translates to:
  /// **'리포트는 {agent}가 씁니다 · {detail}'**
  String reportsWrittenBy(String agent, String detail);

  /// No description provided for @reportsNoAgent.
  ///
  /// In ko, this message translates to:
  /// **'쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.'**
  String get reportsNoAgent;

  /// No description provided for @reportsRunning.
  ///
  /// In ko, this message translates to:
  /// **'{kind} 리포트 {period} 만드는 중… {agent} 수십 초에서 몇 분 걸립니다.'**
  String reportsRunning(String kind, String period, String agent);

  /// No description provided for @reportsNoService.
  ///
  /// In ko, this message translates to:
  /// **'사용 가능한 서비스 없음'**
  String get reportsNoService;

  /// No description provided for @reportsDigest.
  ///
  /// In ko, this message translates to:
  /// **'정리'**
  String get reportsDigest;

  /// No description provided for @reportsDaily.
  ///
  /// In ko, this message translates to:
  /// **'일간 리포트'**
  String get reportsDaily;

  /// No description provided for @reportsDailyHint.
  ///
  /// In ko, this message translates to:
  /// **'고른 요일의 하루를 그날 수집 뒤에 정리합니다 (아침에 돌면 전날).'**
  String get reportsDailyHint;

  /// No description provided for @reportsWeekdays.
  ///
  /// In ko, this message translates to:
  /// **'주중'**
  String get reportsWeekdays;

  /// No description provided for @reportsWeekend.
  ///
  /// In ko, this message translates to:
  /// **'주말'**
  String get reportsWeekend;

  /// No description provided for @reportsEveryday.
  ///
  /// In ko, this message translates to:
  /// **'매일'**
  String get reportsEveryday;

  /// No description provided for @reportsWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get reportsWeekly;

  /// No description provided for @reportsWeeklyHint.
  ///
  /// In ko, this message translates to:
  /// **'고른 요일에 그 전날이 든 주(월~일)를 정리합니다. 월요일이면 지난주.'**
  String get reportsWeeklyHint;

  /// No description provided for @reportsWeekdayName.
  ///
  /// In ko, this message translates to:
  /// **'{day}요일'**
  String reportsWeekdayName(String day);

  /// No description provided for @reportsMonthly.
  ///
  /// In ko, this message translates to:
  /// **'월간 리포트'**
  String get reportsMonthly;

  /// No description provided for @reportsMonthlyHint.
  ///
  /// In ko, this message translates to:
  /// **'매달 고른 날에 지난달을 정리합니다 (summaries/YYYY-MM.md, 월간 정리 자리).'**
  String get reportsMonthlyHint;

  /// No description provided for @reportsMonthDay.
  ///
  /// In ko, this message translates to:
  /// **'{day}일'**
  String reportsMonthDay(int day);

  /// No description provided for @recordPreparing.
  ///
  /// In ko, this message translates to:
  /// **'전사 준비 중'**
  String get recordPreparing;

  /// No description provided for @recordTranscribing.
  ///
  /// In ko, this message translates to:
  /// **'전사 중…'**
  String get recordTranscribing;

  /// No description provided for @recordMicDenied.
  ///
  /// In ko, this message translates to:
  /// **'마이크 접근이 허용되지 않았습니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 zaevis를 켜 주세요.'**
  String get recordMicDenied;

  /// No description provided for @recordError.
  ///
  /// In ko, this message translates to:
  /// **'녹음 오류: {error}'**
  String recordError(String error);

  /// No description provided for @recordStartFailed.
  ///
  /// In ko, this message translates to:
  /// **'녹음을 시작하지 못했습니다: {error}'**
  String recordStartFailed(String error);

  /// No description provided for @recordTranscribeFailed.
  ///
  /// In ko, this message translates to:
  /// **'전사 실패'**
  String get recordTranscribeFailed;

  /// No description provided for @recordTranscribeFailedLong.
  ///
  /// In ko, this message translates to:
  /// **'전사에 실패했습니다'**
  String get recordTranscribeFailedLong;

  /// No description provided for @recordQueued.
  ///
  /// In ko, this message translates to:
  /// **'전사 대기'**
  String get recordQueued;

  /// No description provided for @recordCancelling.
  ///
  /// In ko, this message translates to:
  /// **'취소하는 중'**
  String get recordCancelling;

  /// No description provided for @recordTitle.
  ///
  /// In ko, this message translates to:
  /// **'녹음'**
  String get recordTitle;

  /// No description provided for @recordUploading.
  ///
  /// In ko, this message translates to:
  /// **'올리는 중…'**
  String get recordUploading;

  /// No description provided for @recordTapToStart.
  ///
  /// In ko, this message translates to:
  /// **'눌러서 녹음 시작'**
  String get recordTapToStart;

  /// No description provided for @recordHintRecording.
  ///
  /// In ko, this message translates to:
  /// **'중지하면 inbox에 올라가고, whisperX가 설치돼 있으면 바로 전사합니다.'**
  String get recordHintRecording;

  /// No description provided for @recordHintTranscribing.
  ///
  /// In ko, this message translates to:
  /// **'오른쪽 위를 누르면 전사는 이어집니다. 녹음은 inbox에 남습니다.'**
  String get recordHintTranscribing;

  /// No description provided for @recordHintIdle.
  ///
  /// In ko, this message translates to:
  /// **'16kHz 모노 WAV로 저장합니다. 1분에 약 2MB. 첫 녹음 때 마이크 권한을 묻습니다.'**
  String get recordHintIdle;

  /// No description provided for @recordCancelTranscription.
  ///
  /// In ko, this message translates to:
  /// **'전사 취소'**
  String get recordCancelTranscription;

  /// No description provided for @recordStopUpload.
  ///
  /// In ko, this message translates to:
  /// **'중지하고 올리기'**
  String get recordStopUpload;

  /// No description provided for @recordStart.
  ///
  /// In ko, this message translates to:
  /// **'녹음 시작'**
  String get recordStart;

  /// No description provided for @recordQueuedToast.
  ///
  /// In ko, this message translates to:
  /// **'녹음을 전사 대기열에 넣었습니다: {file}'**
  String recordQueuedToast(String file);

  /// No description provided for @trailRecognizing.
  ///
  /// In ko, this message translates to:
  /// **'인식 중'**
  String get trailRecognizing;

  /// No description provided for @trailRecognizingDetail.
  ///
  /// In ko, this message translates to:
  /// **'인식 중 · {detail}'**
  String trailRecognizingDetail(String detail);

  /// No description provided for @trailSpeakersQueued.
  ///
  /// In ko, this message translates to:
  /// **'대기 · 곧 화자를 붙입니다'**
  String get trailSpeakersQueued;

  /// No description provided for @trailSpeakersRunning.
  ///
  /// In ko, this message translates to:
  /// **'화자 붙이는 중 · {detail}'**
  String trailSpeakersRunning(String detail);

  /// No description provided for @trailQueued.
  ///
  /// In ko, this message translates to:
  /// **'대기 · 곧 전사를 시작합니다'**
  String get trailQueued;

  /// No description provided for @trailTranscribing.
  ///
  /// In ko, this message translates to:
  /// **'전사 중'**
  String get trailTranscribing;

  /// No description provided for @trailFailed.
  ///
  /// In ko, this message translates to:
  /// **'전사 실패 · {error}'**
  String trailFailed(String error);

  /// No description provided for @trailCanRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도할 수 있습니다'**
  String get trailCanRetry;

  /// No description provided for @trailNextCollect.
  ///
  /// In ko, this message translates to:
  /// **'대기 · 다음 수집에서 전사됩니다'**
  String get trailNextCollect;

  /// No description provided for @trailLinked.
  ///
  /// In ko, this message translates to:
  /// **'출처 연결 · 정리에 반영된 전사입니다.'**
  String get trailLinked;

  /// No description provided for @trailIndexing.
  ///
  /// In ko, this message translates to:
  /// **'색인 중 · 끝나면 검색됩니다'**
  String get trailIndexing;

  /// No description provided for @trailWaitingDigest.
  ///
  /// In ko, this message translates to:
  /// **'검색 가능 · 정리 대기. 주간 정리 뒤에 메모리 출처가 됩니다'**
  String get trailWaitingDigest;

  /// No description provided for @trailSaved.
  ///
  /// In ko, this message translates to:
  /// **'글 저장 · 다음 색인에 들어갑니다'**
  String get trailSaved;

  /// No description provided for @trailFilteredOut.
  ///
  /// In ko, this message translates to:
  /// **'전체 {total}건 중 이 기간·출처에는 없습니다.'**
  String trailFilteredOut(int total);

  /// No description provided for @trailSearchIndexing.
  ///
  /// In ko, this message translates to:
  /// **'색인 중입니다. 끝나면 다시 찾습니다.'**
  String get trailSearchIndexing;

  /// No description provided for @trailMore.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}개'**
  String trailMore(int count);

  /// No description provided for @trailPendingTranscripts.
  ///
  /// In ko, this message translates to:
  /// **'전사 {count}개가 방금 저장됐습니다. 색인이 끝나면 검색됩니다.'**
  String trailPendingTranscripts(int count);

  /// No description provided for @trailNoResultsLatin.
  ///
  /// In ko, this message translates to:
  /// **'\"{query}\"에 대한 결과가 없습니다. 기록은 한글로 남아 있는 경우가 많습니다. 한글로 물어보세요.'**
  String trailNoResultsLatin(String query);

  /// No description provided for @trailNoResults.
  ///
  /// In ko, this message translates to:
  /// **'\"{query}\"에 대한 결과가 없습니다.'**
  String trailNoResults(String query);

  /// No description provided for @inputEditLine.
  ///
  /// In ko, this message translates to:
  /// **'줄 편집'**
  String get inputEditLine;

  /// No description provided for @inputNewLog.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 기록'**
  String get inputNewLog;

  /// No description provided for @inputLogHint.
  ///
  /// In ko, this message translates to:
  /// **'무엇을 했고, 왜 그렇게 했는지'**
  String get inputLogHint;

  /// No description provided for @inputDate.
  ///
  /// In ko, this message translates to:
  /// **'날짜'**
  String get inputDate;

  /// No description provided for @inputDigestLine.
  ///
  /// In ko, this message translates to:
  /// **'정리가 쓴 줄입니다. 출처({source})는 그대로 남습니다.'**
  String inputDigestLine(String source);

  /// No description provided for @inputProject.
  ///
  /// In ko, this message translates to:
  /// **'프로젝트 (선택)'**
  String get inputProject;

  /// No description provided for @inputPasteTranscript.
  ///
  /// In ko, this message translates to:
  /// **'전사본 붙여넣기'**
  String get inputPasteTranscript;

  /// No description provided for @inputTitle.
  ///
  /// In ko, this message translates to:
  /// **'제목'**
  String get inputTitle;

  /// No description provided for @inputTitleHint.
  ///
  /// In ko, this message translates to:
  /// **'주간 정리 회의'**
  String get inputTitleHint;

  /// No description provided for @inputPasteHint.
  ///
  /// In ko, this message translates to:
  /// **'전사 서비스에서 복사한 내용을 붙여넣으세요'**
  String get inputPasteHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
