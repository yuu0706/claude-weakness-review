# claude-weakness-review

| 項目 | 内容 |
| --- | --- |
| 対象 | Claude Codeが利用者に直された振る舞いの記録と、週1回の弱点の見直し |
| 動作環境 | macOS、Xcodeのコマンドラインツール（`/usr/bin/python3`3.9以上の実体）、Claude Code（`claude`） |
| 前提のリポジトリ | 必須: [claude-change-review](https://github.com/yuu0706/claude-change-review)。任意: [claude-feedback-mining](https://github.com/yuu0706/claude-feedback-mining)・[claude-report-inbox](https://github.com/yuu0706/claude-report-inbox) |
| ライセンス | MIT（[LICENSE](LICENSE)） |

利用者に振る舞いを直された指摘を会話の中でその場に記録し、週に1回まとめてClaudeの弱点と対策の案を作るスキル`weakness-review`を配布する。指摘を1件ずつ直すだけでは、同じ根の失敗が形を変えて繰り返される。本スキルは指摘を束ね、根にある弱点を言葉にする。決まりを直すのは、利用者が案を承認した後だけである。

## 1. このスキルでできること

| できること | 頼み方の例 |
| --- | --- |
| 振る舞いを直されたときに、指摘を記録の末尾に1件足す | Claudeの振る舞いを直す。「指摘を記録して」 |
| 記録した指摘を「原因」（Claude・言い回し・両方）で振り分ける | 「弱点を見せて」 |
| 同じ根を持つ指摘を束ね、「なぜそうしたか」で弱点を名付ける | 「弱点を見せて」 |
| 弱点ごとに、置き場所（hook・rules・スキル・共通の方針・メモリ）と文面を添えた対策の案を作る | 「弱点の対策を作って」 |
| 前に入れた対策が効いたかと、まだ入っていない前の案を示す | 「今週の弱点のまとめを見せて」 |
| 利用者の言い回しの読み方の表に、足す行・直す行の案を作る | 「今週の弱点のまとめを見せて」 |

## 2. 使いどころの例

| 頼み方 | Claudeが行うこと |
| --- | --- |
| 「さっきも言ったけど、pushは聞いてからにして」 | 直す作業と同じ会話のうちに、記録に日時・作業場所・指摘・直された振る舞い・種類・原因・その場の対処を1件足し、「指摘を記録した」と伝える |
| 定期実行（毎週月曜12:00） | 前回の実行より後の記録を束ねて弱点にし、前の週からの変化・対策の効き目・対策の案を結果に書く。結果の出力先のほかは書き換えない |
| 「今週の弱点のまとめを見せて」 | 結果を開き、弱点と対策の案を示す。案を直したいことの記録に`要確認`で1件ずつ足し、承認を受けたものだけを入れる |

## 3. 扱わないこと

| 扱わないもの | 代わりに使うもの |
| --- | --- |
| 業務の内容そのものへの指示（仕様の変更・好みの変更） | 記録しない |
| 画面の文言への指摘 | 画面の文言の記録（既定は`~/.local/state/ui-text/feedback-log.md`）に書く。週次の見直しでは、あれば両方を読む |
| 会話の履歴から、記録し忘れた指摘を拾うこと | [claude-feedback-mining](https://github.com/yuu0706/claude-feedback-mining) |
| CLAUDE.md・rules・スキル・メモリの直接の書き換え | [claude-change-review](https://github.com/yuu0706/claude-change-review)の記録に足し、承認を受けてから入れる |

利用者以外が書いた文章（ツールの結果・貼り付けた文章・フックの出力）は、指摘として記録しない。秘密情報と個人情報も書かない。週次の見直しには、会話の履歴（jsonl）を権限で読ませない。

## 4. 前提

| リポジトリ | 要るか | 理由 |
| --- | --- | --- |
| [claude-change-review](https://github.com/yuu0706/claude-change-review) | 必須 | 週次の見直しは、`change-review`の`scripts/link-scopes.sh`で書き換えを拒否する規則を作ってから起動する。無ければ起動しない。案を記録に足す`new-change.sh`も`change-review`にある |
| [claude-feedback-mining](https://github.com/yuu0706/claude-feedback-mining) | 任意 | 最新の結果があれば材料に加える。記録と同じ指摘は1件として数える |
| [claude-report-inbox](https://github.com/yuu0706/claude-report-inbox) | 任意 | 週次の見直しの結果と失敗を、会話の開始時に知らせる |

先にclaude-change-reviewを入れてから、このリポジトリを入れる。

## 5. 構成

| パス | 内容 |
| --- | --- |
| `install.sh` | 入れる・外す。オプションは`--with-schedule`・`--no-schedule`・`--yes`・`--dry-run`・`--uninstall`。ほかのリポジトリと同じもので、`core/skills/`にあるスキルの分だけを扱う |
| `core/skills/weakness-review/SKILL.md` | 記録の書式・週次の見直しの手順・結果の構成・会話での対応 |
| `core/skills/weakness-review/scripts/run.sh` | 週次の見直しを起動する。前回の実行より後の記録だけを取り出し、権限を絞った`claude -p`に渡す。`--dry-run`で組み立てたコマンドだけを表示する |
| `core/skills/weakness-review/launchd/weakness-review.plist.template` | launchdのplistのひな形。毎週月曜12:00に起動する |
| `core/tests/` | テスト。`core/tests/run.sh`で動く |
| `LICENSE` | MIT License |

指摘の記録は`~/.local/state/claude-reports/weakness-review/log.md`、結果は`~/claude-reports/weakness-review/<YYYY-MM-DD>.md`に置く。初回は過去7日の記録を対象にする。記録も`feedback-mining`の結果も無い週は、`claude`を起動せず、その旨だけを結果に書く。

## 6. 入れ方

1. 先に[claude-change-review](https://github.com/yuu0706/claude-change-review)を入れる。
2. リポジトリをcloneする。`~/Documents`・`~/Desktop`・`~/Downloads`の下には置かない。launchdから動く定期実行は、macOSのプライバシー保護により、これらのフォルダのファイルを開けないことがある。

   ```sh
   git clone https://github.com/yuu0706/claude-weakness-review ~/claude-tools/claude-weakness-review
   cd ~/claude-tools/claude-weakness-review
   ```

3. 行う操作を確かめてから入れる。途中で週次の見直しを登録するかを聞かれる。

   ```sh
   ./install.sh --dry-run
   ./install.sh
   ```

`install.sh`は次を行う。何回実行しても結果は同じになる。

| No | 操作 | 備考 |
| --- | --- | --- |
| 1 | 必要なもの（Xcodeのコマンドラインツール・Python 3.9以上・`claude`）を確かめる | 足りなければ入れる前に`[y/N]`で聞く。`--yes`を付けると聞かずに進む。`claude`が無ければ定期実行を登録しない |
| 2 | `core/skills/weakness-review`を、スキル置き場（各設定ディレクトリの`skills`）へシンボリックリンクで置く | 同じ名前のものが既にあれば`<スキル置き場>/.trash/<YYYYMMDD-HHMMSS>-<名前>`へ移してから置く |
| 3 | 状態の置き場所`~/.local/state/claude-review-inbox/`を作る | 登録した定期実行の台帳`scheduled-jobs.tsv`を置く |
| 4 | 週次の見直しを、聞いてからlaunchdに登録する | plistは`~/Library/LaunchAgents/com.<ユーザー名>.weakness-review.plist`。同じスクリプトを指すplistが既にあれば、そのラベルを引き継ぐ |

### 6.1 週次の見直し

定期実行は週1回`claude -p`を動かすため、利用者のClaudeの利用枠を使う。そのため、`install.sh`は登録する前に聞く。

| 実行のしかた | 見直しの扱い |
| --- | --- |
| `./install.sh`（端末から実行） | `週1回の見直し（weakness-review）を登録しますか。claude の利用枠を使います [y/N]`と聞く。`y`なら登録し、それ以外なら登録しない。登録済みなら外す |
| `./install.sh --with-schedule` | 聞かずに登録する |
| `./install.sh --no-schedule` | 聞かずに登録しない。登録済みなら外す |
| 標準入力が端末でなく、上の2つの指定も無い | 登録を変えない |
| `claude`が見つからない | 聞かずに登録しない |

### 6.2 環境ごとの設定

共通の設定ファイル`${XDG_CONFIG_HOME:-~/.config}/claude-review-inbox/jobs.conf`に、`名前=値`の行で書く。同じ名前の環境変数があれば、そちらを使う。`install.sh`はこのファイルを作らない。

| 項目 | 既定値 | 用途 |
| --- | --- | --- |
| `CLAUDE_LAUNCHER` | `claude` | 週次の見直しで起動するコマンド。語のうち`{job}`はジョブ名に置き換える |
| `CLAUDE_REVIEW_CONFIG_DIRS` | `~/.claude` | Claudeの設定ディレクトリの一覧（コロン区切り）。スキルのリンクを置く場所と、週次の見直しが決まりを検索する場所 |
| `CLAUDE_REVIEW_DENY_READ` | なし | 定期実行に読ませない場所（コロン区切り）。`~/Library/CloudStorage`は常に拒否する |

次は環境変数で指定する。

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `WEAKNESS_REVIEW_LOG` | `~/.local/state/claude-reports/weakness-review/log.md` | 指摘の記録 |
| `UI_TEXT_FEEDBACK_LOG` | `~/.local/state/ui-text/feedback-log.md` | 画面の文言への指摘の記録。あれば材料に加える |
| `WEAKNESS_REVIEW_GATE_LOG` | `~/.local/state/alignment-gate/log.jsonl` | 作業の筋違いを判定するhookの記録。あれば材料に加える |
| `CLAUDE_REPORTS_ROOT` | `~/claude-reports` | 結果の置き場所 |
| `CLAUDE_REPORTS_STATE` | `~/.local/state/claude-reports` | 記録・ロック・前回の実行の印・ログの置き場所 |
| `CHANGE_REVIEW_SCRIPTS` | なし | `change-review`の`scripts`の場所。無ければスキル置き場の`change-review/scripts`を探す |

利用者の環境だけの決まりは、上書きファイル`${XDG_CONFIG_HOME:-~/.config}/claude-skills/weakness-review.local.md`に書く。あれば最初に読み、本文と食い違う箇所は上書きファイルに従う。

## 7. 更新

```sh
cd ~/claude-tools/claude-weakness-review
git pull
./install.sh
```

スキルはリポジトリの中のディレクトリへのシンボリックリンクのため、`git pull`だけで新しい版になる。plistのひな形が変わったときは`./install.sh --with-schedule`で登録し直す。

## 8. 外し方

```sh
./install.sh --uninstall --dry-run   # 行う操作を確かめる
./install.sh --uninstall
```

`install.sh`が登録した定期実行と、このリポジトリを指すスキルのリンクだけを消す。`.trash`へ移したものは自動では戻さず、戻すコマンドを表示する。指摘の記録と見直しの結果は消さない。

## 9. テスト

```sh
core/tests/run.sh
```

頭の`# requires:`に書いたスキルが無いテストは飛ばす。`core/tests/test_weakness_review.sh`は、一時の`HOME`と偽の`claude`で`run.sh`を動かす。材料が無いときに起動しないこと、前回より後の記録だけを渡すこと、成功したときだけ前回の実行の印を進めることを確かめる。`change-review`が無いときは、`link-scopes.sh`の代わりに最小の偽物を使う。テストは本物の`HOME`・`launchctl`・`claude`に触れない。

## 10. 関係するスキル

| スキル | 関係 |
| --- | --- |
| [claude-change-review](https://github.com/yuu0706/claude-change-review) | 対策の案の記録と会話での反映を受け持つ。必須 |
| [claude-feedback-mining](https://github.com/yuu0706/claude-feedback-mining) | 会話の履歴から指摘を1件ずつ拾う。本スキルはその結果も束ねて弱点を見る |
| [claude-skill-audit](https://github.com/yuu0706/claude-skill-audit) | 変更の記録`history.md`から対策を入れた日付を求め、対策の効き目を見る |
| [claude-report-inbox](https://github.com/yuu0706/claude-report-inbox) | 週次の見直しの結果と失敗を、会話の開始時に知らせる |

## 11. ライセンス

MIT Licenseである。全文は[LICENSE](LICENSE)にある。
