# claude-weakness-review

| 項目 | 内容 |
| --- | --- |
| 対象 | Claude Code が利用者に直された振る舞いの記録と、週1回の弱点の見直し |
| 動作環境 | 必須: macOS、Xcode のコマンドラインツール（`/usr/bin/python3` 3.9 以上の実体）、Claude Code（`claude`）、[claude-review-inbox](https://github.com/yuu0706/claude-review-inbox) |
| ライセンス | MIT（[LICENSE](LICENSE)） |

本書は、claude-weakness-review の入れ方・更新・外し方と、仕組みを説明する。

## 1. 概要

利用者に振る舞いを直された指摘を、会話の中でその場に記録し、週に1回まとめて Claude の弱点と対策の案を作る。決まりを直すのは、利用者が案を承認した後だけである。

| 段 | いつ・誰が | すること |
| --- | --- | --- |
| 指摘の記録 | 会話の中で、指摘を受けたときに Claude が | `~/.local/state/claude-reports/weakness-review/log.md` の末尾に1件足す |
| 週次の見直し | 毎週月曜 12:00 に launchd が `claude -p` を起動して | 前回より後の記録を束ねて弱点にし、対策の案を `~/claude-reports/weakness-review/<日付>.md` に書く。結果の出力先のほかは書き換えない |
| 案の取り込み | 会話の中で、利用者が結果を読むときに Claude が | 案を Skill `change-review` の「直したいこと」の記録に足し、承認を受けたものだけを入れる |

Skill の本文は `core/skills/weakness-review/SKILL.md` にある。

## 2. 前提

| リポジトリ | 要るか | 理由 |
| --- | --- | --- |
| [claude-review-inbox](https://github.com/yuu0706/claude-review-inbox) | 必須 | 週次の見直しは、`change-review` の `link-scopes.sh` で書き換えを拒否する規則を作ってから起動する。無ければ起動しない。案を記録に足す道具も `change-review` にある。`feedback-mining` の結果があれば材料に加える |
| [claude-report-inbox](https://github.com/yuu0706/claude-report-inbox) | 任意 | 週次の見直しの結果と失敗を、会話の開始時に知らせる |

先に claude-review-inbox を入れてから、このリポジトリを入れる。

## 3. 構成

| パス | 内容 |
| --- | --- |
| `install.sh` | 入れる・外す。オプションは `--with-schedule`・`--no-schedule`・`--yes`・`--dry-run`・`--uninstall`。claude-review-inbox などと同じもので、`core/skills/` にあるスキルの分だけを扱う |
| `core/skills/weakness-review/` | 本体（`SKILL.md`）、週次の見直しを起動する `scripts/run.sh`、launchd の plist のひな形 |
| `core/tests/` | テスト。`core/tests/run.sh` で動く。頭の `# requires:` に書いたスキルが無いテストは飛ばす |
| `LICENSE` | MIT License |

## 4. 入れ方

1. リポジトリを clone する。`~/Documents`・`~/Desktop`・`~/Downloads` の下には置かない（launchd から動く定期実行が、macOS のプライバシー保護で開けないことがあるため）。

   ```sh
   git clone https://github.com/yuu0706/claude-weakness-review ~/claude-tools/claude-weakness-review
   cd ~/claude-tools/claude-weakness-review
   ```

2. 行う操作を確かめてから入れる。途中で週次の見直しを登録するかを聞かれる。

   ```sh
   ./install.sh --dry-run
   ./install.sh
   ```

`install.sh` は次を行う。何回実行しても結果は同じになる。

| No | 操作 | 備考 |
| --- | --- | --- |
| 1 | 必要なもの（Xcode のコマンドラインツール・Python 3.9 以上）を確かめる | 足りなければ入れる前に `[y/N]` で聞く。`--yes` を付けると聞かずに進む |
| 2 | `core/skills/weakness-review` を、スキル置き場（各設定ディレクトリの `skills`）へシンボリックリンクで置く | 同じ名前のものが既にあれば `<スキル置き場>/.trash/<YYYYMMDD-HHMMSS>-<名前>` へ移してから置く |
| 3 | 週次の見直しを launchd に登録する（`~/Library/LaunchAgents/com.<ユーザー名>.weakness-review.plist`） | `[y/N]` で聞く。`--with-schedule` で聞かずに登録し、`--no-schedule` で登録しない（登録済みなら外す）。同じスクリプトを指す plist が既にあれば、そのラベルを引き継ぐ |

### 4.1 環境ごとの設定

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `CLAUDE_REVIEW_CONFIG_DIRS` | 共通の設定ファイル `${XDG_CONFIG_HOME:-~/.config}/claude-review-inbox/jobs.conf` の値、無ければ `~/.claude` | Claude の設定ディレクトリの一覧（コロン区切り）。スキルのリンクを置く場所と、週次の見直しが決まりを検索する場所 |
| `CLAUDE_LAUNCHER` | jobs.conf の値、無ければ `claude` | 週次の見直しで起動するコマンド |
| `WEAKNESS_REVIEW_LOG` | `~/.local/state/claude-reports/weakness-review/log.md` | 指摘の記録 |
| `UI_TEXT_FEEDBACK_LOG` | `~/.local/state/ui-text/feedback-log.md` | 画面の文言への指摘の記録。あれば材料に加える |
| `WEAKNESS_REVIEW_GATE_LOG` | `~/.local/state/alignment-gate/log.jsonl` | 作業の筋違いを判定する hook の記録。あれば材料に加える |

利用者の環境だけの決まりは、上書きファイル `${XDG_CONFIG_HOME:-~/.config}/claude-skills/weakness-review.local.md` に書く。

## 5. 更新

```sh
cd ~/claude-tools/claude-weakness-review
git pull
./install.sh
```

## 6. 外し方

```sh
./install.sh --uninstall --dry-run   # 行う操作を確かめる
./install.sh --uninstall
```

このリポジトリを指すスキルのリンクと、登録した定期実行だけを消す。指摘の記録と見直しの結果は消さない。

## 7. 使い方

| したいこと | 方法 |
| --- | --- |
| 指摘を記録する | 会話で Claude の振る舞いを直す。Claude が記録に1件足し、「指摘を記録した」と伝える |
| 弱点を見る | 会話で「弱点を見せて」と伝える |
| 対策の案を取り込む | 会話で「今週の弱点のまとめを見せて」と伝え、示された案のうち入れるものを承認する |
| 週次の見直しをすぐ動かす | `core/skills/weakness-review/scripts/run.sh`（`--dry-run` で組み立てたコマンドだけを表示する） |

## 8. テスト

```sh
core/tests/run.sh
```

テストは本物の `HOME`・`launchctl`・`claude` に触れない。

## 9. ライセンス

MIT License である。全文は [LICENSE](LICENSE) にある。
