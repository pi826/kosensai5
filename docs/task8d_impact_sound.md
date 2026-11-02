# Task 8D: 効果音の重ね合わせ、SFC風の曲、ボス撃破演出

2026-11-01実装、2026-11-02修正。比較の基準は`builds/qa/sound/task8d/baseline-6902671/`の写し。Gitコマンド、信頼設定、所有者、権限は扱わない。.claude/、CLAUDE.md、docs/claude_codex.mdは変更しない。

## ユーザーの指示（原文）

> 複数の音については弱いので、いくつかの音を重ねて出したりしましょう。bgmよりもっと効果音について、ドーンと言う感じがほしいです。中ボス以上を倒したら若干スロー演出を入れて音もそれに追従させ同心円状に空間を揺らす振動がでるようにしてください．回復音の回復感と自分がダメージを受けた音の喰らった感が弱いと思います。chiptuneなのはいいんですけど、今はfcくらいの感じなんですけどほしいのはsfcくらいの豪華なchiptuneです 8bitじゃなくて16bitが

## 変更

効果音60 IDを1〜6層から1本ずつのWAVへ焼き込む。UI 13 IDと敵のQUIET 9 IDは今回の指示に従い元素材1層、操作音は2層以上、Mは3層以上、Hは4層以上。実行時のvoiceは32、予約8、PRIORITY/LIMITS・音ID・発音条件と位置を維持。環境音6 IDは合成。`-- --sound-set=synth`では全71音が8B PCMへ戻り、基準と71/71のdataがバイト一致した。sound_bank.gdは変更していない。音量設定の既定80/60/80、audio.cfgのversion 1形式も維持する。

元素材は実際に層に使う68ファイルだけをassets/audio/source/へ元のバイトで配置した。.gdignoreでGodotインポート・書き出しから除外。比較用の旧WAVはQAのbaseline-audio/へ保存した。旧Junkala効果音55 WAVと曲4 WAV、および各.importを再生用ディレクトリから削除した。承認済みOGG 5本のバイトは変更していない。

`audio_tools/sfx_recipes.gd`にIDごとの層と8C測定基準を集約。`--headless --path . --script audio_tools/bake_sfx.gd`でPCM16/44.1kHz/mono・ループなしのWAVを再生成し、素材表とSHAも更新する。固定シード、固定順、線形補間による音程変更、遅延、HP/LP、ソフトクリップ、ID別の下降/上昇サブ、帯域ノイズ、サインスイープ、素材の下降する音程、短い途切れ、倍音ベル、ID別の音数・音程・間隔のアルペジオ、高域を丸め低域を落とした3回の反復を使う。出力の8ms末尾窓と全波形ゲインは焼き込み内の処理。.import側のtrim/normalizeはfalse。インポート後に原PCMとの一致を検査する。

sound_assets.gdは各IDにつき1行のpath/pitch/gain_db表。効果音pitchは1、gainは0を基準に聴感調整用として残す。曲・効果音ともAudioStreamとしてthreadedロードし、1フレーム1.5msのサービス予算内で登録・回収する。LOADED前の同期回収はしない。WAVのdataとOGGのpacket_dataの合計を重複なしで計測し、結果をキャッシュする。読めないIDだけ追加の合成で補い、警告はIDごとに1回。失敗したthreaded requestも回収する。

## 2026-11-02の修正

`spawn_bullet`の自機分岐に入っていた`boss_impact.cancel()`を削除した。自機と敵の通常弾・誘導弾、移動、通常/空中ジャンプ、色切替、ダッシュ、滑空、吸収、回復、回復薬、非致死被弾、射撃長押し＋誘導弾の実処理を追加検査し、activeとtime_scale/playback_speed_scale/physics ticksの完全一致を確認する。死亡、playing以外への遷移、再挑戦、チュートリアル、終了での解除は残した。

既存の1800フレーム完全一致検査は、比較の初期化を同じ60Hzの物理コールバック内へそろえた。72Hzとfixed-fps 60の境界で、手動のmove_and_slideが異なるキャッシュ済みdeltaを使う不安定さを除くため。比較する状態と1800フレーム完全一致の判定を維持する。通常操作の検査後は独立したワールドに戻す。

| ID群 | 修正した構成 |
|---|---|
| boss_defeat | 8Cのcluster9＋cannon＋126→36Hzの歪んだサブ、0.25/0.55秒遅延の爆発、長いノイズと反響。K目標-4.7dBでH内最大 |
| boss_appear | 8Cのportal＋32→95Hzの地鳴り、立ち上がるノイズ、1.65秒後に1回の低い打撃。爆発素材は使わない |
| bomb_explode | 8Cのshort_hard10＋bang_07＋170→60Hzの短いサブ＋ノイズ、0.62秒 |
| enhancer_defeat | 8Cのshort_hard1＋ガラス2種＋高いきらめき＋84→48Hzの短いサブ |
| death | 8Cのrobot2を1.15→0.28倍へ下降、1100→70Hzの下降スイープ、低い打撃、69→30Hzのサブ、0.35秒後から短い途切れ |
| hurt | 金属・bang・120→38Hzのサブ・ノイズ・plateと0.42秒を維持 |
| enemy_defeat / block_break / boss_hit / laser_fire | 共通ベルとアルペジオを除去。小爆発／採掘・石の破片／金属と装甲／高域ノイズで区別し、各々異なる短いサブを加える |
| chest_open / key / item_get / ability_get / arrow_unlock / charge | 共通サブを除去。keyは短い2音、ability_getは最長1.2秒・6音と2つのきらめき、chargeは連続上昇。他も別の基音・音数・音程・間隔 |
| UI 13 ID / QUIET 9 ID | ベルを除去し8C素材1本。UIは8C比+3dB以内、QUIETは+1dB以内 |
| land / jump / air_jump / dash / glide / homing | 低い下降音と打撃／上昇する帯域ノイズ／風切り／短い下降スイープ。ベルなし |
| shot_a / shot_b | 元素材の1.0/0.75倍を維持し、高いクリック＋胴体／低いクリック＋胴体 |
| switch_a/b / absorb_a/b | 元素材の色別pitchを維持し、短い高域ノイズを追加。ベル層0% |
| heal / potion / crystal / tutorial_step / win / lose | 前回の報酬音の方針を維持 |

Kenneyのガラス・採掘・金属・plate・soft・punchとbang/cannonの複数候補を、長さ、RMS、peak、高域差分で調べた。記録は`builds/qa/sound/task8d-fix/source-inspection.json`。これは試聴評価ではない。復元した8C素材5本と新たな9本は原本バイトでコピーし、SHAと出典を追記。未使用のimpactPunch.oggだけをsourceと出典表から除いた。

追加の波形検査は次の定義。既存のK/低域/ピーク/長さ等の閾値は維持。UI/QUIETだけ、新指示の「元の素材1本でよい」に従い最小層数を1とした。

- 相関は先頭400ms、短い音はゼロ埋め、DCを除いたゼロラグ正規化相関の絶対値。Hの指定5 ID全10組とenemy_defeat/block_break/boss_hit全3組を0.6以下で検査。
- 帯域割合は全PCMの矩形窓FFTを2冪までゼロ埋めし、指定周波数±3%の帯域の和集合の二乗エネルギーを全帯域で割る。DC/Nyquist以外の片側スペクトルを2倍し、重複を数えない。純660Hzと既知の4%混合で測定器も検証。
- 戦闘4 IDは660/825/990Hzの割合5%以下。land/ui_move/glide/dash/empty/enemy_warn/air_jumpは660/1320/2640Hzの割合15%以下。

## 演出と物理

kindがbossのguardian/final/secretにだけ適用する。報酬・鍵・スコア・撃破フラグは従来のactor_defeatedで直ちに確定し、演出はその外側の表示処理として動く。通常敵、強化の灯、チュートリアルは対象外。headlessは既定で何もせず、検査ではimpact_effect_override=1を指定する。

実時間0.05秒のsmoothstepでguardianは0.30、final/secretは0.22へ下げる。holdは0.55/0.85秒、復帰は0.60秒。Engine.time_scaleとAudioServer.playback_speed_scaleは同じ倍率曲線を、それぞれ開始前の値へ掛ける。Time.get_ticks_usecを使い、ゲームのdeltaに依存しない。voice.untilはメディア時間で管理し、実時間×実際のplayback_speed_scaleだけclockを進める。途中から遅くなった音も自然な実長までvoiceを保持する。

物理補間は現在のproject.godotでは無効。Godot 4.7.2を実測すると、time_scaleは物理deltaを小さくするが実時間のコールバック数は落とさない。ticksを60/scaleへ増やす案は約202.10回/秒となったため採用せず、元のticksを保持する方式で59.93回/秒を確認した。原点移動のreset_physics_interpolation等を維持する。物理と移動はdeltaを使い、フレーム番号を参照する既存箇所は音の同時フレーム制限のみ。終了時は開始前に読み取ったtime_scale/playback_speed_scale/ticksを正確に戻す。

worldとHUDの間のCanvasLayer 0にCompatibility対応hint_screen_textureを使うColorRectを置く。3本のリングを実時間で0.11秒ずつ遅らせ、幅30px、初期振幅22/30pxから減衰して広げる。開始時の中心から画面の最も遠い隅までの距離に90pxを足し、最後のリングが1.3秒でそこへ到達するよう一定速度を決める。わずかな色収差と明るい縁、0.12秒の白い閃光1回、0.3秒のcamera.offsetの揺れを加える。1.3秒でLayerを隠す。HUDとメニューはCanvasLayer 1以降なのでスクリーンテクスチャに含まれない。非演出時はprocessも止める。

中心は整数区画＋区画内位置で保存し、毎描画時に現在のorigin_sectorとcanvas_transformから画面座標へ変換する。画面外の中心もクランプしない。連続撃破では現在の速度から新たなholdへ延長し、新しい中心からリングを出す。クリア画面は演出全体（guardian 1.3秒、final/secret 1.5秒）の後へ遅らせる。stateのsetter、再挑戦、チュートリアル開始、自機死亡、_exit_treeで必ず解除する。クリア待機中に一時停止した場合も、再開後に結果へ進む。

## 音量と測定

K測定は8B/8Cと同じDeManのBS.1770シェルフ＋RLB、左右の二乗平均を合算する。曲は末尾0.5秒でフィルターを予熱して全長を測る。効果音はゼロ状態から、50msの無音尾を含め全標本を1標本ずつ動かす固定50ms窓の最大RMSを取る。LUFSのゲートや-0.691補正は使わない。

低域は2次Butterworthの30Hzハイパスと120Hzローパスを順に通し、最初の300msに完全に含まれる50ms窓を1標本刻みで測る。8Cも同じフィルター、旧pitch/gain適用後で測り直した。定数BASE_K/BASE_LOWとQAの元WAV・初回計測を保持する。

Hは再生要求を受理した瞬間にBGMの実出力を-7dB、enemy_defeat/block_break/boss_hitは-4dBへ下げる。300msで戻す。従来duckと結果-9dBと合わせて-14dBを下限とし、既存の実出力とエンベロープの上昇制限も残す。全体/BGM/SEが100%のミックスで16種のH/Mとboss曲を同時再生し、既存Master hard limiter通過後をAudioEffectCaptureで測定する。今回の実測は後掲の検査結果とmix-results.jsonに記録する。ceiling -0.5dBと既存の判定誤差は変更していない。

heal/potionはCure1/2と523.25→654.0625→784.875→1046.5Hzの4音、きらめき、長い反復を重ねた。potionにはglass/bottleを加える。Goertzelの時間窓で4音の上昇と4回の立ち上がりを測定した。hurtは0.42秒、アタック0.091ms、低音の測定周波数は95→40Hz。deathは1.6秒、hurtより大きく長く下降する。これらの指標から聴感の「満たされた」「痛い」を断定しない。

## 置き換えた既存検査

変更対象はaudio_testのassetsグループ。assetsのチェックをaudio_assets_checks.gdへ分けた。8B合成に対するenergy/startup/波形/発音/制限/状態遷移等の既存判定・閾値は変更していない。

- 素材58効果音/4曲、合成8効果音＋boss → 素材60効果音/5曲、合成は環境音6種。
- 効果音の「8B Kから±1dB」とPEAK_LIMITED差 → 指定のH/M絶対K下限、射撃8C比+4〜+7、UI比+3以内、敵警告比+1以内、H/M低域下限と8C比+6。全素材のpeak≤-1dBFSは維持。
- 素材メモリ≤16MiB → PCM data＋OGG packet_dataの実バイト数一致・計測記録。今回の条件で上限値は指定されていない。
- 曲のWAV/QOA/stereo/全長ループと8B K±0.5 → OGG/loop/明示loop_offsetとデコード後K=-21±0.5。bossの素材化も検査。
- 固定共有WAV59本の原本ハッシュ → 焼き込み60 WAV＋原本OGG 5本のSHA、使用source68本の原本SHAとCREDITS、層数・形式・長さ。
- 効果音だけの1 ID欠損 → 効果音とOGG bossの2 ID欠損、それぞれ1回の警告、他ID維持、基準合成PCMとgainなしへの復帰。

素材の準備1.3/3.0秒、メインスレッド8ms、音の上昇量等、それ以外の既存の時間条件と閾値は緩めていない。tests/impact_effect_test.gdをtest.cmdへ追加し全36実行とした。新しいassets検査だけはaudio_material_test.gdでも個別実行できる。impact_realtime_test（fixed-fpsなし）、audio_mix_test、audio_fresh_clone_test、impact_visualは追加の専用確認。

## 検査と成果物

全てAPPDATA=.userdata、Godotはtools/godot/Godot_v4.7.2-stable_win64_console.exe。通常描画だけCompatibility/NVIDIA RTX 3060、その他headless/Dummy。今回の指示により全36実行は行わない。audio_test、audio_material_test、audio_mix_test、impact_effect_test、impact_realtime_test、run_tests、movement_testだけを直接実行。impact_realtime_testはfixed-fpsなし、他は--fixed-fps 60。sector_test/playthrough/shaft/generation/diagonal、streaming_performance等は実行していない。全体の検査はClaudeがサンドボックス外で行う。

詳細ログ・計測・SHA・変更ファイル一覧は`builds/qa/sound/task8d/`。`file-changes.md`と`change-audit.json`に追加・変更・削除を列挙する。QAの補助・基準コピー・ログ、プレビューWAVは検証成果物として追加している。Godotによる新規GDScript/shaderの.uidと.godotキャッシュも自動生成される。許可範囲外のゲーム仕様ファイルは変更しない。

前回の通常描画PNG（impact-before.png、0.1/0.3/0.6/1.0/1.4秒）は既存成果物として残す。今回は通常描画を再実行せず、画像も再確認していない。今回の本体演出の修正は射撃時の解除1行の削除で、波紋・シェーダーは変更していない。

試聴は`builds/qa/sound/preview-8d/`。全66 IDを辞書順に並べたse_sampler.wavと開始秒つきse_sampler.txt、各IDの単体WAV、5曲のgain適用済み2周WAV（1周目だけイントロを含む）、hurt/heal/potion/bomb_explode/enemy_defeat/boss_defeatの8C→0.5秒無音→8Dの比較WAVと8C単体、boss_defeatのfinal/secret用スロー曲線再生WAVを置いた。

## 未確認

聴感はClaude・人とも未確認。SFCらしさ、打撃の重さ・回復感・痛さ、反復や長い余韻の密度、曲のループ継ぎ目、連続戦闘での聞き疲れ、実スピーカー・実機出力遅延は未確認。Dummyの波形と数値・画面確認で聴感を代替しない。OSディスクキャッシュを排除したコールド起動も未確認。

## 曲の割り当て表・実測

初回はイントロを含む全長、2周目からloop_offsetへ戻る。OGGの原本バイトには手を加えずgainだけで調整する。

| ID | assets/audio/music/のファイル | 秒 | loop_offset秒 | 元K dB | gain dB | 調整後K dB |
|---|---|---:|---:|---:|---:|---:|
| title | hydrogene_traveling_the_sky.ogg | 70.074310 | 0.000000 | -13.69329 | -7.30671 | -21.00000 |
| region0 | hydrogene_spirits_forest_full.ogg | 81.982132 | 27.343741 | -18.07074 | -2.92926 | -21.00000 |
| region1 | hydrogene_dangerous_cave.ogg | 79.287598 | 0.000000 | -15.65124 | -5.34876 | -21.00000 |
| region2 | hydrogene_volcanic_crater.ogg | 85.541946 | 0.000000 | -12.45150 | -8.54850 | -21.00000 |
| boss | hydrogene_battle_theme_iv_full.ogg | 85.218750 | 1.741066 | -15.21813 | -5.78187 | -21.00000 |

## 効果音の割り当て・層・実測

出力は全てassets/audio/sfx/ID.wav、pitch=1、gain_db=0。層のgain/pitch/フィルター/遅延等の全パラメーターはrecipes.jsonとsfx_recipes.gd。echoは低域を落とした3回の反復。表のK/低域/peakは焼き込み・gain適用後。

| ID | 秒 | 層（順序どおり） | K max50 dB | 8C比dB | peak dBFS | 低域dBFS | 低域8C比dB |
|---|---:|---|---:|---:|---:|---:|---:|
| ability_get | 1.200 | sfx_sounds_powerup1.wav + 合成:arp + 合成:bell + 合成:bell | -10.500 | 3.702 | -7.787 | -38.559 | 5.666 |
| absorb_a | 0.450 | sfx_coin_double4.wav + 合成:noise | -17.000 | -2.519 | -14.524 | -51.188 | -3.068 |
| absorb_b | 0.450 | sfx_coin_double4.wav + 合成:noise | -17.000 | -2.382 | -13.330 | -45.752 | -2.856 |
| aim | 0.450 | sfx_menu_move4.wav | -27.999 | 2.000 | -22.117 | -43.015 | 156.985 |
| air_jump | 0.270 | sfx_movement_jump10.wav + 合成:noise | -17.000 | 3.875 | -8.645 | -28.743 | 1.927 |
| arrow_unlock | 0.900 | sfx_sounds_powerup7.wav + 合成:arp + 合成:noise | -10.500 | 5.025 | -7.934 | -43.915 | 5.887 |
| block_break | 0.850 | sfx_exp_shortest_hard5.wav + impactMining_000.ogg + 合成:sub + 合成:noise | -10.500 | 7.845 | -6.587 | -11.309 | 15.938 |
| bomb_explode | 0.620 | sfx_exp_short_hard10.wav + bang_07.ogg + 合成:sub + 合成:noise | -6.800 | 5.126 | -5.487 | -8.665 | 6.566 |
| bomb_warn | 0.450 | sfx_wpn_grenadewhistle1.wav | -26.458 | -0.000 | -26.655 | -62.733 | -0.276 |
| boss_appear | 2.200 | sfx_movement_portal2.wav + 合成:sub + 合成:noise + impactSoft_heavy_000.ogg | -6.800 | 2.287 | -2.365 | -5.681 | 24.106 |
| boss_defeat | 2.600 | sfx_exp_cluster9.wav + cannon.ogg + 合成:sub + cannon_03.ogg + sfx_exp_cluster9.wav + 合成:noise | -4.700 | 4.852 | -2.516 | -6.526 | 10.761 |
| boss_hit | 0.480 | sfx_sounds_impact8.wav + impactMetal_heavy_003.ogg + impactPlate_heavy_003.ogg + 合成:sub | -10.500 | 7.841 | -5.905 | -13.972 | 18.246 |
| boss_shot | 0.450 | sfx_weapon_singleshot21.wav | -21.900 | 0.000 | -17.725 | -27.150 | -0.084 |
| buy | 0.450 | sfx_coin_double2.wav | -14.451 | 2.000 | -15.942 | -63.690 | 1.989 |
| charge | 0.700 | sfx_sounds_powerup8.wav + 合成:sweep + 合成:noise | -10.500 | 1.791 | -6.958 | -38.038 | 5.371 |
| chest_locked | 0.450 | sfx_sounds_error15.wav | -22.955 | 2.000 | -20.854 | -46.828 | 1.913 |
| chest_open | 0.850 | sfx_sounds_interaction10.wav + impactPunch_medium_003.ogg + 合成:arp | -10.500 | 3.162 | -5.902 | -29.009 | 10.540 |
| crystal | 0.450 | sfx_coin_single3.wav + 合成:bell | -17.000 | 4.154 | -12.645 | -48.826 | 8.339 |
| dash | 0.320 | sfx_wpn_sword1.wav + 合成:noise | -17.000 | 3.647 | -17.527 | -48.673 | 3.853 |
| death | 1.600 | sfx_deathscream_robot2.wav + 合成:sweep + impactPlate_heavy_003.ogg + 合成:sub | -5.100 | 6.360 | -2.827 | -4.114 | 8.187 |
| deny | 0.450 | sfx_sounds_error3.wav | -23.237 | 2.000 | -15.334 | -34.686 | 1.970 |
| empty | 0.450 | sfx_wpn_noammo3.wav | -26.750 | 2.000 | -17.575 | -37.407 | 1.036 |
| enemy_absorb | 0.450 | sfx_sounds_interaction9.wav | -24.617 | -0.000 | -21.662 | -41.052 | -0.701 |
| enemy_defeat | 0.640 | sfx_exp_shortest_hard2.wav + bang.ogg + 合成:sub + 合成:noise | -10.500 | 4.969 | -8.526 | -18.507 | 18.063 |
| enemy_hit | 0.450 | sfx_damage_hit1.wav + 合成:noise | -17.000 | 6.157 | -13.245 | -31.769 | 6.352 |
| enemy_homing | 0.450 | sfx_wpn_missilelaunch.wav | -26.565 | -0.000 | -24.019 | -45.021 | -0.388 |
| enemy_shot | 0.450 | sfx_weapon_singleshot14.wav | -34.579 | -0.000 | -32.579 | -68.331 | 131.669 |
| enemy_switch | 0.450 | sfx_sounds_Blip6.wav | -28.107 | 0.000 | -24.531 | -50.514 | -0.208 |
| enemy_warn | 0.450 | sfx_sounds_Blip11.wav | -33.520 | 0.000 | -28.754 | -49.935 | -0.032 |
| enemy_warn_special | 0.450 | sfx_lowhealth_alarmloop6.wav | -24.652 | -0.000 | -18.136 | -36.557 | -1.044 |
| enhancer_defeat | 0.950 | sfx_exp_short_hard1.wav + impactGlass_heavy_003.ogg + impactGlass_light_000.ogg + 合成:bell + 合成:sub | -6.800 | 2.338 | -3.512 | -6.852 | 10.881 |
| equip | 0.450 | sfx_menu_select2.wav | -18.529 | 2.000 | -18.688 | -48.954 | 2.061 |
| glide | 0.400 | sfx_wpn_sword3.wav + 合成:noise | -17.000 | 8.013 | -10.317 | -27.954 | 6.883 |
| heal | 1.350 | Cure1.wav + 合成:arp + 合成:bell | -13.000 | 2.022 | -8.573 | -38.648 | 6.693 |
| homing | 0.320 | sfx_wpn_laser6.wav + 合成:sweep | -17.000 | 2.170 | -13.461 | -33.290 | 0.996 |
| hurt | 0.420 | impactMetal.ogg + bang.ogg + 合成:sub + 合成:noise + impactPlate.ogg | -6.800 | 7.301 | -5.088 | -8.152 | 14.814 |
| item_get | 0.750 | sfx_sounds_powerup12.wav + 合成:arp + 合成:bell | -10.500 | 4.698 | -6.513 | -33.418 | 4.240 |
| jump | 0.240 | sfx_movement_jump1.wav + 合成:noise | -17.000 | 5.526 | -15.176 | -36.954 | 5.378 |
| key | 0.420 | sfx_sounds_powerup10.wav + 合成:arp + 合成:noise | -10.500 | 3.054 | -5.858 | -34.271 | 1.375 |
| land | 0.220 | sfx_movement_jump12_landing.wav + impactPunch_medium_003.ogg + 合成:sweep | -17.000 | 6.420 | -11.923 | -22.071 | 40.790 |
| laser_charge | 0.450 | sfx_sound_poweron.wav | -22.807 | -0.000 | -18.017 | -43.556 | 8.732 |
| laser_fire | 0.800 | sfx_wpn_laser12.wav + cannon_03.ogg + 合成:noise + 合成:sub | -10.500 | 9.207 | -6.390 | -20.704 | 10.395 |
| loop_up | 0.450 | sfx_alarm_loop8.wav + 合成:noise | -17.000 | 1.066 | -16.036 | -39.613 | 0.823 |
| lose | 2.500 | 合成:lose + 合成:bell + 合成:arp | -17.000 | - | -11.963 | -47.627 | - |
| map_close | 0.450 | sfx_sounds_pause6_out.wav | -22.995 | 2.000 | -15.028 | -36.993 | 0.702 |
| map_open | 0.450 | sfx_sounds_pause6_in.wav | -20.909 | 2.000 | -15.846 | -37.112 | 0.570 |
| pause | 0.450 | sfx_sounds_pause2_in.wav | -21.537 | 2.000 | -16.108 | -37.721 | 0.531 |
| potion | 1.500 | Cure2.wav + 合成:arp + 合成:bell + bottle.ogg | -13.000 | 7.836 | -8.269 | -38.529 | 13.799 |
| shop_open | 0.450 | sfx_sounds_pause7_in.wav | -19.049 | 2.000 | -16.605 | -39.431 | 1.176 |
| shot_a | 0.180 | sfx_wpn_laser2.wav + 合成:noise + 合成:sweep | -19.223 | 5.500 | -20.066 | -53.546 | 4.563 |
| shot_b | 0.220 | sfx_wpn_laser2.wav + 合成:noise + 合成:sweep | -18.161 | 5.500 | -17.904 | -46.800 | 9.484 |
| switch_a | 0.450 | sfx_sounds_interaction14.wav + 合成:noise | -17.000 | 0.571 | -12.596 | -38.205 | -0.217 |
| switch_b | 0.450 | sfx_sounds_interaction14.wav + 合成:noise | -17.000 | 0.321 | -12.200 | -33.681 | 0.053 |
| tutorial_step | 0.450 | sfx_sounds_fanfare3.wav + 合成:bell | -17.000 | -1.883 | -12.055 | -37.312 | -6.096 |
| ui_back | 0.450 | sfx_sounds_Blip9.wav | -23.960 | 2.000 | -20.995 | -46.650 | 1.779 |
| ui_confirm | 0.450 | sfx_menu_select5.wav | -19.733 | 2.000 | -20.195 | -47.646 | 0.777 |
| ui_move | 0.450 | sfx_menu_move2.wav | -28.178 | 2.000 | -21.188 | -56.682 | 1.529 |
| wall_place | 0.450 | sfx_sounds_impact12.wav + 合成:noise | -17.000 | 8.279 | -14.175 | -23.849 | 8.105 |
| wall_vanish | 0.450 | sfx_sounds_high5.wav + 合成:noise | -17.000 | 12.848 | -16.917 | -38.146 | 13.331 |
| win | 3.500 | 合成:win + 合成:bell + 合成:arp | -17.000 | - | -11.603 | -44.885 | - |

## 修正後の相関・帯域割合

| 組 | 先頭400msの相関絶対値 |
|---|---:|
| block_break / boss_hit | 0.264 |
| bomb_explode / death | 0.098 |
| bomb_explode / enhancer_defeat | 0.108 |
| boss_appear / bomb_explode | 0.045 |
| boss_appear / death | 0.203 |
| boss_appear / enhancer_defeat | 0.004 |
| boss_defeat / bomb_explode | 0.021 |
| boss_defeat / boss_appear | 0.021 |
| boss_defeat / death | 0.058 |
| boss_defeat / enhancer_defeat | 0.017 |
| enemy_defeat / block_break | 0.089 |
| enemy_defeat / boss_hit | 0.071 |
| enhancer_defeat / death | 0.189 |

| ID | 指定帯域のエネルギー割合 % |
|---|---:|
| air_jump | 9.479 |
| block_break | 0.576 |
| boss_hit | 2.722 |
| dash | 1.534 |
| empty | 2.500 |
| enemy_defeat | 3.029 |
| enemy_warn | 0.117 |
| glide | 2.351 |
| land | 0.380 |
| laser_fire | 4.324 |
| ui_move | 0.435 |

## 2026-11-02の実行結果

| 実行 | 終了コード | 秒 |
|---|---:|---:|
| preview | 0 | 31.316 |
| import-final | 0 | 5.575 |
| audio_test | 0 | 77.275 |
| audio_material_test | 0 | 24.243 |
| audio_mix_test | 0 | 1.747 |
| impact_effect_test | 0 | 4.987 |
| impact_realtime_test | 0 | 5.545 |
| run_tests | 0 | 17.202 |
| movement_test | 0 | 12.967 |

| 検査 | 項目数 | 失敗数 |
|---|---:|---:|
| audio_test | 43344 | 0 |
| audio_material_test | 1094 | 0 |
| impact_effect_test | 3412 | 0 |
| run_tests | 940 | 0 |
| movement_test | 77 | 0 |

Master/BGM/SE=100でH/M 16音＋boss曲を同時に発音。limiter後の24576 stereo framesでpeak -0.500 dBFS、ok=True。

| 演出 | 実時間秒 | 実物理Hz | 復元ticks | 速度差最大 |
|---|---:|---:|---:|---:|
| guardian | 1.310 | 57.508 | 60 | 1.19209E-08 |
| final | 1.510 | 59.899 | 60 | 1.19209E-09 |
| secret | 1.511 | 60.068 | 60 | 1.19209E-09 |

詳細は builds/qa/sound/task8d-fix/ の各ログ、selected-results.json、progress.md。計測JSONとrecipes.jsonは従来のtask8d/にも更新した。bake-byte-equality.jsonは最終設定の再実行で60/60一致、synth-byte-equality.jsonは基準71/71一致。preserved-files.jsonはsound_bank.gd、audio_director.gd、OGG 5本、ユーザーaudio.cfg、変更禁止ファイルのSHA一致を記録する。

途中の失敗も記録に残す。初回はbomb_explodeの低域8C比が+4.33dBで不足し、短いサブを増やして修正。測定ログの%書式エラーも修正。指定7本の初回では追加した測定器校正のみ失敗し、校正信号を0.2秒から1秒に延長して再検査した。音素材と受入閾値は変更していない。selected-results-first.jsonと各first.logを参照。

Godot起動時にWindowsルート証明書ストアの読込エラーが出る。検査はローカルのみで、ネットワークによる素材取得や認証は行っていない。全36実行、通常描画の再確認、実プレイでの手動確認、聴感（Claude・人とも）は今回未確認。

## 直接実行での確認（2026-11-02）

Codexのサンドボックス外で、Claudeが修正後の写しに対して実行した。全てAPPDATAをプロジェクト内に設定、--audio-driver Dummy。

- test.cmdの全36実行：36/36が終了コード0、SCRIPT ERRORなし。
- audio_test 43,344項目、impact_effect_test 3,412項目、失敗0。
- audio_material_test 1,094項目、失敗0。audio_mix_test 成功（16音、最大-0.4998dBFS）。impact_realtime_test 成功。
- 通常のウィンドウ起動（メインシーン、Dummyオーディオ）：全71音の準備0.93秒、素材65、合成へ戻したID 0。
