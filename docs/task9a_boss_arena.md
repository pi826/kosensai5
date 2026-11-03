# Task 9A: 専用ボスアリーナと固有攻撃

2026-11-03。Godot 4.7.2 / GDScript。区画をつないだ一続きの探索を保ち、ボスのための専用空洞をシード生成に加えた。

## 仕様

### 区画・形・足場

`S.is_arena_sector(seed, at, guardians)` は純粋関数。初回ガーディアンの3区画は必ずアリーナ。その他は原点からチェビシェフ距離1以下を除外し、`floor(at / 3)` で求める3×3の塊について `_key(seed, block, "arena") mod 9` の1区画を選ぶ。負の座標も床関数で扱う。ガーディアン優先による追加区画と開始付近の除外は、塊ごとの1区画規則の例外となる。

通常生成の専用部屋はkind `boss`、幅1664〜1920px（64px刻み）・高さ1024px・`arena_tiers=3`。xは14〜`(3648-w)/32`、yは12〜`(2816-1024)/32`の整数を32倍する。shaft/elbowの縦穴が天井前後32pxに交わる候補を除き、横の入口と床から下の縦穴を許す。

中心xをcx、床yをFとして、厚さ16pxの足場を次の型で置く。各棚の周囲は既存と同じ192px高のclearanceを要求し、置けなければ再試行する。棚の踏切は既存方式で保護する。旧有限ステージの`arena_tiers`なしのboss部屋は従来の飾り付けを維持する。

| 段 | y | x / 幅 |
|---|---|---|
| 1 | F−160 | cx−704 / 448、cx+256 / 448 |
| 2 | F−320 | cx−384 / 768 |
| 3 | F−480 | cx−640 / 384、cx+256 / 384（3段以上のみ） |

ボスの探索範囲zoneは `Rect2(x+32, y+32, w−64, h−32−160)`。天井から32px下〜床から160px上、通常は高さ832px。厚い岩（solidsのsize.y != 16）とbreakablesがこの範囲に交わらないことを検証する。薄い足場はzone内にあってよい。アリーナのroamは `roam_rect(data, zone, role, Vector2(zone.get_center().x, F−ARENA_BOSS_CENTER_HEIGHT), true)` で求め、体・余白・往復距離が収まり、中心が床から360px上に最も近い候補を選ぶ。薄い足場のみ回避対象から除き、岩・壊れるブロック・収集物・商人は避ける。

フォールバックは中段右の部屋を `Rect2(1696,928,1920,832)`・2段に置き換える。従来の中段トンネルは残し、棚は1・2段目の3枚。zoneの高さは640px。初回ガーディアン区画のみ、生成データのボスとlandmarkをアリーナ床中央に置く。実体の初期位置は床から360px上を優先したroamの中央。それ以外のアリーナはBossCycleの追加配置まで空室になる。

Claudeのplaythroughで、床に立つ自機からボスが見えず発見されない問題を見つけ、床から見える高さへ修正した（2026-11-03、Task 9A位置修正）。重力反転・4方向ダッシュのTask 9Bは維持する。

アリーナには通常敵・強化の灯・ハート・収集物・商人・寄り道・壊れるブロック・段差・岩を生成しない。通常敵の総数・地形接続・足場clearance・侵食・到達性の既存閾値は維持する。

### 配置・タイプ・保存

追加ボス候補はアリーナ区画だけを対象とし、距離2〜5を決定的にシャッフルして探す。足りなければ同じ乱数列で距離6〜8を追加探索する。既存の候補順を維持し、既使用区画の除外と復活3体の別地域条件を保つ。

`guardian_types(seed, round)` は `"seed:round:guardian_types".hash()` を種にFisher–Yatesで3タイプを並べ替える。初回はboss_id、復活はsitesの添字で割り当てる。表示名は「ガーディアン・召喚／旋回／突進」。体の上に3小円／十字／山形の印を描き、既存の画像は変えない。

通常ボスは薄い足場を通過し、岩・設置壁の衝突は保持する。突進等でroam外へ出た場合、320px/秒の衝突移動で最寄りの境界点へ戻る。瞬間移動しない。原点移動時は固定した突進目標も同じ量だけ動かす。

区画解放時は既存欄に加えて `signature_clock`、`signature_index`、`spin_direction`、`summon_wave`、`summons_to_restore` を区画状態とBossCycleのsavedへ保存する。召喚ガーディアンの解放直前の生存召喚数を数え、未完了の呼び直し数も保持する。タイプはBossCycleの個体記録へ保持する。攻撃中の一時状態は破棄し、再読込はidleと通常の起床待ちから始める。

### 固有攻撃

通常の優先順は色切替→満タンゲージ誘導弾→固有攻撃→通常射撃。召喚ガーディアンの呼び直しとHP半分時の追加波はそれらより優先し、画面内・起床待ち終了・idleの次の選択で始める。実行中の攻撃は中断しない。固有タイマーは通常射撃と同様に待機中だけ`delta*rate`で減る。ラスボスと裏ボスは旋回→召喚→突進の順に循環する。従来の射撃・扇射撃・誘導弾・色切替を維持する。

- **旋回**: 0.6秒予告して腕の方向へ160pxの線を描く。開始ごとに回転方向を逆にし、4本（裏ボス8本）の腕から等角度で発射する。腕の色は交互、反対側の腕は同色。移動しながら回転し、発射後の弾色を保持する。
- **召喚**: 0.8秒の輪の予告後に実行する。召喚ガーディアンは最初の固有攻撃（開始待ち2.5秒後）に5体、HPが最大の半分以下になった次の攻撃選択でさらに5体、合計2波だけ。1波目の生存数に関係なく2波目を追加し、上限は10体。早くHPが半分になった場合も開始待ちを保ち、1波目を先に、完了後の次の選択で2波目を実行する。完了時だけ波数を進めるので、キャンセルした予告は再選択できる。再読込は召喚実体0体から始まり、生存数の記録があれば同じ予告でその数を呼び直す。呼び直しは2波目より先に行い、波数を進めず完了時に待ち数を0にする。ラスボス／裏ボスの周期召喚は従来の2／3体、上限4／5体で、満員なら開始せず順序だけ進める。

召喚の種類はwalker/flyer、色はボスの色から交互。walkerは床上、flyerのflight_center_yは床から400px上。候補xはwalkerで両端64px、flyerで両端160pxを除いた連続区間から求める。体の半幅を加えた岩・壊れるブロックの占有区間と、同波の同段の敵との中心間隔102px未満の区間を全段で除く。現在の`view_rect().grow(-16)`に体全体が入る中心区間を求め、a:画面内・水平256px以上・生きた敵（召喚元を含む）と非交差、b:画面内・水平256px以上（生きた敵との重なり可）、c:画面内・距離条件なし・自機の体と非交差、d:従来のアリーナ内配置（生きた敵との非交差を優先）、の順で最初の空でない段を使う。各段の空き区間の左右端から自機と水平に最も遠い位置を選び、同距離なら左。シード・乱数は使わない。walkerの巡回はx±192を両端64px以内へ収め、flyerは両端160pxの飛行範囲を保つ。呼び直しとfinal/secretもこの共通規則を使う。

床の自機へカメラをsnapした場合、画面片側で使える中心の最遠距離は`640−16−38/2=605px`。3体のwalkerを102pxずつ並べても3体目は401px、2体のflyerでは2体目が503pxとなり、256pxを確保できる。中央・左右端近くの実配置で1波目と生存5体を残す2波目、画面内への体全体の収容、起床と活動を検査する。岩・ブロック回避やc/dへのフォールバックも人工条件で検査する。

- **突進**: 自機位置を体と余白が収まるアリーナ内へ制限して目標を固定する。線の予告中は静止し、突進中は衝突移動する。到着・岩との衝突・1.4秒の期限で0.5秒の静止回復へ移り、その後idle・roam復帰。既存の同色安全・異色接触ダメージを使う。

召喚敵は `summon:boss_id:連番` のID、`summoned_by`・元の`sector`・`chamber_id=-1`を持ち、通常の周回強化と起床待ちを適用する。撃破では通常敵の音と演出・誘導弾報酬のみを与える。結晶・スコア・kills・defeated_enemies・復活記録・live_normalsへ入れない。区画解放で実体を保存せず消す（召喚ガーディアンのみ生存数を保存して呼び直す）。召喚元の撃破でも演出後に報酬なしで消す。

`main.spawn_bullet` は末尾に任意の `color=-1` と `origin=Vector2.INF` を追加した。省略時の発射色・位置は従来どおり。旋回のみ色とマズル座標を指定する。音は既存IDだけを使う。

### 定数

役別の列はguardian / final / secretの順。

| 定数 | 値 |
|---|---|
| ARENA_BLOCK / START_EXCLUSION | 3 / 1 |
| ARENA_WIDTH_MIN / MAX / HEIGHT | 1664 / 1920 / 1024 |
| ARENA_TIERS / TIER_STEP | 3 / 160 |
| ARENA_BOSS_CENTER_HEIGHT / ARENA_FLYER_HEIGHT | 360.0 / 400.0 |
| ARENA_FALLBACK_RECT / TIERS | Rect2(1696,928,1920,832) / 2 |
| BOSS_SPAWN_DISTANCE_MIN / MAX / FALLBACK_MAX | 2 / 5 / 8 |
| BOSS_ROAM_TRAVEL | (480,120) / (640,160) / (720,176) |
| BOSS_RETURN_SPEED | 320 |
| GUARDIAN_TYPES | summoner, spinner, charger |
| GUARDIAN_TYPE_NAMES | 召喚, 旋回, 突進 |
| BOSS_SIGNATURE_ORDER | spinner, summoner, charger |
| BOSS_SIGNATURE_DELAY | 2.5 |
| BOSS_SIGNATURE_INTERVAL | 7 / 6 / 5 |
| BOSS_SPIN_WARNING | 0.6 |
| BOSS_SPIN_DURATION | 3 / 3 / 3.5 |
| BOSS_SPIN_SHOT_INTERVAL | 0.2 / 0.18 / 0.24 |
| BOSS_SPIN_SPEED | 1.4 / 1.7 / 2 rad/s |
| BOSS_SPIN_ARMS | 4 / 4 / 8 |
| BOSS_SUMMON_WARNING | 0.8 |
| BOSS_SUMMON_COUNT | 5 / 2 / 3 |
| BOSS_SUMMON_MAX_ALIVE | 10 / 4 / 5 |
| BOSS_SUMMON_SECOND_WAVE_RATIO | 0.5 |
| BOSS_CHARGE_WARNING | 0.75 / 0.65 / 0.55 |
| BOSS_CHARGE_SPEED | 720 / 820 / 900 |
| BOSS_CHARGE_MAX_TIME / RECOVER | 1.4 / 0.5 |

`BOSS_ROOM_MIN` は削除した。

## 変更ファイル

実装: `scripts/tuning.gd`、`sector_generator.gd`、`stage_generator.gd`、`boss_cycle.gd`、`enemy.gd`、`main.gd`、`sector_stream.gd`、`interface.gd`。

検査: 新規 `tests/boss_arena_test.gd`、`tests/boss_patterns_test.gd`、既存 `tests/boss_cycle_test.gd`。`test.cmd` はperf_behavior_test直前に2本を追加し、表示を39実行へ変更、pauseを保持。文書: 本書、README、roadmap_v2、seamless_world。

`player.gd`、`key_bindings.gd`、`loot_generator.gd`は変更していない。Git・インターネット・別エージェントの呼出しは行っていない。

## 検証

以下はTask 9A初回実装時の記録。表示位置修正後の検査結果・現在の未確認事項は末尾を参照。

テストは各1本ずつ前景で、`APPDATA=.userdata`、`--headless --audio-driver Dummy --fixed-fps 60`で実行。以下は修正後の採用結果。ログは `.userdata/codex-delegation/task-20261103-63-<test名>.log`。

| 検査 | 項目数 | 結果 |
|---|---:|---|
| boss_arena_test | 3900 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_patterns_test | 119 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_cycle_test | 225 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_arrow_test | 90と表示 | 終了0だがSCRIPT ERRORあり。成功には数えない |
| enemy_types_test | 56 | 終了0、失敗0、SCRIPT ERRORなし |
| run_tests | 1909 | 終了0、失敗0、SCRIPT ERRORなし |
| rewards_test | 109 | 終了0、失敗0、SCRIPT ERRORなし |
| cave_world_test | 25 | 終了0、失敗0、SCRIPT ERRORなし |
| streaming_test | 54 | 終了0、失敗0、SCRIPT ERRORなし |

Godotはこの環境で `Failed to read the root certificate store` を出力する。ネットワークは使用していない。採用した成功結果ではSCRIPT ERRORを別に照合する。初期の専用検査では型指定・重複宣言・flyerの揺れを含めない期待値を修正し再実行した。既存の閾値は緩めていない。

### 変更した既存検査

`boss_cycle_test.gd`の3点のみ。

1. 初回ガーディアンのroamを「床の出現点から256px未満」から「体全体がarena_zoneに収まる」に変更。実体は床上の生成座標と異なるroam中央に浮遊するため。
2. 追加配置を「通常空洞・768×448以上」から「boss部屋・is_arena_sector」に変更。専用アリーナへ移したため。
3. 従来の移動・射撃型の検査前にsignature_clockを十分大きく設定。固有攻撃を別の専用検査へ分け、既存の射撃本数・色切替・誘導弾の検査を保つため。

それ以外の既存検査は変更していない。変更前ソースとの比較でも、既存ファイルの変更は上記の許可一覧内13ファイルのみ。新規の本書と専用検査2本を加えて16ファイル（指定された.userdata内の下書き・比較スクリプト・ログを除く）。

### 非アリーナ署名

実装前に `.userdata/codex-delegation/task-20261103-63-draft.md` を保存した。その後、同ディレクトリの `task-20261103-63-signatures.gd` を実行し、seed 1・37、x/y各−4〜4の162区画について `S.signature(S.generate(...)).sha256_text()` を `task-20261103-63-before.json` へ保存した。

実装後は同スクリプトに `-- --compare` を渡した。新仕様で非アリーナとなる142区画は全件一致、不一致0。結果は `task-20261103-63-comparison.json`。アリーナ20区画は比較対象外。元ソースは同ディレクトリの `task9a-source/` に保存した。

### アリーナ生成実測

seed 1・37・2026・−17の各11区画（初回3区画＋それ以外8区画）、計44区画を生成。通常生成のフォールバックは **0/44**。平均 **193.520ms**、最大 **1148.910ms**。強制フォールバックは別途4例すべてvalidate通過。`task-20261103-63-arena-results.json` に記録した。これは専用検査の標本であり、性能検査や難易度評価ではない。

## 未解決・未確認

- **チュートリアルのコンパイル互換性**: `scripts/tutorial.gd:227` が旧4引数で `spawn_bullet` をoverrideしており、mainの新6引数と一致しないため、boss_arrow_testのチュートリアル依存部分でSCRIPT ERRORとなる。tutorial.gdは変更許可一覧外のため未変更。引数追加とsuperへの転送だけの2行パッチを `.userdata/codex-delegation/task-20261103-63-tutorial-compatibility.patch` に準備し、変更範囲の追加を照会中。この修正後にboss_arrow_testとui_map_testの再検査が必要。受入条件の「指定7本すべてSCRIPT ERRORなし」は現時点で未達。
- 人が遊んだ難易度・戦闘の所要時間、予告と印の通常描画での視認性、音の聴感は未確認。
- 指示によりtest.cmd全体、sector_test、generation_test、playthrough、audio_test、streaming_performance、perf系は実行していない。Claude側で実行する。


## 検査結果の保存先（Task 66）

`boss_arena_test.gd`は`res://builds/qa/bosses/arena-results.json`、`boss_patterns_test.gd`は`res://builds/qa/bosses/pattern-results.json`へ結果を保存する。書込前に`res://builds/qa/bosses`を再帰作成するため、buildsの無いcloneでも保存できる。以下のTask 63・65の作業記録の保存先は当時のもの。

## 表示位置修正の検証（2026-11-03、Task 65）

今回の変更は指定された実装5・検査3・文書2ファイルのみ。Task 9Aと9Bの既存変更を保持した。方針は実装前に`.userdata/codex-delegation/task-20261103-65-draft.md`へ保存し、元ソースを`task65-source/`に控えた。

| 検査 | 項目数 | 結果 |
|---|---:|---|
| boss_arena_test | 4572 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_patterns_test | 3791 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_cycle_test | 225 | 終了0、失敗0、SCRIPT ERRORなし |
| boss_arrow_test | 91 | 終了0、失敗0、SCRIPT ERRORなし |
| rewards_test | 109 | 終了0、失敗0、SCRIPT ERRORなし |
| run_tests | 1943 | 終了0、失敗0、SCRIPT ERRORなし |
| gravity_test | 81 | 終了0、失敗0、SCRIPT ERRORなし |

計10812項目。各1本ずつpwshから前景で実行した。ログ・結果は`.userdata/codex-delegation/task-20261103-65-*.log`、`task-20261103-65-results.json`。環境由来の`Failed to read the root certificate store`は出力されたが、通信は行っていない。初回実装時のチュートリアル互換性エラーは今回のboss_arrow_testでは再現せず、この修正でtutorial.gdは変更していない。

- boss_arena_test：zoneの定義と岩・breakablesの非交差を更新。通常44例と強制fallback4例の各guardian/final/secretについて、体全体の収容、床上視界の上端（不感帯+20pxを含む）、床−160pxまでの余白、岩・breakablesとの非交差を検査した。
- boss_patterns_test：flyerのflight_center_yの期待値を床−400へ更新し、揺れ幅の既存閾値を保持。seed 1・37・2026・−17の初回guardian全12体を実際に読み込み、無敵の自機を床中央に固定してカメラ更新・探索による発見を確認。各300物理フレーム、カメラをボスへ追従させず20px内側の画面内に留まり、実際に動くことも確認した。新検査の条件分岐に使うcheckはboolを返すようにした。初回の実行で後続検査が飛ぶヘルパーの誤りを見つけて直し、上表は再実行後の結果。
- boss_cycle_test：初回roamの呼出しを実装と合わせ、ボスの体と地形の交差判定から厚さ16pxの足場だけを除いた。岩・breakablesとの非交差、既存の他の閾値は維持した。

旧63のbefore.jsonと比較スクリプトを保持し、同じ手順のコピー`task-20261103-65-signatures.gd`で比較した。9B後の今回変更前162区画の値を実装前に`task-20261103-65-before.json`へ保存。seed 1・37、x/y各−4〜4のうち非アリーナ142区画は今回変更前後で全件一致（不一致0）。63基準とはその142区画中140区画が異なるが、これは今回変更前から存在する差。両基準との比較は`task-20261103-65-comparison.json`へ保存した。

人による描画・視認性・難易度・音の確認と長時間プレイは未確認。test.cmd全体、sector_test、generation_test、playthrough、audio_test、streaming_performance、perf系は指示により未実行。Git・インターネット・他のcoding agentは使用していない。

## 召喚ガーディアンの2波化（2026-11-03、Task 67）

本節は2波化時点の記録。画面外に配置される問題は、後続のTask 67bで上記のa〜dによる画面内優先配置へ修正した。

変更は`enemy.gd`（完了波・呼び直しと優先順位）、`main.gd`の`summon_minions`（決定的な空き区間配置）、`tuning.gd`（5体・上限10・半分HP）、`sector_stream.gd`の保存欄、`boss_patterns_test.gd`、本書と`seamless_world.md`の召喚記述の7ファイル。BossCycleの既存の保存・復元経路を使うため`boss_cycle.gd`は変更していない。Task 9A/9Bの現在の変更を保ち、方針は実装前に`.userdata/codex-delegation/task-20261103-67-draft.md`へ保存した。

| 検査 | 項目数 | 結果 |
|---|---:|---|
| boss_patterns_test | 4318 | 終了0・失敗0・SCRIPT ERRORなし |
| boss_cycle_test | 225 | 終了0・失敗0・SCRIPT ERRORなし |
| boss_arena_test | 4572 | 終了0・失敗0・SCRIPT ERRORなし |
| boss_arrow_test | 91 | 終了0・失敗0・SCRIPT ERRORなし |
| rewards_test | 109 | 終了0・失敗0・SCRIPT ERRORなし |
| run_tests | 1943 | 終了0・失敗0・SCRIPT ERRORなし |
| 合計 | 11258 | 全6本成功 |

`APPDATA=.userdata`、headless・Dummy・fixed-fps 60を使用し、pwshの前景で1本ずつ実行した。パターン検査は追加の配置・呼び直し検査を加えて再実行し、表は最終ソースの結果。ログは`.userdata/codex-delegation/task-20261103-67-<検査名>.log`、集計は`task-20261103-67-results.json`。環境由来の`Failed to read the root certificate store`は出たが、全ログでSCRIPT ERROR・Parse Error・FAILは0。通信は使用していない。

既存検査の置換と理由：

- guardianの旧2体・上限3体は、要求された1波5体・2波計10体・上限10体へ変更。
- 「満員なら通常射撃」のguardian検査は、HPが半分より多い1波目後と2波目後にそれぞれ20秒進めても召喚しない検査へ置換。生存数に応じた周期補充を廃止したため。final/secretの「capped summon advances index only」は維持。
- 「左右25%／75%で遠い方」は、床中央・左右端で全5体が水平256px以上、同段102px以上・体の非交差・岩／ブロック回避・決定性の検査へ置換。256pxが不可能な小部屋だけ最遠候補へ戻る検査も追加した。
- 「召喚敵は再読込されない」は、実体の保存除外・再読込直後0体を維持した上で、1波目の生存3体の保存→予告→3体呼び直し→半分HPで5体追加へ更新。波数と生存数を保持する新仕様のため。呼び直し前・予告中の再解放、2波目後の8体呼び直し、半分HPと同時の呼び直し優先も検査。

初回待ち・0.8秒の予告、正確に半分HPでの色切替／満タンゲージ／固有攻撃／通常射撃に対する優先、実行中攻撃・画面外・起床待ちの保持、早期半分HPの1波目→2波目、新個体の初期状態も追加検査した。色・報酬・旋回・突進・表示位置の既存閾値は緩めていない。

実装前のソース控えは`task67-source/`、変更範囲と保持した生成・自機・キー設定等のハッシュ確認は`task-20261103-67-changed-files.json`と`task-20261103-67-preserved-files.json`。生成処理には触れておらず、生成signatureの再比較は実行していない。人による通常描画・難易度・長時間プレイは未確認。禁止されたtest.cmd全体、sector_test、generation_test、playthrough、audio_test、streaming_performance、perf系、loop_scaling_testは実行していない。Git・信頼設定／所有者／権限の変更・他agent・commit／push／publish／deployは行っていない。

## 召喚の画面内配置（2026-11-03、Task 67b）

Task 67のアリーナ最遠端では、自機が床中央にいると召喚敵が画面外で停止していた。`main.gd`の`summon_minions`に現在の画面と体全体の収容条件を加え、上記のa→b→c→dを実装した。各段で最遠端、同距離なら左を選ぶ。岩・ブロック回避、同波同段102px、床／床−400px、アリーナ内、巡回範囲は維持する。定数・敵の挙動・保存処理・攻撃色には変更を加えていない。

変更した実装・検査・文書は`main.gd`（同関数のみ）、`boss_patterns_test.gd`、本書、`seamless_world.md`の4ファイル。実装前に`.userdata/codex-delegation/task-20261103-67b-draft.md`を保存した。`main.gd`は同関数以外がTask 67開始時のソース控えとも一致する。

`_update_camera(0,true)`で床の自機へカメラを合わせた実配置：

| 自機位置 | 1波目5体の段 | 生存5体を残した2波目5体の段 | 最小水平距離（1波目／2波目） |
|---|---|---|---:|
| 床中央 | 全5体a | 全5体a | 503／465px |
| 左端から32px | 全5体a | 全5体a | 401／363px |
| 右端から32px | 全5体a | 全5体a | 401／363px |

各波の体全体が画面の16px内側に入り、距離256px・同段102px・既存敵との非交差・岩／ブロック回避を満たした。各位置で全10体の物理処理を有効にし、カメラ・自機を固定したままENEMY_WAKE_DELAY+1秒以内の可視化と活動を確認した。walkerは位置変化または攻撃予告、flyerは位置変化を条件とし、一度でもwas_visibleがtrueになったことを記録する。呼び直し3体、final上限4体、secret上限5体も全体が画面内で、段aを使用した。

人工条件ではaの生存敵回避、aが近距離にしか残らない場合にbが256pxを保つこと、画面外の最遠端よりcの画面内候補を選ぶこと、画面内候補が無い場合にdへ戻ることを検査した。256px自体は下げていない。

既存検査の修正と理由：

- アリーナ全幅から計算していた配置余力の2検査を、画面半幅から16pxと敵の半幅を引いた余力へ更新。画面内で3体のwalker／2体のflyerを収めるため。
- 床3位置の配置検査は自機へカメラをsnapして共通召喚関数を直接呼ぶ。端ではボス自身が画面外になり、予告の物理更新が停止するため。初回の検査はこの理由で左右端で失敗し、配置と予告の検査を分けて修正した。既存の2波・起床待ち・画面外停止・予告時間の検査は保持。
- 600pxの小部屋の固定期待座標（walker=64、flyer=160）は変更せず、段cとして画面内・自機非交差を追加確認。画面を離した段dでも同じ従来座標を確認する。
- 再読込後の検査用カメラも床の自機へsnapし、呼び直しの画面内収容を追加。final/secretの上限・順序検査に同じ画面内条件を追加。

Task 67の2波、20秒後も追加召喚しないこと、HP半分時の優先、保存と呼び直し、final/secretの順序、および色・吸収・ダメージ・発射後の弾色保持の既存検査は保持している。

最終ソースでの限定検査：

| 検査 | 項目数 | 結果 |
|---|---:|---|
| boss_patterns_test | 4850 | 終了0・失敗0・SCRIPT ERRORなし |
| boss_cycle_test | 225 | 終了0・失敗0・SCRIPT ERRORなし |
| boss_arena_test | 4572 | 終了0・失敗0・SCRIPT ERRORなし |
| run_tests | 1943 | 終了0・失敗0・SCRIPT ERRORなし |
| 合計 | 11590 | 全4本成功 |

`APPDATA=.userdata`、headless・Dummy・fixed-fps 60を使用し、pwshで1本ずつ前景実行した。パターン検査は初回失敗の修正と追加検査後に再実行し、上表は最終ソースの結果。最終ログは`.userdata/codex-delegation/task-20261103-67b-boss_patterns_test-final.log`と`task-20261103-67b-<残りの検査名>.log`、集計は`task-20261103-67b-results.json`。全4ログでSCRIPT ERROR・Parse Error・FAILは0。終了コードはpwshの実行結果から照合した。環境由来の`Failed to read the root certificate store`は出力されたが、通信は使用していない。

通常描画での録画・人による視認性や難易度・長時間プレイは未確認。禁止された全体テスト、sector_test、generation_test、playthrough、audio_test、streaming_performance、perf系、loop_scaling_testは実行していない。Git・信頼設定／所有者／権限の変更・他agent・commit／push／publish／deployは行っていない。
