# メインスレッド高速化（2026-11-02）

## 目的と制約

区画生成はワーカースレッド側のため対象外とし、メインスレッドの定常処理と区画切替時の処理を減らした。
当たり判定、物理、数値、乱数、ゲーム進行、同色吸収、異色ダメージ、発射後の弾色保持、一続きのマップ、区画の読み込み順、`streaming_wait` の条件、`T.STREAM_*` の予算、`T.ORIGIN_SHIFT_SECTORS` は変更していない。

## 計測値（依頼時に提示された値）

| 場面 | 平均 | p99 | 最大 | 16.7ms超 |
|---|---:|---:|---:|---:|
| 歩行 3シード 各900フレーム | 6.0-6.4ms | 12-13ms | 15-20ms | 0-2回 |
| 区画を連続で移動（敵 約370体） | 7.4ms | 25ms | 61ms | 53/1800 |
| ラスボス3回後の歩行（敵1754体） | 10.2ms | 18ms | 34ms | 13/900 |
| ラスボス3回後の区画移動 | 12.7ms | 49ms | 132ms | 105/1800 |

今回の変更後に新しい計測は行っていない。

## 変更した項目

1. ミニマップ: `scripts/minimap.gd` で地形版と seed のキャッシュ破棄を先に残し、プレイヤー・視界の地図座標、地形 revision、各発見・取得辞書の件数、`origin_sector`、size、`Art.upload_serial` をキーにした。キーが変わったとき、または最後の再描画から `T.MINIMAP_MAX_STALE_FRAMES`（12、`scripts/tuning.gd`）フレーム経過したときだけ `queue_redraw()` する。`_draw_explored` は区画単位で `biome_at` の結果を辞書に再利用する。仮の game を渡す検査向けに `get`/`has_method` で欠けた項目を保護した。
2. ロックオン: `scripts/main.gd` で `lock_on_targets` は `homing_charges <= 0` のとき `targets_for` を呼ばない。`targets_for` は先に `view_rect().grow(-12)` を作り、画面内判定を先に行う。`_update_lock_marks` は前回印を付けた敵の配列との差分だけを更新し、`start_run` で配列を空にする。
3. 探索: `scripts/main.gd` の `_update_exploration` は視界矩形を1回だけ作り、既探索かつ geometry のあるセルでは残りの書き込みを飛ばす。ボス探索は `scripts/enemy.gd` の `_ready` で `kind == "boss"` のとき追加する `"bosses"` グループを使う。親・生死・削除待ち・画面内の条件と最近ボスの選択は従来と同じ。
4. 敵の画面外経路: `scripts/main.gd` の `is_on_screen` を矩形生成なしのスカラー比較にした。`scripts/enemy.gd` は `_ready` で `kind not in ["flyer", "enhancer"]` を `ground_actor` として求める。`scripts/combatant.gd` の `tick_visuals` は `art_time` を常に進め、画面外で全タイマーが 0 のときだけ残りの減算を省く。画面内の経路は変えていない。
5. UI の再適用: `scripts/art_skin.gd` は `Art.upload_serial` の変化時、`Art._pending` が空なら即時、読み込み中は前回適用から 0.25 秒以上経ったときだけ `_skin` する。読み込み完了後の適用は `Art._pending` が空になった時点で行われる。
6. 区画データの生成専用キー除去: `scripts/sector_job.gd` の `run()` で `world_data` の後に `connection_candidates`、`connection_nodes`、`connections`、`entrances`、`cycles`、`routes`、`gates` を `data` から除く。static の `world_data` と `population_data` に使う `local` は変更していない。
7. 区画取り込みの短縮: `scripts/sector_stream.gd` に `_append_stage(data, first)` と `_count_total_enemies()` を分け、`_refresh_stage` はキーを空にして `loaded.values()` の順に追加する。`service()` の取り込み完了は末尾への `_append_stage` と敵数の数え直しだけにした。解放・原点移動・population 更新・`initialize` は全体を再構築する。`_service_population` の `find_custom` は通常ループにした。
8. 地形の解放と境界更新: `scripts/streamed_terrain.gd` の `_refresh_border` と `unload` は、全 `draw_chunks` 走査の代わりに区画が含むチャンクキーの整数範囲を回す。`draw_chunks.has`、`intersects`、`bounds.has_point` の判定は残した。
9. タイル描画: `scripts/sprite_art.gd` の `draw_tile` で seed と `block_cells.has(cell)` をローカル変数にし、`texture_filter` は値が違うときだけ代入する。

## 変えなかった項目と理由

- 区画生成、`sector_generator.gd`、`stage_generator.gd`、`loot_generator.gd`、`vertical_runs.gd` は対象外の指定のため変更していない。
- 読み込み順、保留条件、`T.STREAM_*`、`T.ORIGIN_SHIFT_SECTORS` は挙動を保つため変更していない。
- 当たり判定、物理、乱数、数値、進行、同色吸収、異色ダメージ、弾色保持は変更していない。
- `--art-set=shapes` と、読めない画像を ID ごとに図形へ戻す動作は変更していない。
- ロックオンの可視判定、探索半径、ボスの発見条件、区画の解放距離は変更していない。

## 検証

指定されたテストを1本ずつ実行し、失敗0を確認した。`run_tests` 1909、`tile_test` 98364、`ui_map_test` 466、`streaming_test` 54、`seamless_test` 147、`stream_redraw_test` 4122、`origin_shift_test` 115、`enemy_types_test` 56、`boss_arrow_test` 91、`merchant_test` 96、`rewards_test` 109、`enhancer_test` 3419、`loop_scaling_test` 33062、`perf_behavior_test` 181。`test.cmd` は `impact_effect_test` の次に `perf_behavior_test` を加え、37 runs の表示にした。全テスト、実プレイでの体感、通常描画の目視は未確認。

## 第2弾（区画切替のスパイク削減）

第1弾の後も残った区画切替時の最大値とp99を対象に、`O.geometry`、原点移動、接地再確認、遠方区画の解放を変更した。当たり判定、物理、数値、乱数、ゲーム進行、同色吸収、異色ダメージ、発射後の弾色保持、一続きのマップ、読み込み半径、解放距離、`T.STREAM_BUDGET_MS`、`T.ORIGIN_SHIFT_SECTORS`、`streaming_wait` の条件は変更していない。

### 計測値（依頼時に提示された値）

| 場面 | 平均 前→後 | p99 前→後 | 最大 前→後 | 16.7ms超 前→後 |
|---|---:|---:|---:|---:|
| 区画を連続で移動（敵 約370体） | 7.39→6.05ms | 25.2→24.0ms | 60.8→62.1ms | 53→51 /1800 |
| ラスボス3回後の区画移動 | 12.68→9.89ms | 48.6→46.3ms | 132→99.7ms | 105→92 /1800 |

- `shift_origin`: 平均26.9ms、最大37ms。`stream.shift_origin` 17.2ms（`O.geometry` 13.1ms、全体再構築約3ms、背景0.9ms）、`terrain.shift_origin` 7.1ms（本体5.0ms、チャンク2.0ms）、worldの子2.6ms。
- `_unload`: 平均10.5ms、最大18.8ms。`terrain.unload` 5.4ms、敵の保存と解放1.4ms（最大4.5ms）、`_refresh_stage` 約3ms。
- 敵1700体では、`terrain.revision` の変化による画面外地上敵の再クエリで6ms以上のスパイクが生じていた。

第2弾の変更後に新しい計測は行っていない。

### 変更した項目

1. `scripts/origin_shift.gd` の `O.geometry` は、配列と辞書の各要素を `typeof` で分岐し、`Rect2` と `Vector2` をその場で変換する。配列と辞書だけ再帰し、それ以外と `PackedVector2Array` はそのまま返す。`patrol` の規則も維持し、戻り値は従来と同じ。
2. `scripts/streamed_terrain.gd` の `shift_origin` は `physics_interpolation` を1回だけ取得し、有効なときだけ `reset_physics_interpolation()` を呼ぶ。`force_update_transform()` は全ノードで維持する。`chunk.shelves` が空なら `O.geometry` と `assign` を省く。
3. 接地再確認を局所化した。`scripts/world_terrain.gd` は `support_serial` と `support_revision_at()` を持ち、`rebuild()` と layer 1 の `_changed()` で増やす。`scripts/streamed_terrain.gd` は区画ごとの `support_revisions` を、変更セルの区画と周囲8区画、区画の取り込み完了、解放完了で更新する。原点移動では増やさない。`scripts/enemy.gd` は `support_seen` が `support_serial` と一致する間、画面外地上敵の地形問い合わせを省く。
4. 遠方区画の地形後片付けを複数フレームに分けた。`begin_unload()` と `unload_step()` はセル128個、surfaces 128個、ブロック1個、本体16個、行1行、描画チャンク1行分を単位とし、最後に区画データ、境界、revision、supportを更新する。同期版 `unload()` は維持した。`scripts/sector_stream.gd` は `_begin_unload()` と `_finish_unload()` に分け、解放中は新しいジョブを取り込まず、毎フレーム最低1 step進める。`_unload()` と `shutdown()` は進行中の解放を完了する。

### レビュー指摘

- A: `scripts/main.gd` の `_update_exploration()` は `boss_view.has_point(actor.position)` に戻した。
- B: `scripts/streamed_terrain.gd` は描画チャンク範囲を `Vector2i(T.SECTOR_SIZE / DRAW_CHUNK_SIZE)` に統一した。
- C: `tests/perf_behavior_test.gd` は原点移動後にも `_refresh_border()` の集合と区画解放後のチャンク・本体を検査する。

### 検証

指定された16本を個別に実行し、全て終了コード0・失敗0。`perf_behavior_test` 222、`streaming_test` 54、`origin_shift_test` 115、`terrain_change_test` 122、`enemy_types_test` 56、`seamless_test` 147、`stream_redraw_test` 4196、`run_tests` 1909、`tile_test` 98364、`ui_map_test` 466、`boss_arrow_test` 91、`boss_cycle_test` 225、`merchant_test` 96、`rewards_test` 109、`enhancer_test` 3419、`loop_scaling_test` 33062。`test.cmd`、指定外のテスト、実プレイでの体感、通常描画の目視は未確認。

## Claudeの計測結果（2026-11-02）

コミット2388945の写しと変更後を、同じ `builds/qa/perf/perf_bench.gd` で各1回測定した。通常描画（NVIDIA GeForce RTX 3060）、`--audio-driver Dummy`、`--fixed-fps 60`、垂直同期なし。画像の読み込み完了を待ってから測る。単位はms。各条件1回の測定なので揺れがある。

「一定速度」は、自機を物理なしで右へ動かし、壁を通り抜けて区画をまたぐ条件。「瞬間移動」は1区画ずつ動かして150フレーム待つ条件で、実際の移動より厳しい。

| 場面 | 平均 | p99 | 最大 | 16.7ms超 |
|---|---:|---:|---:|---:|
| 歩行 シード37（900フレーム） | 6.38→4.78 | 13.44→10.26 | 15.88→12.63 | 0→0 |
| 歩行 シード1（900フレーム） | 6.03→4.48 | 11.64→8.63 | 16.15→11.65 | 0→0 |
| 歩行 シード2026（900フレーム） | 6.33→4.78 | 13.19→9.60 | 17.99→12.20 | 1→0 |
| ラスボス3回後の歩行（敵1754体、900フレーム） | 10.29→7.58 | 17.73→13.12 | 27.79→16.17 | 13→0 |
| 一定速度 320px/秒（3600フレーム） | 6.94→5.13 | 12.01→11.25 | 55.85→39.49 | 23→11 |
| 一定速度 640px/秒（3600フレーム） | 7.82→6.45 | 25.31→16.55 | 69.55→40.38 | 66→33 |
| 瞬間移動（1800フレーム） | 7.36→5.67 | 25.22→14.14 | 62.90→48.28 | 53→11 |
| ラスボス3回後の瞬間移動（1800フレーム） | 12.91→9.46 | 50.74→22.43 | 126.91→80.17 | 117→109 |

原点移動1回の時間は、一定速度320px/秒で平均26.02→20.03ms。一定速度で残る最大値は主にこの原点移動で、320px/秒では約25秒に1回起きる。`T.ORIGIN_SHIFT_SECTORS` は変更していない。

解放の途中でのリスタートと終了は `builds/qa/perf/probe_exit.gd` で確認し、スクリプトエラーは出なかった。

`test.cmd` の全37実行を、時間に関する検査は単独で、generation_test・playthrough・sector_test は並行で直接実行した。37/37が終了コード0、SCRIPT ERRORなし、計287,396項目。第1弾の節の「今回の変更後に新しい計測は行っていない」と各節の未確認の記述は、Codexの実行の記録として残す。

人が遊んだときの体感、ミニマップの更新の見え方、他のGPUでの値は未確認。

## 第3弾（移動後に戻っても重い問題と接敵中の負荷）

開始地点で待つ、移動する、開始地点へ戻る、の3段階を `builds/qa/perf/perf_return.gd` で比較した（開発機、作業ツリーの現状）。

| 段階 | 平均ms | 区画 | 敵 | ノード | 描画コール | 三角形 | 描画オブジェクト |
|---|---:|---:|---:|---:|---:|---:|---:|
| 開始直後に落ち着いた状態 | 3.80 | 25 | 367 | 10,724 | 76 | 4,242 | 1,851 |
| 同じ場所で敵12体と戦闘 | 5.76 | 25 | 367 | 10,738 | 304 | 8,306 | 2,378 |
| 移動して戻った後（敵12体が画面内） | 6.12 | 34 | 497 | 14,673 | 269 | 16,732 | 7,019 |

ミニマップの探索済みセル矩形を消す実験では、描画オブジェクトが7,019→1,925、三角形が16,732→6,544になった。探索セルは28→1,180で、増加の主因はセルごとの `draw_rect` だった。

1. ミニマップ: `scripts/large_map.gd` の `_draw_explored`、`_textures`、`_versions`、`drawn_cells`、`clear_cache` を `scripts/minimap.gd` へ移し、大きな地図は継承して使う。`game.explored_images` があれば区画画像を `draw_texture_rect_region` で描き、仮の game など画像を持たない場合だけ従来のセル矩形へ戻す。`start_run` は大きな地図とミニマップの両方のキャッシュを消す。ミニマップの `texture_filter` は既定のまま、大きな地図は `NEAREST` のまま。
2. 保持区画: `T.STREAM_UNLOAD_DISTANCE` を3、`T.STREAM_UNLOAD_GAP` を2.25にした。`_should_unload` は中心からの距離3以上かつ、プレイヤーから区画矩形までの軸別距離を区画幅・高さで割った最大値が2.25以上のときだけ解放する。完成ジョブの破棄と解放選択の両方で使い、`_return_area_clear` は従来どおり距離3で判定する。解放した区画は `states` に残るため、戻れば同じシードと状態で復元される。
3. 当たり判定: `scripts/world_terrain.gd` と `scripts/streamed_terrain.gd` で `collision_root` を `hide()` する。`StaticBody2D` と `CollisionShape2D` は CanvasItem でも、非表示なら描画の巡回対象から外れる。物理は可視状態に影響されない。
4. ロックオン枠: `scripts/combatant.gd` の8本の `draw_polyline` を、6pxのL字を描く `draw_rect` に置き換えた。暗い色 `Color("07111d")` の太さ5pxを先、白の太さ2pxを後に描く。
5. 輪のAA: `scripts/combatant.gd` の吸収・予告、`scripts/enemy.gd` の強化の灯・強化された敵・field_active、`scripts/laser_beam.gd`、`scripts/bomb.gd`、`scripts/effects.gd` の `draw_arc`・`draw_polyline`・`draw_line` をアンチエイリアスなしにした。図形表示専用の経路は変更していない。
6. 弾の軌跡: `scripts/trail_layer.gd` を追加し、`main.gd` で `projectiles` より先に `world` へ入れる。`_process` は弾がある間と直前のフレームに弾があった間に再描画し、`_draw` は `Bullet` の隣り合う `trail` を `Art.enabled()` の暗い線と `Color(tint, 0.4)` の2層で描く。弾ごとのAA付き `draw_polyline` は削除した。原点移動は従来どおり弾と `trail` を同じ量だけ動かし、層の位置は0のまま。
7. 敵の再描画: `T.ENEMY_REDRAW_INTERVAL` を3にし、`enemy.gd` の `tick_visuals` の第2引数を `on_screen and (Engine.get_physics_frames() + get_instance_id()) % T.ENEMY_REDRAW_INTERVAL == 0` にした。被弾・吸収・撃破・攻撃中断・ロックオンなどの状態変化の `queue_redraw()` は残し、タイマーは毎フレーム更新する。
8. 背景シェーダー: `assets/art/backdrop.gdshader` は `weights` の各成分が0より大きいときだけ、その地域の2枚を `textureLod(..., 0.0)` で読む。0の成分は加算しないため結果の色は同じ。
9. 実機計測: `tests/perf_return_bench.gd` を追加し、`bench.cmd` から実行する。開始時にCPU・GPU・描画ドライバ・ウィンドウサイズ・リフレッシュレート・画面サイズ・スレッド数を表示し、最後に段階ごとの平均・p95・最大・GPU時間・CPU速度の目安（固定計算の時間、増えればクロック低下）・経過秒・描画コール・三角形・区画・敵・画面内の敵をタブ区切りで表示する。`play-angle.cmd` は `--rendering-driver opengl3_angle` を付けてDirect3D 11経由の描画を試す。

検査は `tests/perf_behavior_test.gd` に、ミニマップの画像キャッシュと矩形フォールバック・`start_run` のキャッシュ消去、`_should_unload` の距離と余白、実移動後の保持数、境界往復の解放回数、解放後の状態復元、非表示の当たり判定での着地と弾の衝突、軌跡層の順序と原点移動、敵の再描画間隔とタイマー更新を追加した。既存の閾値は緩めていない。

Ryzen 7 5825U の内蔵GPUでの値、`bench.cmd` と `play-angle.cmd` の実行結果、通常描画の目視は未確認。上の計測値は開発機（i7-12700KF、RTX 3060）のもので、実機の体感を保証しない。

## 第3弾のClaudeの計測結果（2026-11-02）

開発機（i7-12700KF、RTX 3060）の通常描画、`--audio-driver Dummy`、`--fixed-fps 60`、垂直同期なし。各条件1回の測定。単位はms。

`builds/qa/perf/perf_return.gd`（`tests/perf_return_bench.gd` と同じ段階）で、第3弾の前後を比べた。

| 段階 | 平均 前→後 | 描画コール 前→後 | 三角形 前→後 | 区画 前→後 | 敵 前→後 |
|---|---:|---:|---:|---:|---:|
| 開始直後に落ち着いた状態 | 3.80→3.45 | 76→76 | 4,242→3,754 | 25→25 | 367→367 |
| 同じ場所で敵12体と戦闘 | 5.76→4.45 | 304→141 | 8,306→5,248 | 25→25 | 367→367 |
| 移動して戻った後 | 6.12→3.48 | 269→140 | 16,732→4,804 | 34→25 | 497→367 |
| 戻った後に敵24体と戦闘 | 7.09→3.97 | 363→215 | 19,686→5,382 | 34→25 | 497→367 |

描画コールの増え方（`builds/qa/perf/probe_draws.gd`）は、ロックオン枠1体 +24→+1、予告の輪 +4→+2、強化の灯 +10→+6、弾1発 +5→+0.2。敵1体の +3 は変わらない。

`builds/qa/perf/perf_bench.gd` で、コミット2388945の写しと第3弾の後を比べた。

| 場面 | 平均 | p99 | 最大 | 16.7ms超 |
|---|---:|---:|---:|---:|
| 歩行 シード37（900フレーム） | 6.38→4.11 | 13.44→7.17 | 15.88→8.41 | 0→0 |
| 歩行 シード1（900フレーム） | 6.03→3.86 | 11.64→7.02 | 16.15→8.81 | 0→0 |
| 歩行 シード2026（900フレーム） | 6.33→4.08 | 13.19→7.22 | 17.99→9.48 | 1→0 |
| ラスボス3回後の歩行（敵1754体） | 10.29→6.57 | 17.73→11.09 | 27.79→13.05 | 13→0 |
| 一定速度 320px/秒（3600フレーム） | 6.94→3.48 | 12.01→8.03 | 55.85→25.65 | 23→2 |
| 一定速度 640px/秒（3600フレーム） | 7.82→4.04 | 25.31→8.84 | 69.55→25.51 | 66→4 |
| 瞬間移動（1800フレーム） | 7.36→4.57 | 25.22→10.26 | 62.90→44.24 | 53→9 |
| ラスボス3回後の瞬間移動（1800フレーム） | 12.91→8.36 | 50.74→19.00 | 126.91→78.10 | 117→50 |

原点移動1回の時間は、一定速度320px/秒で26.02→15.73ms。一定速度での保留は前後とも0フレーム。

ミニマップは、同じ経路で探索した後の画面を変更前と並べて確認し、ほぼ同じ見た目だった（`builds/qa/perf/minimap-compare.png`）。

`test.cmd` の全37実行を、時間に関する検査は単独で、generation_test・playthrough・sector_test は並行で直接実行した。37/37が終了コード0、SCRIPT ERRORなし、計287,432項目。

Ryzen 7 5825U の実機での値、`play-angle.cmd` の効果、人が遊んだときの体感は未確認。

## ノートPCでの1回目の実機計測（2026-11-02）

ユーザーのノートPC（Ryzen 7 5825U、内蔵GPU）で、第3弾の後の `bench.cmd` を1回実行した。BENCH_ENV の行は共有されていない。単位はms。

| 段階 | 平均 | p95 | 最大 | 描画コール | 三角形 | 区画 | 敵 |
|---|---:|---:|---:|---:|---:|---:|---:|
| A_just_started | 6.97 | 9.24 | 10.21 | 82 | 4,062 | 12 | 176 |
| B_start_sector_settling | 8.02 | 10.15 | 14.06 | 82 | 4,062 | 25 | 367 |
| C_start_sector_settled | 7.58 | 9.47 | 12.42 | 81 | 3,334 | 25 | 367 |
| C2_fight_12_at_start | 8.50 | 10.54 | 12.31 | 138 | 4,102 | 25 | 367 |
| D_two_sectors_away | 6.28 | 8.61 | 11.98 | 116 | 4,306 | 25 | 368 |
| E_further_away | 8.06 | 10.35 | 12.46 | 104 | 4,038 | 30 | 439 |
| F_back_at_start | 12.32 | 14.51 | 17.90 | 117 | 4,546 | 25 | 367 |
| G_back_after_10s | 9.44 | 11.01 | 12.03 | 113 | 4,402 | 25 | 367 |
| H_fight_12_after_travel | 11.40 | 14.07 | 18.90 | 143 | 4,892 | 25 | 367 |
| I_fight_24_after_travel | 14.02 | 17.24 | 29.84 | 205 | 5,014 | 25 | 367 |

戻った後の区画・敵の数は開始時と同じで、描画コールと三角形も開始時に近い。一方、同じ敵12体の戦闘が C2 8.50ms から H 11.40ms に増えた。開発機では C2 4.45ms、H 3.53ms で差がない。この版のベンチは C2 で集めた敵を戻さないため、F・G には敵12体が画面内にいて C とは比べられない。時間経過によるクロック低下とゲーム状態のどちらが原因かを区別するため、ベンチに戦闘後の敵の復元、開始地点での再測定（C3、J）、GPU時間、CPU速度の目安、経過秒を追加した。
