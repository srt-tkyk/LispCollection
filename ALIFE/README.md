# LispCollection
Games to spark my imagination

<video src="my-sim.mp4" autoplay loop muted playsinline></video>

## 必要なもの

- [SBCL](http://www.sbcl.org/) (Steel Bank Common Lisp)
- [ffmpeg](https://ffmpeg.org/) (動画出力時)

## ALIFE — 進化シミュレーション

2D世界で生物が食料を探し、食べ、繁殖する進化シミュレーション。
生物はゲノム（速度・旋回率・代謝・感知範囲・色相）を持ち、繁殖時に変異が起きることで自然選択が働く。

### テキスト実行

```bash
cd ALIFE
sbcl --load evolve.lisp --eval '(run-simulation)' --quit
```

オプション:

```lisp
(run-simulation :ticks 200 :print-every 10)
```

### 動画出力

シミュレーションの様子をMP4動画として出力する。

```bash
cd ALIFE
sbcl --load evolve.lisp --load render-video.lisp --eval '(render-run)' --quit
```

オプション:

```lisp
(render-run :ticks 300 :output "my-sim.mp4")
```

- `ticks` — シミュレーションのステップ数（デフォルト: 300）
- `output` — 出力ファイル名（デフォルト: `evolve.mp4`）

動画には生物（色付き円）、感知範囲（薄いリング）、食料（緑の点）が描画される。
