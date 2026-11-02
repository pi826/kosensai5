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
