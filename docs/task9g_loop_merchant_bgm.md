# Task 9G-1: 通常敵の二段階強化と商人の増加

## 通常敵の強化と商人

ラスボス撃破回数 c（0〜3）を、敵の数と能力の2段階に分けた。数は奇数回、能力は偶数回の撃破で上がる。数は追加配置の段階、能力はHP・与ダメージ・攻撃速度・移動速度に使う。ボスとチュートリアルは従来どおり対象外。

| 撃破 c | 数の段階 ceil(c/2) | 能力の段階 floor(c/2) | 通常敵HP | 通知 |
|---|---|---|---|---|
| 0 | 0 | 0 | ×1 | なし |
| 1 | 1 | 0 | ×1 | 敵の数が増えた |
| 2 | 1 | 1 | ×3 | 敵が強くなった |
| 3 | 2 | 1 | ×3 | 敵の数が増えた |

- 数の段階1・2は、通常敵の初期配置に対してそれぞれ+1倍・+2倍の追加配置（人口倍率は 1、2、2、3）。`LOOP_COUNT_CAP = 3` とし、段階3は予約しない。
- 能力の段階ごとに HP ×3、与ダメージ +20%、攻撃速度 +15%、移動速度 +10%。能力の段階は最大1。
- 既存の敵への能力適用、追加配置の予約、`loop_up` 音、初回撃破時の装備強化メッセージの流れは維持している。

商人は `MERCHANT_CHANCE` を 0.2 から 0.6 に変更した。開始区画は必ず1人、1区画の最大1人は維持。乱数の消費順は変えていないため、従来商人がいた区画には必ず商人がいる。

- `merchant_generation_test` の200区画実測: 変更前 36人 → 変更後 117人。

## 検査

最後の変更後に以下を個別に実行し、すべて終了コード0・失敗0・SCRIPT ERRORなし。

- `loop_scaling_test`: 22,391 checks、失敗0
- `boss_cycle_test`: 248 checks、失敗0
- `merchant_generation_test`: 1,076 checks、失敗0、商人117/200
- `merchant_test`: 98 checks、失敗0
- `equipment_upgrade_test`: 217 checks、失敗0
- `enhancer_test`: 3,420 checks、失敗0
- `rewards_test`: 109 checks、失敗0
- `streaming_performance`（通常）: 21 checks、失敗0
- `streaming_performance -- --loop-three`: 24 checks、失敗0（数の段階2・能力の段階1、通常敵1,316体で開始）

## 未確認

- 人は遊んでいない。二段階化による難易度の体感、商人3倍による金策・装備購入のテンポ、追加敵による実プレイ時の負荷は未確認。
- 本タスクでは全体の `test.cmd`・`generation_test`・`sector_test`・`playthrough` は実行していない。

## 天井からの攻撃への対処

### 原因

ボスは Task 9F 以降、画面内、または自機が自分のアリーナ内にいるときに移動と進行中の攻撃を続けていた。しかし、新しい攻撃の開始判定と `build_clock` の減算は画面内のときだけだった。重力反転で天井を歩く自機は、カメラの縦補正も通常の重力と同じ上向きのままで、画面には自機の下約160pxしか映らなかった。このため、自機がボスのアリーナ内にいてもボスはほぼ常に画面外となり、新しい攻撃を開始しなかった。自機の弾は画面外のボスにも当たるため、一方的に攻撃できた。

### 変更

- `scripts/enemy.gd`: ボスでは `on_screen or _player_in_arena()` を新しい攻撃の開始条件にした。自機がアリーナ内なら画面外でも `build_clock` を進め、`_choose_attack()` を呼ぶ。自機がアリーナ外なら従来どおり画面内だけで開始する。通常敵の挙動、ボスのウェイク時間、攻撃の種類・弾速・間隔・色は変えていない。
- `scripts/main.gd`: `camera_target()` の縦補正を `-T.CAMERA_VERTICAL_OFFSET * gravity_sign` にした。重力反転時は注視点が自機の下側になり、天井を歩く自機は画面の上寄りに映る。`gravity_sign` がない場合は1として扱い、通常重力の結果、dead zone、追従速度、先読みは変えていない。

### 検査と結果

`boss_patterns_test` は guardian・final・secret の各役割で、重力反転した自機をアリーナ中央上部の天井に固定し、ボスを画面外の下側に置いて検査した。

| 役割 | 初回攻撃 | 初弾 | 自機方向の弾 | 被弾 | 体力 |
|---|---:|---:|---:|---:|---:|
| guardian | 0.017s | 0.483s | 0.483s | 3.483s | 100 → 88 |
| final | 0.017s | 0.483s | 0.483s | 3.567s | 100 → 82 |
| secret | 0.017s | 0.483s | 0.483s | 3.567s | 100 → 82 |

同じ配置で自機をアリーナ外へ出した場合は、3役割ともボスの行動が `idle`、敵弾0発で、画面外から新しい攻撃を開始しなかった。最終実行は1,362 checks、失敗0。

- `boss_cycle_test`: 248 checks、失敗0
- `boss_arena_test`: 4,572 checks、失敗0
- `gravity_test`: 87 checks、失敗0
- `camera_test`: 22 checks、失敗0。反転時の自機の画面yは180（画面高720の中心360より上）で、注視点は自機の下。通常重力の注視点は変更前と同じ。
- `movement_test`: 87 checks、失敗0
- `tutorial_test`: 373 checks、失敗0
- `dash_aim_test`: 56 checks、失敗0

経路計算の初回時間は負荷で揺れた。一括実行では初回8.765ms（中央値1.111ms、閾値6ms）で当該検査だけ失敗したが、経路処理は変更しておらず、再実行は初回5.849ms（中央値1.996ms）で失敗0だった。閾値は変更していない。

### 人が遊んで確かめていないこと

- 天井から攻撃する戦闘の難しさ、ボス弾を避けながら撃つテンポ、被弾までの3.5秒が適切かは人が遊んでいない。
- 重力反転時にカメラがボスと自機の下側アリーナを見やすいかは、実際の画面で確認していない。
- 全体の `test.cmd` は本タスクでは実行していない。

## BGM の選択

BGM は `standard`（既定）・`dark`・`junkala` の3セットから選べる。`scripts/music_sets.gd` が手書きの対応表を持ち、生成ファイル `scripts/sound_assets.gd` は変更していない。`standard` は従来の HydroGene 5曲、`dark` は同じ HydroGene パックの別5曲、`junkala` は Juhani Junkala の4曲と、曲のない `boss` を `sound_bank.gd` の合成で鳴らす。効果音・環境音・発音条件・ID・`audio.cfg` は3セット共通で従来のまま。

### 曲と音量

K は `DSP.k_music_rms_db(DSP.decoded_pcm(stream), gain_db)` のデコード後 RMS。`loop_offset` は OGG のインポート設定で、WAV は全長ループのため `—`。

| Set | ID | File | 秒 | loop_offset | 元の K (dB) | gain_db | 調整後の K (dB) |
|---|---|---|---:|---:|---:|---:|---:|
| standard | title | `assets/audio/music/hydrogene_traveling_the_sky.ogg` | 70.074 | 0.000000 | -7.306709 | -13.693291 | -21.000000 |
| standard | region0 | `assets/audio/music/hydrogene_spirits_forest_full.ogg` | 81.982 | 27.343741 | -2.929263 | -18.070737 | -21.000000 |
| standard | region1 | `assets/audio/music/hydrogene_dangerous_cave.ogg` | 79.288 | 0.000000 | -5.348764 | -15.651236 | -21.000000 |
| standard | region2 | `assets/audio/music/hydrogene_volcanic_crater.ogg` | 85.542 | 0.000000 | -8.548500 | -12.451500 | -21.000000 |
| standard | boss | `assets/audio/music/hydrogene_battle_theme_iv_full.ogg` | 85.219 | 1.741066 | -5.781872 | -15.218128 | -21.000000 |
| dark | title | `assets/audio/music/hydrogene_goofy_monster.ogg` | 32.002 | 0.000000 | -15.160794 | -5.839206 | -21.000000 |
| dark | region0 | `assets/audio/music/hydrogene_ancient_library.ogg` | 70.348 | 0.000000 | -15.477489 | -5.522511 | -21.000000 |
| dark | region1 | `assets/audio/music/hydrogene_the_old_magician.ogg` | 47.527 | 0.000000 | -13.698408 | -7.301592 | -21.000000 |
| dark | region2 | `assets/audio/music/hydrogene_malicious_scheme.ogg` | 71.210 | 0.000000 | -18.052725 | -2.947275 | -21.000000 |
| dark | boss | `assets/audio/music/hydrogene_the_evil_one.ogg` | 82.656 | 0.000000 | -14.970079 | -6.029921 | -21.000000 |
| junkala | title | `assets/audio/music/junkala_title_screen.wav` | 11.294 | — | -7.627672 | -13.372328 | -21.000000 |
| junkala | region0 | `assets/audio/music/junkala_level1.wav` | 74.254 | — | -6.437071 | -14.562929 | -21.000000 |
| junkala | region1 | `assets/audio/music/junkala_level2.wav` | 72.796 | — | -6.209629 | -14.790371 | -21.000000 |
| junkala | region2 | `assets/audio/music/junkala_level3.wav` | 81.896 | — | -6.434426 | -14.565574 | -21.000000 |
| junkala | boss | `sound_bank.gd` の合成 | 27.907 | — | -11.776044 | -9.223956 | -21.000000 |

`dark` の5曲は原本のバイトのままコピーし、`.import` は標準セットと同じ OGG 形式（`loop=true`、`loop_offset` を明示）にした。`junkala` の WAV は既存の4ファイルと `.import`（QOA、全長ループ）を変更していない。

### 暗めのセットの選曲

HydroGene の28曲と標準セットの5曲を Godot の `DSP.decoded_pcm` で WAV に書き出し、Python（numpy）で長さ、スペクトル重心（4096サンプル Hann 窓、hop 2048）、Krumhansl–Schmuckler の24調相関を測った。短調と推定する条件は、最良の短調相関が最良の長調相関より大きいこと。

規則は、候補を列挙順に見て「短調と推定され、かつスペクトル重心が標準セットの同じ ID 以下」の最初の曲を選ぶ。無ければ短調の候補の中で重心が最も低い曲、それも無ければ全候補で重心が最も低い曲。

| ID | 候補 | 重心 (Hz) | 推定調（短調相関 / 長調相関） | 判定 |
|---|---|---:|---|---|
| title | 12. Goofy Monster | 1,925.97 | D minor 0.4769 / C major 0.4179 | 採用（短調、標準 3,048.67 以下） |
| title | 21. Malicious Scheme | 785.71 | C major 0.8025 / G minor 0.6121 | 見送り（長調） |
| title | 18. The Old Magician | 961.49 | B minor 0.7281 / D major 0.5658 | 見送り（後順） |
| region0 | 06. Hidden Cavern | 1,183.32 | F major 0.8072 / A minor 0.7677 | 見送り（長調） |
| region0 | 22. Ancient Library | 1,490.25 | D minor 0.8848 / D major 0.6324 | 採用（短調、標準 1,892.13 以下） |
| region0 | 13. Magic Temple | 2,265.95 | D major 0.7819 / A minor 0.5467 | 見送り（長調） |
| region1 | 10. Dwarven Mine | 2,911.23 | F major 0.7754 / D minor 0.6312 | 見送り（長調） |
| region1 | 18. The Old Magician | 961.49 | B minor 0.7281 / D major 0.5658 | 採用（短調、標準 1,838.48 以下） |
| region1 | 23. Pyramid | 1,330.32 | G major 0.5621 / D minor 0.4800 | 見送り（長調） |
| region2 | 25. Dark Factory | 1,499.41 | G major 0.6921 / D minor 0.6267 | 見送り（長調） |
| region2 | 21. Malicious Scheme | 785.71 | C major 0.8025 / G minor 0.6121 | 採用（短調候補なし、全体で最低重心） |
| region2 | 20. Military Base | 1,992.24 | C major 0.7013 / A minor 0.6593 | 見送り（長調） |
| boss | 27. The Evil One | 1,815.45 | D minor 0.7386 / F major 0.6865 | 採用（短調、標準 2,120.31 以下） |
| boss | 26. Demon King Castle (full) | 2,015.93 | C major 0.7544 / C minor 0.5670 | 見送り（長調） |

全候補と標準5曲の数値は `builds/qa/sound/task9g/dark_selection.json` に記録した。`region2` は短調と推定された候補が無かったため、規則の第3段階で重心が最も低い 21. Malicious Scheme を選んだ。選んだ5曲に `(full)` は含まれず、`loop_offset` は全て0。

### 起動時の選び方

`play.cmd` と `play-angle.cmd` は起動時に次のメニューを出し、`choice /c 123 /n /t 10 /d 1` で10秒後に標準を選ぶ。

```
BGM set (default 1 in 10 s)
  1  Standard  - HydroGene, bright
  2  Dark      - HydroGene, dark
  3  Junkala   - Juhani Junkala (8-bit)
```

引数でメニューを飛ばせる。`play.cmd 2`、`play.cmd dark`、`play.cmd 3`、`play.cmd junkala` など、1/2/3 か名前を受け付ける。知らない引数はメニューを出す。選んだ名前を表示してから従来と同じ `start` で起動し、最後に `-- --music-set=<名前>` を付ける。`play-angle.cmd` の `--rendering-driver opengl3_angle` は維持している。直接起動する場合は `-- --music-set=dark` のように指定する。`--sound-set=synth` を併用すると、セット名に関係なく全曲を従来の8B合成で鳴らす。

### 検査と結果

- `music_sets_test`: 216 checks、失敗0。3セットの割当、ファイル存在と SHA-256、インポート設定、デコード後の K、director のセット選択、合成への切り替え、未知の名前の標準化を検査した。
- `audio_test`: 43,344 checks、1失敗。失敗は既知の負荷依存の時間検査 `asset main-thread service/operation each <8ms` のみ（`service_max=22.865ms`、`operation_max=22.433ms`）。効果音準備1,270.573ms、title準備1,270.574msは閾値内。標準セットの素材経路と閾値は変更していない。
- `audio_material_test`: 1,094 checks、失敗0。
- `audio_fresh_clone_test`: 作業ツリーでは `.godot/imported` があるため `loaded=65` となり失敗する（この検査は未インポートの複製を前提とする）。`.godot` を含めない複製では `streams=71 loaded=0 warned=65` で終了コード0。
- `title_demo_test`: 46 checks、失敗0。
- `run_tests`: 1,959 checks、失敗0。起動時の検査を含む。

試聴用に `builds/qa/sound/preview-9g/` へ dark と junkala の各5曲の先頭40秒（gain 適用済み、曲間1秒無音）をつないだ WAV と開始秒の txt を置いた。

### 未確認

- 人が聴いて「地下・お化け屋敷のように暗い」と感じるか、標準セットとの差が十分かは未確認。曲の雰囲気の評価は数値では決められない。
- ループの継ぎ目、特に `standard` の `loop_offset` と `junkala` の全長ループが実際のプレイで自然に聞こえるかは未確認。
- 展示用 PC のコードページでの `choice` メニュー表示、実際の `play.cmd` からの起動、全体の `test.cmd` は本タスクでは実行していない。
