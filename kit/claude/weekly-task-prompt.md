내 맥의 {{WORKLOG_DIR}} 폴더로 개인 작업 기록을 정리하는 주간 작업이다.

1. 먼저 {{WORKLOG_DIR}}/README.md를 읽고, 그 안의 "주간 정리" 절차를 그대로 따른다. 입력은 inbox/transcripts, inbox/claude-sessions, 그리고 {{REPOS_ROOT}} 아래 git 저장소에서 {{AUTHOR_EMAIL}}가 .state.md의 마지막 날짜 이후에 만든 커밋이다.
2. 오늘이 그 달의 첫 월요일(1~7일)이면, 주간 정리를 마친 뒤 README의 "월간 정리" 절차대로 지난달 summaries/YYYY-MM.md 초안을 쓴다.
3. 규칙: 한국어로 쓴다. 사용자가 쓴 로그 줄(src 표시 없는 줄)은 고치거나 지우지 않는다. 파일은 삭제하지 않고 processed/로 옮긴다. worklog를 git에 커밋하지 않는다. 로그·커밋에 없는 사실은 쓰지 않는다.
4. 끝나면 짧게 보고한다: 추가한 로그 줄 수, 갱신한 프로젝트 파일, 처리한 inbox 파일 수, 월간 초안을 썼다면 그 파일명. 맥에 접근할 수 없으면 그 사실만 보고하고 멈춘다.
