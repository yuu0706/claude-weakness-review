#!/bin/bash
# weakness-review を非対話で起動する。launchd から週1回（月曜 12:00）呼ばれる。
# 指摘の記録（log.md）から前回の実行より後の分だけを取り出し、feedback-mining の最新の結果などと一緒に
# claude（CLAUDE_LAUNCHER）へ渡す。claude には結果の出力先しか書かせない。
# 使い方: run.sh [--dry-run]
#   --dry-run  起動せず、組み立てたコマンドを標準出力へ表示する。last-run は更新しない。
# bash 3.2（macOS 標準）で動くように書く。連想配列と mapfile は使わない。
set -u

export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
unset CLAUDE_CONFIG_DIR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
JOB_NAME="weakness-review"
REPORTS_ROOT="${CLAUDE_REPORTS_ROOT:-$HOME/claude-reports}"
REPORTS_ROOT="${REPORTS_ROOT%/}"
STATE_BASE="${CLAUDE_REPORTS_STATE:-$HOME/.local/state/claude-reports}"
STATE_BASE="${STATE_BASE%/}"
STATE_DIR="$STATE_BASE/$JOB_NAME"
REPORT_DIR="$REPORTS_ROOT/$JOB_NAME"
# 会話の中で足していく指摘の記録。
LOG_MD="${WEAKNESS_REVIEW_LOG:-$STATE_DIR/log.md}"
FIRST_RUN_DAYS=7
OVERRIDE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-skills/$JOB_NAME.local.md"
UI_TEXT_LOG="${UI_TEXT_FEEDBACK_LOG:-$HOME/.local/state/ui-text/feedback-log.md}"
SKILL_AUDIT_HISTORY="${SKILL_AUDIT_STATE:-$HOME/.local/state/skill-audit}"
SKILL_AUDIT_HISTORY="${SKILL_AUDIT_HISTORY%/}/history.md"
# 作業の筋違いを判定する Stop hook の記録（JSON Lines。無ければ飛ばす）。
GATE_LOG="${WEAKNESS_REVIEW_GATE_LOG:-$HOME/.local/state/alignment-gate/log.jsonl}"

JOBS_CONF="${CLAUDE_REVIEW_JOBS_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-review-inbox/jobs.conf}"
jobs_conf() {
  local v
  [ -f "$JOBS_CONF" ] || return 0
  v="$(sed -n "s/^$1=//p" "$JOBS_CONF" | tail -n 1)"
  case "$v" in '~'*) v="$HOME${v#\~}" ;; esac
  printf '%s' "$v"
}
[ -n "${CLAUDE_LAUNCHER:-}" ] || CLAUDE_LAUNCHER="$(jobs_conf CLAUDE_LAUNCHER)"
[ -n "$CLAUDE_LAUNCHER" ] || CLAUDE_LAUNCHER=claude
[ -n "${CLAUDE_REVIEW_CONFIG_DIRS:-}" ] || CLAUDE_REVIEW_CONFIG_DIRS="$(jobs_conf CLAUDE_REVIEW_CONFIG_DIRS)"
[ -n "$CLAUDE_REVIEW_CONFIG_DIRS" ] || CLAUDE_REVIEW_CONFIG_DIRS="$HOME/.claude"
[ -n "${CLAUDE_REVIEW_DENY_READ:-}" ] || CLAUDE_REVIEW_DENY_READ="$(jobs_conf CLAUDE_REVIEW_DENY_READ)"
split_dirs() {
  local IFS=: d
  for d in $1; do
    case "$d" in '~'*) d="$HOME${d#\~}" ;; esac
    [ -n "$d" ] && printf '%s\n' "${d%/}"
  done
}
config_dirs=()
while IFS= read -r d; do [ -d "$d" ] && config_dirs+=("$d"); done < <(split_dirs "$CLAUDE_REVIEW_CONFIG_DIRS")
deny_read_extra=()
while IFS= read -r d; do deny_read_extra+=("$d"); done < <(split_dirs "${CLAUDE_REVIEW_DENY_READ:-}")
skill_dirs=()
for c in ${config_dirs[@]+"${config_dirs[@]}"}; do skill_dirs+=("$c/skills"); done
PROPOSALS_DIR="${CLAUDE_REVIEW_PROPOSALS:-$REPORTS_ROOT/proposals}"
PROPOSALS_DIR="${PROPOSALS_DIR%/}"
REJECTIONS="$PROPOSALS_DIR/rejections.md"
LEDGER_DIR="${CLAUDE_REVIEW_STATE:-$HOME/.local/state/claude-review-inbox}"
LEDGER_DIR="${LEDGER_DIR%/}"
LOG_KEEP=30

log_error() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_info() { printf '[%s] INFO: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) log_error "不明な引数です: ${arg}"; exit 2 ;;
  esac
done

mkdir -p "$STATE_DIR/logs" "$REPORT_DIR" || exit 1
REPORT_DIR="$(cd -P "$REPORT_DIR" && pwd -P)" || exit 1

LOCK_DIR="$STATE_DIR/lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log_error "別の実行が進行中です（${LOCK_DIR} が存在します）"
  exit 1
fi
STAMP="$STATE_DIR/run-started.$$"
trap 'rm -f "$STAMP"; rmdir "$LOCK_DIR" 2>/dev/null' EXIT
touch "$STAMP" || exit 1

if [ "$dry_run" -eq 0 ]; then
  LOG_FILE="$STATE_DIR/logs/$(date '+%Y-%m-%d-%H%M%S').log"
  exec >>"$LOG_FILE" 2>&1
  ls -1t "$STATE_DIR/logs/"*.log 2>/dev/null | tail -n +$((LOG_KEEP + 1)) | while IFS= read -r old; do
    rm -f -- "$old"
  done
fi

next_report_path() {
  local dir="$1" day n
  day="$(date '+%Y-%m-%d')"
  if [ ! -e "$dir/$day.md" ]; then printf '%s\n' "$dir/$day.md"; return 0; fi
  n=2
  while [ -e "$dir/$day-$n.md" ]; do n=$((n + 1)); done
  printf '%s\n' "$dir/$day-$n.md"
}

# 期間の始まり（YYYY-MM-DD HH:MM）。前回の実行の開始時刻、初回は FIRST_RUN_DAYS 日前。
if [ -f "$STATE_DIR/last-run" ]; then
  since="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$STATE_DIR/last-run")"
else
  since="$(date -v-"${FIRST_RUN_DAYS}"d '+%Y-%m-%d %H:%M')"
fi

# 記録から、見出しの日時が since 以降の項目だけを取り出す。見出しは「## YYYY-MM-DD HH:MM 作業場所」。
ts="$(date '+%Y-%m-%d-%H%M%S')"
entries="$STATE_DIR/entries-$ts.md"
ENTRIES_KEEP=10
if [ -f "$LOG_MD" ]; then
  awk -v since="$since" '
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/ { keep = (substr($0, 4, 16) >= since) }
    keep { print }
  ' "$LOG_MD" >"$entries" || { log_error "記録を読めませんでした: ${LOG_MD}"; exit 1; }
else
  : >"$entries"
fi
count="$(grep -c '^## [0-9]' "$entries" | tr -d ' ')"
ls -1 "$STATE_DIR/entries-"*.md 2>/dev/null | LC_ALL=C sort -r | tail -n +$((ENTRIES_KEEP + 1)) | while IFS= read -r old; do
  rm -f -- "$old"
done

# feedback-mining の最新の結果（期間内に書かれたものだけ）。
fm_latest=""
fm_dir="$REPORTS_ROOT/feedback-mining"
if [ -d "$fm_dir" ]; then
  f="$(ls -1 "$fm_dir"/*.md 2>/dev/null | LC_ALL=C sort | tail -n 1)"
  if [ -n "$f" ] && [ "$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f")" \> "$since" ]; then fm_latest="$f"; fi
fi
# 本スキルの前の結果（最大4週分）。
prev_reports="$(ls -1 "$REPORT_DIR"/*.md 2>/dev/null | LC_ALL=C sort | tail -n 4 | tr '\n' ' ')"

log_info "対象の期間: ${since} 以降。記録: ${count}件。feedback-mining: ${fm_latest:-なし}"

report="$(next_report_path "$REPORT_DIR")"

if [ "$count" -eq 0 ] && [ -z "$fm_latest" ]; then
  if [ "$dry_run" -eq 1 ]; then log_info "材料なし。起動しません"; exit 0; fi
  printf '# 弱点の見直し\n\n対象の期間（%s 以降）に、指摘の記録と feedback-mining の結果はありませんでした\n' "$since" >"$report" || exit 1
  mv -f "$STAMP" "$STATE_DIR/last-run"
  log_info "材料なし。レポートを書きました: ${report}"
  exit 0
fi

PROMPT="Skill weakness-review を自動モードで実行する（本文の「2. 週次の見直し」）。対象の期間は ${since} 以降。材料: 今週の指摘の記録は ${entries}（${count}件）。feedback-mining の最新の結果は ${fm_latest:-（無し）}。画面の文言への指摘の記録は ${UI_TEXT_LOG}（無ければ飛ばす。期間内の項目だけを使う）。作業の筋違いを判定する Stop hook の記録は ${GATE_LOG}（無ければ飛ばす。期間内の行だけを使う）。本スキルの前の結果は ${prev_reports:-（無し）}。否認リストは ${REJECTIONS}、skill-audit の変更の記録は ${SKILL_AUDIT_HISTORY}、利用者の環境だけの決まりは ${OVERRIDE_FILE}（無ければ飛ばす）。結果の出力先は ${report}。会話の履歴（jsonl）は読まない（権限で拒否している）。"

for lsc in "${CHANGE_REVIEW_SCRIPTS:-}" "$SCRIPT_DIR/../../change-review/scripts" \
  ${skill_dirs[@]+"${skill_dirs[@]/%//change-review/scripts}"}; do
  [ -n "$lsc" ] && [ -f "$lsc/link-scopes.sh" ] && . "$lsc/link-scopes.sh" && break
done
if ! type guard_deny_rules >/dev/null 2>&1; then
  log_error "Skill change-review の link-scopes.sh を読み込めません。書き換えを拒否する規則を作れないため、見直しを起動しません"
  exit 1
fi
link_reals=()
while IFS= read -r lr; do [ -n "$lr" ] && link_reals+=("$lr"); done < <(skill_link_reals ${skill_dirs[@]+"${skill_dirs[@]}"})

# 読んでよい範囲: 設定ディレクトリ（決まりの検索）・結果の置き場所・状態（記録と取り出したファイル）・承認待ち（否認リスト）。
read_scopes=(${config_dirs[@]+"${config_dirs[@]}"} "$HOME/.agents" "$REPORTS_ROOT" "$STATE_BASE" "$PROPOSALS_DIR")
allowed=(Skill)
for d in "${read_scopes[@]}"; do allowed+=("Read(/$d/**)"); done
allowed+=("Read(/$OVERRIDE_FILE)" "Read(/$SKILL_AUDIT_HISTORY)" "Read(/$UI_TEXT_LOG)" "Read(/$LOG_MD)" "Read(/$GATE_LOG)")
# common.md など、CLAUDE.md が「読め」と指す先（ai-agents の共通設定）も決まりの検索に含める。
AI_AGENTS_DIR="${AI_AGENTS_CONFIG_DIR:-$HOME/.config/ai-agents}"
[ -d "$AI_AGENTS_DIR/instructions" ] && allowed+=("Read(/$AI_AGENTS_DIR/instructions/**)" "Read(/$AI_AGENTS_DIR/config.json)")
for lr in ${link_reals[@]+"${link_reals[@]}"}; do allowed+=("Read(/$lr/**)"); done
allowed+=("Edit(/$REPORT_DIR/**)")
disallowed=("Read(/$HOME/Library/CloudStorage/**)")
for d in ${deny_read_extra[@]+"${deny_read_extra[@]}"}; do disallowed+=("Read(/$d/**)"); done
for c in ${config_dirs[@]+"${config_dirs[@]}"}; do disallowed+=("Edit(/$c/**)"); done
disallowed+=("Edit(/$HOME/Documents/**)" "Edit(/$HOME/.agents/**)" "Edit(/$PROPOSALS_DIR/**)" "Edit(/$LEDGER_DIR/**)"
  "Edit(/$STATE_DIR/**)" "Edit(/$LOG_MD)" "Edit(/$AI_AGENTS_DIR/**)")
for lr in ${link_reals[@]+"${link_reals[@]}"}; do disallowed+=("Edit(/$lr/**)"); done
deny_files=()
for c in ${config_dirs[@]+"${config_dirs[@]}"}; do deny_files+=("$c/CLAUDE.md" "$c/settings.json"); done
for df in ${deny_files[@]+"${deny_files[@]}"} "$PROPOSALS_DIR" "$LEDGER_DIR"; do
  while IFS= read -r dp; do
    if [ -d "$dp" ]; then disallowed+=("Edit(/$dp/**)"); else disallowed+=("Edit(/$dp)"); fi
  done < <(path_and_real "$df" | tail -n +2)
done
while IFS= read -r gr; do disallowed+=("$gr"); done < <(guard_deny_rules ${config_dirs[@]+"${config_dirs[@]}"} -- \
  ${skill_dirs[@]+"${skill_dirs[@]}"})
# 会話の履歴（jsonl）は表記と実体の両方で読ませない。
seen_src=" "
for c in ${config_dirs[@]+"${config_dirs[@]}"}; do
  while IFS= read -r dp; do
    case "$seen_src" in *" $dp "*) continue ;; esac
    seen_src="$seen_src$dp "
    disallowed+=("Read(/${dp%/}/**/*.jsonl)")
  done < <(path_and_real "$c/projects")
done

launcher=()
read -r -a launcher_words <<<"$CLAUDE_LAUNCHER"
for w in "${launcher_words[@]}"; do
  [ "$w" = "{job}" ] && w="$JOB_NAME"
  launcher+=("$w")
done
log_info "起動に使うコマンド: ${launcher[*]}"
cmd=("${launcher[@]}" -p "$PROMPT" --model opus --effort medium --permission-mode default
  --allowedTools "${allowed[@]}" --disallowedTools "${disallowed[@]}")

print_command() {
  local a sq="'\\''"
  printf "cd '%s' &&" "${REPORT_DIR//\'/$sq}"
  for a in "${cmd[@]}"; do printf " '%s'" "${a//\'/$sq}"; done
  printf '\n'
}

if [ "$dry_run" -eq 1 ]; then print_command; exit 0; fi

log_info "見直しを起動します"
print_command
(cd "$REPORT_DIR" && "${cmd[@]}")
rc=$?
if [ "$rc" -ne 0 ]; then
  log_error "見直しが異常終了しました（終了コード ${rc}）。last-run は更新しません"
  exit "$rc"
fi
if [ ! -s "$report" ]; then
  log_error "レポートが作られていません: ${report}。last-run は更新しません"
  exit 1
fi
mv -f "$STAMP" "$STATE_DIR/last-run"
log_info "見直しが完了しました。レポート: ${report}。last-run を更新しました"
exit 0
