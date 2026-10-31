# Task 8C: CC0素材への音の差し替え

**自動検査は直接実行で35/35成功（184,430項目、2026-10-31）。** Codexのサンドボックス内の実行では音検査の時間条件だけが不安定に失敗し、基準コードでも同じ検査が失敗した。サンドボックス外の直接実行では失敗しない。原因は特定していないため、時間条件は実行環境の負荷に左右されるものとして扱う。人の試聴は未実施。

2026-10-30。ユーザーの指示（原文）：「インターネットから使えそうなものを取ってきてやってみてください．」

承認済み・配置済みの Juhani Junkala の素材を使い、効果音58 IDと曲4枠を差し替えた。環境音6種、win/lose、boss曲は8Bの合成を使う。ゲーム側の発音条件・ID・位置・タイミングは維持する。既定はassets、`-- --sound-set=synth`で全て8B合成に戻せる。`-- --sound-set=assets`で明示指定も可能。headless既定は両方の準備を省略し、`-- --audio-synthesis=on`で音を有効にする。

合成音で起動する具体的なコマンド（play.cmdは引数を転送しないのでGodot本体へ渡す）：

```powershell
$env:APPDATA = "$PWD\.userdata"
& .\tools\godot\Godot_v4.7.2-stable_win64.exe --path . -- --sound-set=synth
```

## 出典と変更方法

- 作者：Juhani Junkala（OpenGameArtのアカウント名 SubspaceAudio）。両ZIP同梱INFOにCC0と明記。配布ページへの今回のアクセスは403で再取得できなかった。
- 曲：[5 Chiptunes (Action)](https://opengameart.org/content/5-chiptunes-action)。ZIP SHA-256 `ea189990c0fb9a700187ccc740eda72400341a082305a163867467d96346460d`。
- 効果音：[512 Sound Effects (8-bit style)](https://opengameart.org/content/512-sound-effects-8-bit-style)。ZIP SHA-256 `6d4519229c6e2c9e09502cd4967940052f68664140549a467615b56bdfd1d031`。
- 両ZIPのハッシュ、使った59 WAVとZIPメンバーのバイト一致を確認した。ファイル別の元の場所・配置先・ID・SHA-256は [CREDITS](../assets/audio/CREDITS.md)。Endingは未使用。

`scripts/sound_assets.gd`のEFFECTS/MUSICの各1行（path/pitch/gain_db）で差し替える。SHA256は原本検証用で、別の素材へ替える際には更新する。directorの`sound_set_override`（空文字/synth/assets）はready前に設定するテスト用変数。Mainを作るテストでは同名のmetadataをready前に渡せる。`asset_paths_override`は欠損検査用。読み込めなかったIDだけを合成へ戻し、そのIDの警告はdirectorの生存期間に1回。

## 音量の計測

`tests/audio_test.gd`のBS.1770 K特性関数を再利用。係数を実際の標本化周波数から算出する。効果音は指定pitchを44100Hzの線形補間再サンプリングで反映し、gainは浮動小数点の振幅倍率で反映。ゼロ初期状態と末尾50msゼロ入力を含む、1標本ずつの固定50ms窓RMSの最大を比較した。ピークの上限は元の全サンプルの最大から求めるため、線形補間後も上限を超えない。既存ゲーム側の追加音程倍率は実行時にさらに掛ける。

曲は末尾0.5秒でフィルターを予熱し、1ループ全体を計測。ステレオは左右の平均二乗の和を取り、チャンネル数では割らない。LUFSのゲートや-0.691補正は使わない。44100Hz正弦波の解析応答と同一左右チャンネルで+3.0103dBになる検査も追加した。曲は元WAVと、Godotのmix_audioでデコードしたQOAを別々に再検証する。

gainは目標との差（効果音はピーク-1dBFS上限も適用）を一度計算し、小数8桁の定数にした。58 ID全てがピーク制約内で目標に到達し、ピーク制約による不足IDはない。許容は効果音±1.0dB、曲±0.5dB。補助コードと原数値はbuilds/qa/sound/assets/、実行記録は下記のrunディレクトリに保存する。

### 効果音

パスは全てassets/audio/sfx/からの相対名。K値とピークはdB、長さは指定pitch適用後の秒。K素材はgain適用後。

| ID | ファイル | pitch | gain_db | K合成8B | K素材 | peak dBFS | 秒 |
|---|---|---:|---:|---:|---:|---:|---:|
| ability_get | sfx_sounds_powerup1.wav | 1.00 | -8.26989 | -14.202 | -14.202 | -14.269 | 0.835896 |
| absorb_a | sfx_coin_double4.wav | 1.00 | -5.78003 | -14.481 | -14.481 | -11.781 | 0.263220 |
| absorb_b | sfx_coin_double4.wav | 0.67 | -4.86440 | -14.618 | -14.618 | -10.865 | 0.392866 |
| aim | sfx_menu_move4.wav | 1.00 | -17.00464 | -29.999 | -29.999 | -23.005 | 0.048934 |
| air_jump | sfx_movement_jump10.wav | 1.00 | -4.59199 | -20.875 | -20.875 | -10.590 | 0.110227 |
| arrow_unlock | sfx_sounds_powerup7.wav | 1.00 | -9.33793 | -15.525 | -15.525 | -15.338 | 0.664467 |
| block_break | sfx_exp_shortest_hard5.wav | 1.00 | -9.03416 | -18.345 | -18.345 | -15.074 | 0.283039 |
| bomb_explode | sfx_exp_short_hard10.wav | 1.00 | -3.02907 | -11.926 | -11.926 | -9.069 | 0.550317 |
| bomb_warn | sfx_wpn_grenadewhistle1.wav | 1.00 | -20.34177 | -26.458 | -26.458 | -26.341 | 0.975215 |
| boss_appear | sfx_movement_portal2.wav | 1.00 | -3.45821 | -9.087 | -9.087 | -9.498 | 2.185578 |
| boss_defeat | sfx_exp_cluster9.wav | 1.00 | -0.85301 | -9.552 | -9.552 | -6.893 | 2.268435 |
| boss_hit | sfx_sounds_impact8.wav | 1.00 | -11.17521 | -18.341 | -18.341 | -17.173 | 0.139546 |
| boss_shot | sfx_weapon_singleshot21.wav | 1.00 | -13.70151 | -21.900 | -21.900 | -19.700 | 0.128163 |
| buy | sfx_coin_double2.wav | 1.00 | -10.32853 | -16.451 | -16.451 | -17.840 | 0.325057 |
| charge | sfx_sounds_powerup8.wav | 1.00 | -4.97093 | -12.291 | -12.291 | -10.970 | 0.393946 |
| chest_locked | sfx_sounds_error15.wav | 1.00 | -16.97861 | -24.955 | -24.955 | -23.019 | 0.198821 |
| chest_open | sfx_sounds_interaction10.wav | 1.00 | -5.12665 | -13.662 | -13.662 | -11.124 | 0.291610 |
| crystal | sfx_coin_single3.wav | 1.00 | -11.35113 | -21.154 | -21.154 | -17.351 | 0.131429 |
| dash | sfx_wpn_sword1.wav | 1.00 | -16.25886 | -20.647 | -20.647 | -22.259 | 0.110816 |
| death | sfx_deathscream_robot2.wav | 1.00 | -0.44118 | -11.460 | -11.460 | -6.521 | 0.753197 |
| deny | sfx_sounds_error3.wav | 1.00 | -10.51735 | -25.237 | -25.237 | -17.002 | 0.210930 |
| empty | sfx_wpn_noammo3.wav | 1.00 | -11.61640 | -28.750 | -28.750 | -17.699 | 0.171973 |
| enemy_absorb | sfx_sounds_interaction9.wav | 1.00 | -15.55024 | -24.617 | -24.617 | -21.549 | 0.056032 |
| enemy_defeat | sfx_exp_shortest_hard2.wav | 1.00 | -9.55918 | -15.469 | -15.469 | -15.599 | 0.185397 |
| enemy_hit | sfx_damage_hit1.wav | 1.00 | -14.04643 | -23.157 | -23.157 | -20.044 | 0.059297 |
| enemy_homing | sfx_wpn_missilelaunch.wav | 1.00 | -17.40339 | -26.565 | -26.565 | -23.403 | 0.782948 |
| enemy_shot | sfx_weapon_singleshot14.wav | 1.00 | -26.21962 | -34.579 | -34.579 | -32.219 | 0.049637 |
| enemy_switch | sfx_sounds_Blip6.wav | 1.00 | -19.80250 | -28.107 | -28.107 | -25.801 | 0.101066 |
| enemy_warn | sfx_sounds_Blip11.wav | 1.00 | -23.99475 | -33.520 | -33.520 | -29.994 | 0.089773 |
| enemy_warn_special | sfx_lowhealth_alarmloop6.wav | 1.00 | -11.38742 | -24.652 | -24.652 | -17.428 | 0.300045 |
| enhancer_defeat | sfx_exp_short_hard1.wav | 1.00 | 0.12555 | -9.138 | -9.138 | -5.915 | 0.602472 |
| equip | sfx_menu_select2.wav | 1.00 | -14.24646 | -20.529 | -20.529 | -20.246 | 0.305034 |
| glide | sfx_wpn_sword3.wav | 0.85 | -13.68390 | -25.013 | -25.013 | -19.683 | 0.161398 |
| heal | sfx_sounds_powerup13.wav | 1.00 | -7.87423 | -15.022 | -15.022 | -13.872 | 0.425420 |
| homing | sfx_wpn_laser6.wav | 1.00 | -9.95340 | -19.170 | -19.170 | -15.953 | 0.491973 |
| hurt | sfx_sounds_damage3.wav | 1.00 | -0.65439 | -14.101 | -14.101 | -6.655 | 0.172925 |
| item_get | sfx_sounds_powerup12.wav | 1.00 | -7.80302 | -15.198 | -15.198 | -13.802 | 0.608322 |
| jump | sfx_movement_jump1.wav | 1.00 | -16.74152 | -22.526 | -22.526 | -22.741 | 0.139365 |
| key | sfx_sounds_powerup10.wav | 1.00 | -5.20769 | -13.554 | -13.554 | -11.207 | 0.254308 |
| land | sfx_movement_jump12_landing.wav | 1.00 | -5.89107 | -23.420 | -23.420 | -18.471 | 0.100136 |
| laser_charge | sfx_sound_poweron.wav | 1.00 | -13.75788 | -22.807 | -22.807 | -19.758 | 1.608435 |
| laser_fire | sfx_wpn_laser12.wav | 1.00 | -9.85336 | -19.706 | -19.706 | -15.854 | 0.679410 |
| loop_up | sfx_alarm_loop8.wav | 1.00 | -12.11440 | -18.066 | -18.066 | -18.195 | 0.702404 |
| map_close | sfx_sounds_pause6_out.wav | 1.00 | -9.58370 | -24.995 | -24.995 | -15.664 | 0.377324 |
| map_open | sfx_sounds_pause6_in.wav | 1.00 | -8.73237 | -22.909 | -22.909 | -17.549 | 0.376871 |
| pause | sfx_sounds_pause2_in.wav | 1.00 | -10.92198 | -23.537 | -23.537 | -17.002 | 0.259773 |
| potion | sfx_sounds_powerup15.wav | 1.00 | -13.10758 | -20.836 | -20.836 | -19.106 | 0.187732 |
| shop_open | sfx_sounds_pause7_in.wav | 1.00 | -11.46243 | -21.049 | -21.049 | -17.711 | 0.520272 |
| shot_a | sfx_wpn_laser2.wav | 1.00 | -21.55264 | -24.723 | -24.723 | -27.552 | 0.116100 |
| shot_b | sfx_wpn_laser2.wav | 0.75 | -19.73346 | -23.661 | -23.661 | -25.732 | 0.154800 |
| switch_a | sfx_sounds_interaction14.wav | 1.26 | -9.39476 | -17.571 | -17.571 | -15.396 | 0.110535 |
| switch_b | sfx_sounds_interaction14.wav | 0.84 | -8.65630 | -17.321 | -17.321 | -14.658 | 0.165803 |
| tutorial_step | sfx_sounds_fanfare3.wav | 1.00 | -3.55087 | -15.117 | -15.117 | -9.549 | 0.285714 |
| ui_back | sfx_sounds_Blip9.wav | 1.00 | -18.02341 | -25.960 | -25.960 | -24.021 | 0.065397 |
| ui_confirm | sfx_menu_select5.wav | 1.00 | -17.23657 | -21.733 | -21.733 | -23.237 | 0.360136 |
| ui_move | sfx_menu_move2.wav | 1.00 | -16.55777 | -30.178 | -30.178 | -22.558 | 0.060113 |
| wall_place | sfx_sounds_impact12.wav | 1.00 | -17.36432 | -25.279 | -25.279 | -23.362 | 0.277619 |
| wall_vanish | sfx_sounds_high5.wav | 1.00 | -24.66939 | -29.848 | -29.848 | -30.669 | 0.295170 |

合成のまま：amb0_drop, amb0_ripple, amb1_chime, amb1_ring, amb2_ember, amb2_metal, win, lose。

### 曲

長さは元WAVの1周。境界段差は左右の大きい方の正規化振幅、前後50ms RMS差は左右の二乗を合算した絶対dB差。素材の継ぎ目は原本のままで、補正・切り詰め・正規化はしていない。

| ID | ファイル | 秒 | K合成8B | K元WAV | gain_db | K調整後 | peak調整後 | 原本境界段差 | 原本前後50ms差dB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| title | junkala_title_screen.wav | 11.294127 | -15.702 | -7.591 | -8.11093 | -15.702 | -8.111 | 0.040100 | 6.567 |
| region0 | junkala_level1.wav | 74.254150 | -15.509 | -6.401 | -9.10720 | -15.509 | -9.107 | 0.161926 | 5.807 |
| region1 | junkala_level2.wav | 72.796213 | -15.822 | -6.161 | -9.66098 | -15.822 | -9.661 | 0.534760 | 4.747 |
| region2 | junkala_level3.wav | 81.895760 | -16.110 | -6.404 | -9.70627 | -16.110 | -9.706 | 0.095306 | 0.870 |
| boss | 8B合成 | 27.906984 | -14.641 | -14.641 | 0 | -14.641 | -3.719 | 0.000519 | 4.411 |

元のtitleは前後50ms差6.567dB、region1は境界段差0.534760。作者のループ用途の説明とは別に、この実測値では継ぎ目の聴感は判断できない。人による2周試聴が必要。WAVを変更しない条件を守り、Godotのループを全長に設定した。

QOAデコード後のK値（gain込み）：title -15.739dB、region0 -15.544dB、region1 -15.871dB、region2 -16.141dB、全て合成目標との差0.5dB以内。

## 取り込みと実行時

効果音は44100Hz/mono/16bit PCM、loopなし。曲は44100Hz/stereo/QOA、Forward、開始0・末尾は全サンプル数。全59ファイルでtrim/normalizeはfalse。Godotのloop_end=-1は最後の1フレームが範囲から外れることを初回検査で発見したため、4曲には全フレーム数を明示した。.importを更新して通常のheadless --importを実行。project.godotは基準と同じで、自動変更はない。

効果音と曲はResourceLoader.load_threaded_requestで準備し、LOADEDを確認したものだけload_threaded_getで受け取る。キュー登録・回収をフレームごとの約1.5ms予算に分け、個々の操作とサービス全体を計測する。共有元ファイルは同じstreamを使う。raw WAVをゲームのメインスレッドで解析しない。割り当て済みIDを合成スレッドの処理対象から外し、残りの相対順序を保つ。欠損IDは追加の低優先度合成で補う。

効果音のpitchは既存の倍率に掛け、gainは減衰前の基準音量にも加える。untilは実際のplayer.pitch_scaleから計算する。曲のgainは各スロットの一貫したオフセットで、クロスフェード、ボス曲の先頭再開、duck、結果の-9dBと復帰を保つ。音量増加制限は従来のエンベロープと実出力の双方で維持する。

別の新規プロセスでの起動計測（OSファイルキャッシュの排除はしていない）：効果音 420.765ms、title 420.766ms。素材サービス最大 2.848ms、個別の登録/確認/回収操作最大 0.239ms。director初期設定 0.605ms。全フレーム経過最大 24.078msはゲーム側処理や待機も含み、素材処理の停止時間とは区別する。

素材streamの重複を除いたdata合計 10517890 bytes（10.031 MiB）で16MiB以下。合成boss等の予備9音のPCMとプロセス全体のメモリはこの数値に含めない。

## 検査と記録

この節はCodexのサンドボックス内での実行記録。

実行記録：builds/qa/sound/assets/run-20261030-203637/。全てAPPDATA=.userdata、--audio-driver Dummy。Gitコマンド・信頼設定・所有者・権限は使わず/変更せず、Claudeが用意したbaseline-1aac42cのSHA256SUMSと開始時作業ファイルの一致を確認して比較した。

エンジン起動時間を含めた完成時刻：効果音 1110.719ms、title 1110.720ms（シーン生成前 689.954ms）。1.3秒/3.0秒の目標内。

- 合成PCM：別名コピーした基準bankと今回のbankを各々実行し、全66効果音＋5曲の71本がバイト一致（calibration.jsonにSHA-256）。素材モードで残る9本も合成検査で基準PCMとの一致と処理順を確認する。
- 初回音検査：42,677項目、4失敗（4曲のloop_end）。その後の全長指定で修正した。ログは破棄しない。
- Codexのサンドボックス内で test.cmd と同一引数を実行した結果：34/35。

| 実行 | 終了コード | 項目数 |
|---|---:|---:|
| 1: tests/generation_test.gd  | 0 | 21785 |
| 2: tests/run_tests.gd  | 0 | 940 |
| 3: tests/movement_test.gd  | 0 | 77 |
| 4: tests/key_bindings_test.gd  | 0 | 220 |
| 5: tests/tile_test.gd  | 0 | 50 |
| 6: tests/seamless_test.gd  | 0 | 147 |
| 7: tests/camera_test.gd  | 0 | 19 |
| 8: tests/playthrough.gd  | 0 | 101 |
| 9: tests/enemy_types_test.gd  | 0 | 56 |
| 10: tests/terrain_change_test.gd  | 0 | 122 |
| 11: tests/cave_world_test.gd  | 0 | 25 |
| 12: tests/sector_test.gd  | 0 | 68692 |
| 13: tests/streaming_test.gd  | 0 | 54 |
| 14: tests/streaming_performance.gd  | 0 | 21 |
| 15: tests/rewards_test.gd  | 0 | 109 |
| 16: tests/boss_cycle_test.gd  | 0 | 225 |
| 17: tests/tutorial_test.gd  | 0 | 292 |
| 18: tests/origin_shift_test.gd  | 0 | 115 |
| 19: tests/test_guard_test.gd  | 0 | 4 |
| 20: tests/ability_physics_test.gd  | 0 | 36 |
| 21: tests/abilities_test.gd  | 0 | 53 |
| 22: tests/ability_generation_test.gd  | 0 | 1088 |
| 23: tests/merchant_generation_test.gd  | 0 | 671 |
| 24: tests/equipment_physics_test.gd  | 0 | 180 |
| 25: tests/merchant_test.gd  | 0 | 96 |
| 26: tests/boss_arrow_test.gd  | 0 | 91 |
| 27: tests/ui_map_test.gd  | 0 | 442 |
| 28: tests/enhancer_test.gd  | 0 | 3419 |
| 29: tests/loop_scaling_test.gd  | 0 | 33062 |
| 30: tests/streaming_performance.gd --loop-three | 0 | 24 |
| 31: tests/diagonal_test.gd  | 0 | 1033 |
| 32: tests/diagonal_physics_test.gd  | 0 | 259 |
| 33: tests/shaft_test.gd  | 0 | 3406 |
| 34: tests/stream_redraw_test.gd  | 0 | 4705 |
| 35: tests/audio_test.gd  | 1 | 42921 |

計 184540 項目。詳細はsuite/results.jsonと各stdout/stderr。

初回の30番・周回3性能は終了コード1：physics平均 18.649msが16.667msの条件を超えた。音は省略され、director平均 0.123ms。閾値は変更しなかった。初回の結果とログを残し、同じ引数で再実行した。
基準audio_directorの別名コピーへ差し替えたQA用Mainでの比較検査は、physics平均 12.404ms、失敗0。fixture以外のベンチマーク処理・閾値は同一。初回との差だけから音コードが原因とは判断していない。
今回のコードの再実行はphysics平均 12.006ms、失敗0。初回性能の変動要因は未確定。

- 音検査 builds/qa/sound/assets/audio-2026-10-30T222659-2760/audio-results.json：42921項目、失敗1。素材startup：effects 983.556ms、title 983.558ms、service最大 3.920ms。

- 音検査 builds/qa/sound/assets/audio-2026-10-30T223035-43728/audio-results.json：42921項目、失敗6。素材startup：effects 1362.270ms、title 1362.270ms、service最大 6.122ms。

- 音検査 builds/qa/sound/assets/audio-2026-10-30T223636-44756/audio-results.json：42921項目、失敗6。素材startup：effects 1238.243ms、title 1238.243ms、service最大 3.778ms。

音検査の失敗内容（builds/qa/sound/assets/audio-2026-10-30T222659-2760/audio-results.json）：title ready before 4s。 合成title準備 4098.142ms、全合成 15291.385ms。

音検査の失敗内容（builds/qa/sound/assets/audio-2026-10-30T223035-43728/audio-results.json）：title ready before 4s / total synthesis before 20s / title: synthesis <4s / region2: synthesis <4s / boss: synthesis <4s / asset effects ready <=1.3s。 合成title準備 6232.045ms、全合成 25400.933ms。

音検査の失敗内容（builds/qa/sound/assets/audio-2026-10-30T223636-44756/audio-results.json）：title ready before 4s / all effects ready before 2s / total synthesis before 20s / title: synthesis <4s / region0: synthesis <4s / region1: synthesis <4s。 合成title準備 9889.743ms、全合成 28367.605ms。

基準bank/今回bankを同じ小さなQAループで順に実行した比較：title準備 1439.523 / 3499.274ms、全合成 9078.873 / 13323.462ms。PCMは再び71/71本がバイト一致。開始時の計測との差・実行間の変動要因は未確定で、省略分岐の追加が原因とは断定していない。CPUクロック情報の取得はアクセス拒否で未確認とし、権限やシステム設定は変更しなかった。

基準プロジェクトによる元の音検査：scripts/audio_director.gd・sound_bank.gd・tests/audio_test.gd・project.godotを基準の写しにした隔離プロジェクトで、元の音検査を同じheadless/Dummy/fixed-fps=60で実行。40109項目、失敗1。失敗内容：title ready before 4s。合成title準備 4116.732ms、全合成 15053.347ms。今回の追加検査や素材を使わない元の検査でも合成準備時間の超過を再現した。基準の検査・音コードのSHA-256一致は記録する。

追加実行：
- audio-repeat：終了コード1、42921項目。
- streaming-assets-normal：終了コード0、21項目。
- streaming-assets-loop-three：終了コード0、24項目。
- startup-final：終了コード0、5項目。

素材有効時のstreaming_performance実測（ms）。全体の処理時間と素材サービスの時間は別に示す。

| 条件 | main平均 | physics平均 | physics p95 / p99 | 発音込みdirector平均 / 最大 | 素材サービス最大 | 素材loaded |
|---|---:|---:|---:|---:|---:|---:|
| streaming-assets-loop-three | 5.000 | 10.714 | 16.582 / 24.704 | 0.092 / 1.731 | 1.574 | 62 |
| streaming-assets-normal | 1.902 | 3.951 | 7.016 / 12.477 | 0.082 / 1.814 | 1.716 | 62 |

assetsグループで割り当て全域、原本ハッシュ、PCM/mono/44100Hz/no loop、trim/normalizeなし、QOA/stereo/全長Forward、K音量・ピーク、素材と合成の選択、gain/pitch/until、結果・duckのオフセット、1 ID欠損からの復帰、素材あり/なし1800フレームの完全状態一致を検査。元のstartup、波形、energy、発音、重なり、画面・結果遷移と合成あり/なし1800フレームの検査は維持した。

既存検査で変更した箇所：startup_testのMainとrunの最初のMainにsound_set_override=synthを明示した。波形・energyは従来通りbankの全合成出力で検査。既存check式・閾値は変更していない。K計測関数だけを任意pitch/gain/channelとステレオ合算へ拡張し、既存mono/倍率1の結果は維持した。OUTは既存8Bの記録を上書きしない日時・PID入りassets/audio-*へ変更した。tests/audio_preview.gdは変更せず、今回のプレビュー生成はQA内の一回限りの補助スクリプトで行う。

全実行でGodotのroot certificate store読込エラーが出る環境だった。素材はローカルから読み、ネットワークや証明書設定は変更していない。欠損検査によるshot_aの警告は意図した1回のもの。終了コードとSCRIPT ERROR/FAILは別々に確認する。

試聴ファイル：builds/qa/sound/preview-assets/se_sampler.wavとse_sampler.txt（従来と同じIDの辞書順を全66 IDへ適用）、title/region0/region1/region2/boss-two-loops.wav。素材はgain/pitchを適用、残す合成音は同じPCM。曲の素材試聴は元WAVにgainを適用した2周で、bossは合成2周。preview/とpreview-8a/は変更しない。

## 直接実行での確認（2026-10-31）

Codexのサンドボックス外で、Claudeが実行した。全てAPPDATA=.userdata、--audio-driver Dummy。

- test.cmdの全35実行：35/35が終了コード0、184,430項目、SCRIPT ERRORなし。
- 音検査は全体の実行とは別にもう1回実行し、2回とも42,921項目で失敗0。
- 全35実行の中の音検査の時間：素材の効果音 1214.576ms、title 1214.577ms、素材サービス最大 4.915ms、個別操作最大 3.978ms、素材データ 10,517,890 bytes。合成はエンジン起動から効果音 1041.44ms、title 2057.689ms。
- 素材の効果音の条件1.3秒に対する余裕は約0.09秒で、サンドボックス内では1.362秒の超過が1回あった。

通常のウィンドウ起動（メインシーン、Dummyオーディオ）：

| 指定 | 全71音の準備 | sound_set | 素材 | 合成へ戻したID |
|---|---:|---|---:|---:|
| なし | 1.8秒 | assets | 62 | 0 |
| --sound-set=synth | 5.9秒 | synth | 0 | 0 |

`.godot/` のないコピー（クローン直後と同じ状態）をheadlessで起動した結果：素材0、合成へ戻したID 62、全71音の準備8.1秒、終了コード0、警告はID当たり1回の計62回。ゲームは合成音で動く。素材を使うには一度インポートが必要（open-editor.cmdでエディターを開く、または `--headless --path . --import`）。`.godot/` はGit管理外のため、クローンのたびに必要。

曲の継ぎ目を、曲中の標本間の差と隣接50ms窓のRMS差の分布と比べた。

| 曲 | 境界段差 | 曲中の順位 | 曲中99.9パーセンタイル | 前後50ms差dB | 曲中の順位 |
|---|---:|---:|---:|---:|---:|
| title | 0.040 | 54.0% | 0.680 | 6.57 | 93.8% |
| region0 | 0.162 | 85.1% | 0.742 | 5.81 | 96.4% |
| region1 | 0.535 | 99.4% | 0.802 | 4.75 | 90.0% |
| region2 | 0.095 | 54.0% | 0.760 | 0.87 | 24.3% |

どの値も曲中で普通に現れる範囲で、数値からは継ぎ目の異常は見つからなかった。聞こえ方は未確認。

## 変更ファイルと未確認事項

変更：scripts/audio_director.gd、scripts/sound_bank.gd、tests/audio_test.gd、README.md、docs/roadmap_v2.md。
追加：scripts/sound_assets.gd、assets/audio/CREDITS.md、assets/audio/sfx/の55 .wav.import、assets/audio/music/の4 .wav.import、docs/task8c_asset_sound.md。補助スクリプト・基準の別名コピー・ハッシュ/計測/検査ログはbuilds/qa/sound/assets/、試聴ファイルはbuilds/qa/sound/preview-assets/。WAV 59本は配置時のまま。作業開始前の未追跡.claude/、CLAUDE.md、docs/claude_codex.mdは変更しない。test.cmd、project.godot、tests/audio_preview.gdも基準と同じ。最終のファイル別一覧・ハッシュ・非Git差分はrunのchange-audit.json/diffs/に保存する。.godot/は通常インポートのキャッシュ更新。

未確認：人の耳による音量・曲の継ぎ目・長い効果音の余韻・場面への適合、スピーカー/実機の遅延、通常描画での聴取、OSファイルキャッシュを排除したコールドディスクでの起動時間。Dummyによる自動検査から聴感の良否は判断していない。