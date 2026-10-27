# Task 6C：通常敵10体撃破でボスへの矢印

2026-10-27のユーザー依頼「敵を10体倒すと最寄りのボスの方向に矢印」を実装。通常敵の累計撃破10体で、再挑戦まで案内する解釈を維持した。仕様からの逸脱はない。区画の生成・戦闘・ボス循環・6A/6Bのルールは変更していない。

## 表示と対象

- `actor_defeated` の通常敵撃破数 `kills` を使う。ボスを数えず、5Cで復活した敵は再び数える。既存の個体・IDの重複拒否も維持する。10体目だけ `announce` で「ボスの方角が分かるようになった」を6秒表示し、以後は通知を繰り返さない。`start_run` が撃破数と通知を初期化するため、追加の解禁フラグは持たない。
- 解禁前は左上の目的表示の下に「ボスの方角まで あとn体」。解禁後は自機の中心から70pxの位置に、淡い黄の矢印と距離を表示する。HUDのCanvas上で地形・敵・弾より手前、既存HUD・メニューより奥へ描く。自機と頭上HPバーを避ける。
- ガーディアン段階は現在の `guardian_ids`、ラスボス／裏ボス段階はその種別の生存記録を候補にし、ピクセルの直線距離で最寄りを選び直す。撃破済みは除外する。矢印は経路探索を行わず、対象への直線方向を示す。
- 対象の体の矩形が視界と一部でも重なると非表示。対象なし・配置選択中・クリア後・チュートリアルも非表示。一時停止・店・装備・設定・結果・タイトルでは隠す。
- 距離は `sqrt((dx/4096)^2 + (dy/3072)^2)` を四捨五入した区画の目安。「約2区画」など、1未満は「近い」。最寄りの選択自体は区画換算せず、実際のピクセル距離を使う。

## 未読込と原点移動

1周目で未生成のガーディアンは `initialize` が保持した `guardian_sectors` の該当区画中心を使う。`records` ができたらその `sector` と区画内 `position`、読込中は弱参照の `live_actors` から実体の現在位置を使う。区画解放で実体は通常どおり破棄でき、その後は既存の保存記録へ戻る。後の周回に初回の推定位置を流用しない。

プレイヤーと対象を区画座標＋区画内位置で扱い、整数区画座標の差を取ってからVector2に変換する。絶対ピクセル位置を作らず、原点移動で距離表示と方向を維持する。候補は数体、読込実体はボスIDの辞書で取得する。矢印のための区画生成・読込要求・全通常敵の走査は行わない。

## 変更ファイルと定数

追加：`scripts/boss_arrow.gd` と `.uid`、`tests/boss_arrow_test.gd`、本書。
変更：`scripts/boss_cycle.gd`（対象選択）、`scripts/enemy.gd`（ボスの弱参照登録）、`scripts/main.gd`（表示条件・解禁通知）、`scripts/interface.gd`（HUD）、`scripts/tuning.gd`、`tests/visual_check.gd`、`test.cmd`、`README.md`、`docs/roadmap_v2.md`。
`CLAUDE.md`・`.claude/`・`docs/claude_codex.md` は編集せず、コミット・プッシュ・公開は行わない。

追加定数は全て `scripts/tuning.gd`。

| 定数 | 初期値 |
|---|---|
| BOSS_ARROW_KILLS | 10体 |
| BOSS_ARROW_RADIUS | 70px |
| BOSS_ARROW_LENGTH / WIDTH | 16 / 20px |
| BOSS_ARROW_COLOR | f4f58a（淡い黄） |
| BOSS_ARROW_OUTLINE / OUTLINE_WIDTH | 121c27 / 2px |
| BOSS_ARROW_FONT_SIZE / LABEL_GAP | 16 / 18px |

通知時間は既存の `BOSS_ANNOUNCEMENT_TIME = 6.0` 秒を共用する。

## 検証

APPDATAをプロジェクト内 `.userdata` に設定し、同梱Godot 4.7.2で各テストを直接・逐次実行する。テスト自身の期限監視と、外部の上限（生成・区画・走破・ボス循環は3900秒、他1000秒）を併用する。ログ・開始終了時刻・終了コードは `builds/qa/boss_arrow/` に保存する。

新規検査は実撃破9→10体、ボス除外、5Cの復活経路、重複通知、再挑戦、チュートリアル、最寄りと角度誤差1e-5rad未満、移動・撃破による対象切替、各ボス段階、選択中・クリア後、初回の推定位置→実体→解放後の保存位置、遠方(100000,-50000)付近の記録・実体の原点移動、画面内・画面端、HUD進捗・通知・配置を検査する。

全26本・94,296項目・失敗0、全て終了コード0。スクリプトエラー・期限超過も0。区画・生成を除く24本は4,517項目。`run_tests` は追加の進捗Labelが既存の日本語UI再帰検査に入り、813→817項目となった。

| テスト（tests/、拡張子.gd） | 項目数 | 失敗 |
|---|---:|---:|
| run_tests | 817 | 0 |
| movement_test | 77 | 0 |
| key_bindings_test | 217 | 0 |
| tile_test | 50 | 0 |
| seamless_test | 147 | 0 |
| camera_test | 19 | 0 |
| playthrough | 101 | 0 |
| enemy_types_test | 56 | 0 |
| terrain_change_test | 122 | 0 |
| cave_world_test | 29 | 0 |
| streaming_test | 50 | 0 |
| streaming_performance | 21 | 0 |
| rewards_test | 109 | 0 |
| boss_cycle_test | 222 | 0 |
| tutorial_test | 165 | 0 |
| origin_shift_test | 115 | 0 |
| test_guard_test | 4 | 0 |
| ability_physics_test | 36 | 0 |
| abilities_test | 51 | 0 |
| ability_generation_test | 1073 | 0 |
| merchant_generation_test | 671 | 0 |
| equipment_physics_test | 180 | 0 |
| merchant_test | 96 | 0 |
| boss_arrow_test | 89 | 0 |
| sector_test | 68692 | 0 |
| generation_test | 21087 | 0 |
| 合計 | **94296** | **0** |

区画・生成の2本は最後に各1回ずつ実行した。区画検査は200シード・5,538標本、生成検査は1,000標本、自然なフォールバックはいずれも0。区画検査は実時間1,088.360秒、生成検査は175.997秒。開始終了時刻・終了コードは `runner-run_tests.json`、項目数の集計は `verification_audit.json` に保存した。

Windows証明書ストアの読取エラーは既存環境のものが残る。最終の全件実行・描画ではGDScriptエラーはない。初回の新規検査ではテスト用チュートリアルへキー設定を渡し忘れたためスクリプトエラーが出たが、検査側を修正して再実行した。

通常描画は `tests/visual_check.gd -- --boss-arrow`。OpenGLで8枚を保存し、全8枚を開いて確認した。進捗、解禁通知、左右上下・右上の矢印と距離、画面内の実体と矢印非表示を確認した。保存場面では自機・HPバー・既存HUDとの重なりはなかった。方向と画面内ボスの位置は制御したQA用配置、撃破は実際の処理を使う。

未確認：人の実操作中の矢印の見やすさ、10体という解禁数の釣り合い、長時間の難易度・所要時間、単独exeの書き出し。
