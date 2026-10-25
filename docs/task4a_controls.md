# Task 4A：操作・射撃・すり抜け・複数ロックオン

2026-10-25。地形生成、敵の種類・数・配置は変更していない。一続きのワールド、移動・ジャンプの物理値、戦闘数値と敵の行動は維持した。仕様からの意図した逸脱はない。

## 実装

- 左手はA/D・Space/W・S/↓、右手はJ射撃・K色切替・L角度切替・;誘導弾。全10操作を既存の設定画面に列挙し、スクロール・変更・保存できる。案内・開始説明・ゲージ表示もキー設定に追従する。
- 保存形式はversion 3。旧版とversionなしのファイルは読み込まず既定値を適用し、明示的に保存するまで元ファイルを保持する。version 3の行ごとの回復・重複拒否・保存失敗の説明を維持した。
- 自機の仰角は0°→60°→-60°→0°。方向は `Vector2(facing * cos(angle), -sin(angle))`。体の矩形と発射方向の交点から9px先に通常弾を生成し、銃身とHUDに角度を表示する。向き変更で角度を保ち、開始・再挑戦で0°に戻す。
- 薄い足場は物理レイヤー5（ビット16）。厚い地形・ブロックはレイヤー1、設置壁は4（ビット8）のまま。本体のmaskは1|8|16、自機弾は1|4|8|16、敵弾・砲弾は1|2|16、レーザーは1|16。両方の地形実装に適用した。
- 下キーを押して接地中の衝突を調べ、支持が薄い足場だけなら自機のmaskから16だけを外す。自機の上端が足場の底面+4pxより下に抜けたら復帰し、最長0.4秒でも復帰する。コヨーテ時間と既存のジャンプ予約を消し、すり抜け中はコヨーテ時間を補充しない。下キー保持中は次の薄い足場でも繰り返す。敵のmaskは変更しない。
- 自機誘導弾は画面内の生存敵を距離順に選び、異色がいれば異色だけに絞る。初回は候補を巡回して1発ずつ割り当てる。対象が倒れた場合は、飛行中の自機誘導弾の本数が最少の敵へ再照準し、同数なら弾から近い候補を優先する。再照準した弾は直ちに後続の本数集計に含まれる。
- ゲージによる発射予定と飛行中の追尾先の和集合に、暗い縁の白い照準印を表示する。敵の誘導弾は従来どおりプレイヤーのみを狙う。

## 追加定数（scripts/tuning.gd）

| 定数 | 値 |
|---|---|
| AIM_ANGLES | [0.0, 60.0, -60.0]度 |
| MUZZLE_CLEARANCE | 9px |
| PLATFORM_LAYER | 16（物理レイヤー5） |
| DROP_THROUGH_MAX_TIME | 0.4秒 |
| DROP_THROUGH_CLEARANCE | 4px |
| LOCK_MARK_SIZE | 10px |

## 実行した検査

APPDATAをプロジェクト内の `.userdata` に設定し、全10本を変更前・変更後にそれぞれ直接実行した。`test.cmd` は使用していない。

```powershell
$env:APPDATA = "$PWD\.userdata"
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 --script tests/<name>.gd
```

| テスト | 変更前の項目数 | 変更後の項目数 | 失敗（前／後） |
|---|---:|---:|---:|
| generation_test | 26,492 | 26,492 | 0 / 0 |
| run_tests | 301 | 402 | 0 / 0 |
| movement_test | 30 | 58 | 0 / 0 |
| key_bindings_test | 188 | 205 | 0 / 0 |
| tile_test | 47 | 47 | 0 / 0 |
| seamless_test | 52 | 52 | 0 / 0 |
| camera_test | 18 | 18 | 0 / 0 |
| playthrough | 328 | 328 | 0 / 0 |
| enemy_types_test | 56 | 56 | 0 / 0 |
| terrain_change_test | 114 | 114 | 0 / 0 |
| 合計 | 27,626 | 27,772 | 0 / 0 |

- キー設定：全既定値、2操作の追加とUI変更・保存、;表示、version 3保存・再読込、旧版ファイルの非更新、壊れた行、重複拒否を確認した。旧版引継ぎの検査は今回の旧版無視の検査に置き換えた。
- 射撃：循環、左右各角度の実弾方向・発射口・数値、移動での角度保持、停止中の入力禁止、再挑戦の初期化、HUDを確認した。
- すり抜け：両地形実装でタップによる真下の足場への着地、保持による複数段通過、厚い床・ブロック・壁での非発動、直後のコヨーテ禁止、下からの通過、敵の接地維持を実物理で確認した。両地形の薄い足場による自機弾・敵弾・レーザー・砲弾の遮断も確認した。
- 誘導弾：異色3体への5発の割り当て（2・2・1）、同色の除外と同色のみのときの候補化、死亡後の最少本数への再照準と同数時の優先順、照準印の数・保持・消去、敵誘導弾の対象と数値を確認した。
- 既存検査：1,000シードの生成、地域境界での状態保持、カメラ、全中ボスへの往復、地形破壊・設置を失敗0で維持した。
- `visual_check.gd` はheadlessなし、OpenGL / RTX 3060で終了コード0。27画像を保存した。`angle_0.png`、`angle_60.png`、`angle_-60.png`、`lock_on_preview.png`、`lock_on_flight.png`、`key_settings_aim.png`、`key_settings.png`、`controls_help.png`を目視確認し、銃身・弾・HUD・照準印・設定画面・案内の表示を確認した。

ログ・終了コード・画像は `builds/qa/controls/`。変更前にも出ていたWindowsのルート証明書ストア読み取りエラーは残るが、最終の全検査にGDScriptエラー・テスト失敗はない。

人の実プレイによる両手操作のしやすさ、角度切替の使いやすさ、戦闘の難易度・所要時間は未確認。洞窟地形は次のTask 4Bで扱う。

## 変更ファイル

- 実装：`project.godot`、`scripts/key_bindings.gd`、`player.gd`、`combatant.gd`、`main.gd`、`interface.gd`、`terrain.gd`、`world_terrain.gd`、`projectile.gd`、`laser_beam.gd`、`bomb.gd`、`tuning.gd`。
- 検証：`tests/key_bindings_test.gd`、`movement_test.gd`、`run_tests.gd`、`enemy_types_test.gd`、`terrain_change_test.gd`、`visual_check.gd`。`enemy_types_test.gd`と`terrain_change_test.gd`の既存物理検査には薄い足場の新レイヤーを反映した。
- 文書：`README.md`、`docs/roadmap_v2.md`、`docs/seamless_world.md`、本書（新規）。

`CLAUDE.md`、`.claude/`、`docs/claude_codex.md`は編集していない。Gitのコミット・プッシュ・公開・デプロイは行っていない。
