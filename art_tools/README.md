# 第1〜第3段階の画像ビルド

numpy と Pillow の入った Python で実行する。スクリプトに Python の絶対パスは含めない。
検証環境は Pillow 12.3.0 / numpy 2.3.5。別バージョンの減色処理で同じバイト列になる保証はない。

```powershell
python -B art_tools/build_art.py
python -B art_tools/verify_art.py
```

`build_art.py` は `assets/art/source/` の保存済みAI原画6枚を入力にする。
追加の画像生成・ダウンロード・API呼び出しは行わない。
高解像度の部品と、その切出し座標・関節座標はビルドスクリプトに保存される。
部品は `source/parts/`、出力は `assets/art/{player,enemies,bosses,projectiles,effects,terrain,hud,items,ui,backdrops}/`。
シートの状態・コマ数・速度・基準点とSHA256は `assets/art/manifest.json`。

処理順は、明るい前景の種→2px膨張→外周から到達できない穴だけを埋める→部品マスク→
関節周りの回転と移動→BOX縮小→二値アルファ→共通63色＋透明1色。
走査行の両端を埋める処理は使わず、脚・腕・翼の間の空白を残す。
自機の胴体・頭・脚は両色で同じ部品。橙はそのアクセント色を変え、冠と核の形を別部品へ替える。
射撃は腕だけを差し替える。自機の胴体と腕は同じパレットを使う。
地上の待機・走り・着地などは、画像の足元を判定の下端へ揃える。

`verify_art.py` は再ビルドしてPNGのバイト一致を確認し、アルファ・色数・各コマの外周・
不透明な矩形背景・状態の網羅・アニメーションの変化・足元・地形の接続辺を検査する。
`probe_fresh_clone.py` はQAディレクトリに小さな検証プロジェクトを新規作成し、
`.godot/imported` がない状態で本番のPNG読込処理を通常レンダラーで実行する。
本体キャッシュと、別途Claudeが使うプロジェクトの写しには触れない。

第1段階の確認用画像は `builds/qa/art/stage1/`、第2段階の全コマ・GIF・地形・PNG検査結果は
`builds/qa/art/stage2/`。`build_stage2.py` を `build_art.py` から呼び、共通manifestを更新する。
第2段階の通常描画・負荷比較・欠損/破損/キャッシュなしPNGの検査は次で再取得する。

```powershell
$env:APPDATA = "$PWD\.userdata"
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . --script tests/impact_effect_test.gd -- --stage2-art-qa
```

このQAは通常描画、同じ生成地形、静止したカメラと物理、表示用時計で比較する。
VSyncとフレーム上限を解除し、各モードのウォームアップ後120フレームを測る。
測定値はCPU・GPUの待ちを含む実時間で、ゲーム全体の最悪負荷や単独GPU時間ではない。

通常起動は画像が既定。図形へ戻すには次の直接起動を使う。

```powershell
$env:APPDATA = "$PWD\.userdata"
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . -- --art-set=shapes
```

インポート済みPNGは `ResourceLoader.load_threaded_request` で読み、キャッシュがない場合は
WorkerThreadPoolでPNGバイトをデコードする。完了分の回収とGPU転送は1フレーム1.5msを予算にする。
一つの転送は途中で分割できないため、個別操作とサービス全体の最大時間を別途計測する。
将来exeへ書き出す場合は、全リソースを含める設定、または動的に参照する全出力PNGを選ぶ。
非リソースファイルを含める `include_filter` に **`assets/art/manifest.json`** を指定する。
PNGの生バイトを含めることはインポート済みリソース利用の必須条件ではない。
原画・部品は `source/.gdignore` でインポート・書き出し対象外。exe書き出しは今回未検証。

`verify_art.py` は全3段階を再生成して一致を検査する。壁タイルとレーザー帯は接続のため外周に
画素を持つが、他の全コマは透明な外周を要求する。ボスも全シート64色以内、アルファは0/255。
周期検査はGDScriptとPythonで同じハッシュを用い、16×16の領域と4セルずらした領域を比較する。

第3段階は `build_stage3.py` が続けて実行される。出力・GIF・全アイテムコマ表・検査結果は
`builds/qa/art/stage3/`。3地域の全タイル辺、背景の左右/上下接続、通常状態の弾・敵・ボスに
反対色の色相がないことも検査する（windup_switch/switchは除く）。
色相の条件はHSVで彩度0.28以上・明度0.16以上、青は0.46〜0.72、橙は0〜0.14または0.96〜1。
切替行と共有する減色パレットの誤選択を、同じパレット内の最も近い許可色へ戻す。
連結成分の調査は `components.json` に記録。新たな素材の取得は行わない。

通常描画・3地域・境界・全メニューの取得と図形/画像比較（指定検査の表示用分岐）:

```powershell
$env:APPDATA = "$PWD\.userdata"
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . --script tests/impact_effect_test.gd -- --stage3-art-qa
```

QA画面は実際の地形と描画を使い、敵・弾・アイテムの配置を固定して物理を止める。
地域ごとの新規ランと、同じランの実際の地域境界を撮影する。人が操作した評価を含まない。

仕上げの水路・背景8PNGだけを作り直す場合は `python -B art_tools/build_polish.py`。
同じ生成関数を2回呼び、バイト一致、64色、二値アルファ、水路の全変種の接続辺を確認して
既存manifestの対象ハッシュだけを更新する。原画の追加生成はない。
通常描画QAは `tests/run_tests.gd -- --polish-art-qa`（headlessを付けない）。
第3段階と同じ撮影に、背景だけの画像・深い内部の画像と測定マスクを追加し、
`builds/qa/art/polish/metrics.json` に明度、色差、4セルずらした画素の相関を記録する。
タイルの分布・負座標・原点移動はtile_test、HUD輪郭はui_map_testで検査する。
