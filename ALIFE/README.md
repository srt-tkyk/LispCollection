# ALIFE — S式ゲノム進化シミュレーション

<video src="demo.mp4" autoplay loop muted playsinline></video>

<sub>CLOS版 600 tick（`./run.sh video` と同じ設定）。白く縁取られた赤い個体が、
進化の途中で `change-class` により草食から転じた捕食者。終盤で 25 匹まで増える。</sub>

行動を `behave` にハードコードせず、**行動そのものをS式の木としてゲノムに入れた**
人工生命シミュレーション。突然変異は部分木の書き換え、交叉は部分木の交換、
表現型化は `COMPILE` によるネイティブコード化で行う。

進化した個体の「脳」はそのまま Lisp のソースコードとして読める。

```lisp
[age 1200  energy 36.9  sense-r 50.3]
  turn : FOOD-ANGLE
  speed: FOOD-DIST
```

これは旧版 `evolve.lisp`（git 履歴に残る、行動が固定だった版）の `steer-toward`
に相当する行動が、**一行も書かずに発見された**もの。

---

## 1. 必要なもの

| | 用途 | 必須 |
|---|---|---|
| SBCL 2.0 以降 | 実行 | 必須 |
| ffmpeg | 動画出力 | 動画を作る場合のみ |

外部ライブラリ（Quicklisp / ASDF）への依存はない。素の SBCL で動く。

### インストール

**macOS**
```bash
brew install sbcl ffmpeg
```

**Ubuntu / Debian**
```bash
sudo apt install sbcl ffmpeg
```

**Arch**
```bash
sudo pacman -S sbcl ffmpeg
```

**Windows** — WSL2 上で上記 Ubuntu の手順を推奨。
ネイティブで動かす場合は http://www.sbcl.org/platform-table.html から
バイナリを取得し、ffmpeg は https://ffmpeg.org/download.html から。

確認:
```bash
sbcl --version     # SBCL 2.x.x
ffmpeg -version
```

---

## 2. ファイル構成

```
ALIFE/
├── brain.lisp        S式ゲノム — 木の生成・変異・交叉・コンパイル
├── spatial.lisp      トーラス空間ハッシュ + トーラス距離
├── alife-clos.lisp   ★CLOS版 — 捕食者が進化する（推奨）
├── evolve-gp.lisp    S式ゲノム版 — 草食のみ、構造が単純
├── render.lisp       PPM出力 + ffmpeg で MP4 化
├── run.sh            実行スクリプト
├── Makefile
└── demo.mp4          冒頭のデモ動画（`make clean` では消えない）
```

依存関係:

```
brain.lisp ──┬─ evolve-gp.lisp ──┐
             │                   ├─ render.lisp
spatial.lisp─┴─ alife-clos.lisp ─┘
```

`alife-clos.lisp` は空間ハッシュと距離の両方を、`evolve-gp.lisp` は距離だけを
`spatial.lisp` から使う（近傍探索は全走査のまま）。どちらも先に
`brain.lisp` と `spatial.lisp` をロードすること。

> **注意**: `evolve-gp.lisp` と `alife-clos.lisp` は同名の関数
> （`create-world` `behave` `world-step` など）を定義するので、
> **同じセッションに両方ロードしてはいけない。** どちらか一方を使う。

---

## 3. 実行

### いちばん簡単な方法

```bash
chmod +x run.sh
./run.sh clos          # CLOS版（捕食者が進化する）
```

`make` を使うなら:

```bash
make          # = ./run.sh clos
make gp       # GP版
make video    # MP4 出力
make repl     # ロードして REPL に入る
make clean    # 出力を削除
```

### 直接 sbcl を叩く

```bash
# CLOS版
sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp \
     --eval '(run-simulation)' --quit

# GP版
sbcl --load brain.lisp --load spatial.lisp --load evolve-gp.lisp \
     --eval '(run-simulation)' --quit
```

パラメータを変える:

```bash
sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp \
     --eval '(run-simulation :ticks 5000 :n-org 300 :n-food 400 :print-every 200)' --quit
```

### 動画出力

```bash
./run.sh video                      # alife.mp4 が生成される
```

```bash
sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp --load render.lisp \
     --eval '(render-run :ticks 600 :n-org 200 :n-food 250 :output "my-run.mp4")' --quit
```

> `render-run` の既定値（個体 120 / 400 tick）だと**捕食者が一匹も出現しないまま終わる**。
> 捕食を映したいなら個体 200 / 餌 250 で 600 tick 以上回すこと。`./run.sh video`
> はこの設定にしてある。

描画の凡例:

| 見た目 | 意味 |
|---|---|
| 緑の小さい点 | 食料 |
| 色つきの円 | 個体。色相は遺伝、明るさはエネルギー |
| 薄いリング | その個体の感知範囲 `sense-r` |
| **白い縁取り** | **捕食者**（`change-class` で赤くなる） |
| 白い線 | 進行方向 |

**所要時間の目安**: CLOS版デフォルト（2000 tick, 個体200）で約 23 秒。
`./run.sh video` は 600 フレームで 1〜2 分（PPM 書き出しが大半）。

> **GP版について**: `./run.sh gp` は個体数 100 から始まり、
> 10 前後で平衡に落ち着く（絶滅はしない）。餌の再生量に対して
> 繁殖閾値が高いため。構造進化の観測（7.1 / 7.2）はこの状態で起きる。
> 個体数を保ちたければ `:n-food` を増やすか `try-reproduce` の閾値 75 を下げる。

### REPL で触る

ここが Lisp を使う実利。**走らせたまま世界に介入できる。**

```bash
./run.sh repl
```

```lisp
;; 世界を作って手で進める
(defparameter *w* (create-world 200 250))
(dotimes (i 500) (world-step *w*))
(print-stats *w*)
(show-brains *w* 5)

;; 生きている個体の脳を1つ取り出して、単体で評価してみる
(let ((g (organism-genome (first (world-organisms *w*)))))
  (run-brain (genome-turn-tree g) 0.5 0.3 0.8 0.1))
;;                                fa  fd  en  ag

;; 走らせたまま代謝コストの定義を変える → 次の tick から効く
(defmethod metabolic-cost ((org predator) v) (* 1.2 (call-next-method)))
(dotimes (i 200) (world-step *w*))
(print-stats *w*)

;; 特定の個体を手で捕食者に変える（同一性は保たれる）
(let ((o (first (world-organisms *w*))))
  (change-class o 'predator)
  (values o (class-of o)))
```

---

## 4. 仕組み

### 4.1 ゲノムの構造

```lisp
(defstruct genome
  speed turn-rate metabol sense-r hue    ; 形態 — 連続値
  aggression                             ; 攻撃性 — 種分化のトリガ
  turn-tree                              ; 脳1 — 旋回量を決める木
  speed-tree)                            ; 脳2 — 速度を決める木
```

形態は数値、行動は木。**木のほうには次元という概念がない。**

### 4.2 プリミティブ集合

終端（葉）:

| 記号 | 意味 | 範囲 |
|---|---|---|
| `food-angle` | 最寄りの獲物への相対角 | -π..π（見えなければ 0） |
| `food-dist` | 正規化距離 | 0..1（見えなければ 1） |
| `energy` | 正規化エネルギー | 0..1 |
| `age` | 正規化年齢 | 0..1 |
| `noise` | 乱数 | -1..1 |
| 定数 | エフェメラル定数 | -2..2 |

関数（節）: `+ - * %` `if>` `sin` `abs`

- `%` は保護付き除算（0除算で 1.0 を返す）
- `(if> a b c d)` は `a > b` なら `c`、さもなくば `d`。**`c` と `d` は遅延評価**

**閉包性**: すべてが `single-float` を返す。よって任意の部分木を任意の位置に
差し込んでも妥当な木になり、交叉・変異に型チェックが要らない。

### 4.3 変異と交叉

```lisp
(mutate-tree tree)      ; 部分木を1箇所ランダムに書き換える
(crossover a b)         ; A の部分木を B の部分木で置き換える
```

交叉の具体例:

```lisp
;; 親A
(if> (food-dist) 0.5 (steer) (wander))
;; 親B
(if> (energy) 0.2 (rest) (wander))
;; 条件部を交換した子 — どちらの親も持たない行動
(if> (energy) 0.2 (steer) (wander))
```

`speed` を混ぜても到達できない場所に、部分木の交換で一発で届く。

### 4.4 表現型化

```lisp
(emit tree)          ; 木 → Lisp ソース。大半は恒等写像
(compile-brain tree) ; ソース → ネイティブコード
```

`emit` の中身を見ると、`%` と `if>` の2つ以外はこれだけ:

```lisp
(t (cons (car tree) (mapcar #'emit a)))
```

**遺伝子とソースコードが同じ表現なので、変換器がほぼ要らない。** これが要点。

コンパイル結果は木を `equal` キーにしたハッシュでキャッシュしている。
無変異で継承された脳は再コンパイルされない。

`*use-compiler*` を `nil` にすると木の直接解釈に切り替わる（デバッグ用）。

### 4.5 CLOS — 同じ脳が体によって別の意味を持つ

`target-of` が `edible-p` の多重ディスパッチで対象を選ぶ。

```lisp
(defmethod edible-p ((e herbivore) (thing food))      t)
(defmethod edible-p ((e predator)  (thing herbivore)) t)
(defmethod edible-p ((e predator)  (thing predator))  nil)
```

草食獣の `FOOD-ANGLE` は植物への方向、捕食者の `FOOD-ANGLE` は獲物への方向。
`change-class` で種が変わると、**脳のS式を一文字も書き換えずに行動の意味が変わる。**

### 4.6 change-class による種分化

`aggression` が `*predator-threshold*` を超えると捕食者になる。
オブジェクトを作り直さないので `EQ` 同一性が保たれ、世界のリストや
進行中の参照が壊れない。遷移処理は CLOS 標準プロトコルに乗せてある。

```lisp
(defmethod update-instance-for-different-class :after
    ((old herbivore) (new predator) &key)
  (setf (genome-hue (organism-genome new)) 0.0))   ; 赤くなる
```

閾値を下回れば草食に戻る（可逆）。

---

## 5. 主なパラメータ

`brain.lisp`:

| 変数 | 既定 | 意味 |
|---|---|---|
| `*max-depth*` | 4 | 初期木の最大深さ |
| `*max-size*` | 40 | 木の最大ノード数（bloat 抑制） |
| `*use-compiler*` | `t` | `nil` で解釈実行 |

`alife-clos.lisp`:

| 変数 | 既定 | 意味 |
|---|---|---|
| `*predator-threshold*` | 0.55 | 捕食者になる攻撃性の閾値 |
| `*capture-rate*` | 0.35 | 捕食の成功率 |

`run-simulation` の引数: `:ticks 2000 :n-org 200 :n-food 250 :print-every 100`

`world-step` の引数: `:food-cap 250 :pop-cap 600`

### 乱数

SBCL は起動時の `*random-state*` が毎回同じなので、**既定では実行が再現する。**
毎回変えたいとき:

```lisp
(setf *random-state* (make-random-state t))
```

シードを固定したいとき:

```lisp
(setf *random-state* (sb-ext:seed-random-state 42))
```

---

## 6. 観測用の関数

```lisp
(print-stats w)        ; 個体数・平均エネルギー・脳サイズ・攻撃性
(show-brains w 5)      ; 長寿個体の脳をソースとして印字
(count-class w 'predator)
*speciation-log*       ; 種転換イベントの履歴
```

`evolve-gp.lisp` には構造獲得率の測定もある:

```lisp
(structure-stats w)
;; => (:N 13 :TURN-USES-FOOD-ANGLE 1.0 :SPEED-USES-ENERGY 0.23076923
;;     :HAS-CONDITIONAL 0.84615386 :AVG-BRAIN 28.2)
```

`TURN-USES-FOOD-ANGLE` などは**固定次元GAでは原理的に動かない量**。
進化が構造を獲得したかどうかを直接測っている。

---

## 7. 実験結果

### 7.1 感覚運動結合の獲得（GP版, 1200 tick）

`(create-world 100 180)` を既定の `*random-state*` で 1200 tick 回したときの
`structure-stats`:

```
 tick    個体数   turn が food-angle を参照   if> 保有   平均脳サイズ
    0      100              43%                 68%         26.0
  200       38              34%                 47%         15.2
  400        8              62%                 62%         18.0
  600        7              86%                 86%         25.9
  800       10             100%                 80%         24.4
 1000       11             100%                 82%         24.6
 1200       13             100%                 85%         28.2
```

**`food-angle` の参照率は 43% → 100% に固定される。** 餌の方向を見ない個体は
1200 tick までに一匹残らず淘汰された。これが `steer-toward` を書かずに
獲得された感覚運動結合であり、固定次元GAでは原理的に動かない量。

t=1200 の生存個体3体のうち1体は最小形まで削れている:

```lisp
[age 1200  energy 36.9  sense-r 50.3]
  turn : FOOD-ANGLE
  speed: FOOD-DIST
```

ただし**平均脳サイズは 26.0 → 28.2 で、縮んでいない。** 最小形の個体と、
20〜30ノードの冗長な木を抱えた個体が共存している。個体数が 10 前後まで
落ちると選択圧が弱まり、脳の維持コスト `(* 0.004 (brain-complexity g))` では
bloat を削りきれない（§9 も参照）。「最小形に収束する」とまでは言えず、
**最小形が到達可能であることが示せた**、というのが正確なところ。

### 7.2 条件分岐は環境が要求したときだけ現れる

周期的な飢饉を入れ、移動コストを速度の2乗にすると:

```
条件分岐(if>)を持つ個体:      51% → 100%
speed-tree が energy を参照:  53% → 100%
```

> **注記**: この実験は同梱コードそのままでは再現しない。飢饉と2乗コストを
> 加えた改変版での結果であり、その改変は本リポジトリに入っていない。
> また 7.1 の環境で `if>` が淘汰されるという以前の記述は誤りだった。
> 実測では 7.1 の環境でも `if>` 保有率は 68% → 85% で残り続ける（上表）。
> `if>` は餌が潤沢でも中立に近く、消えるほどのコストは掛かっていない。

### 7.3 捕食の自然発生（CLOS版, 2000 tick）

既定の `*random-state*` で `(run-simulation)` を回したときの実測:

```
Tick  100 | 草食  236 | 捕食   1        ← 最初の捕食者が出現
Tick  300 | 草食   96 | 捕食   6        ← 獲物が減り個体数の底
Tick  600 | 草食  287 | 捕食  25
Tick  800 | 草食  518 | 捕食  82        ← 捕食者ピーク
Tick 1000 | 草食  560 | 捕食  40        ← 食い過ぎた反動で捕食者減
Tick 1500 | 草食  566 | 捕食  34
Tick 2000 | 草食  562 | 捕食  38
種転換イベント: 617 回 (→捕食 601 / →草食 16)
```

t=800 の 82 匹をピークに 30〜40 匹で振動する。**草食が減る → 捕食者が飢える →
草食が回復する**という捕食者-被食者サイクルが、個体群動態を明示的に書かずに出ている。

seed を変えても捕食者は定着する:

| seed | 2000 tick 時点 | 種転換イベント |
|---|---|---|
| 既定 | 草食 562 / 捕食 38 | 617 回（→捕食 601 / →草食 16） |
| 1 | 草食 572 / 捕食 28 | 540 回（→捕食 537 / →草食 3） |
| 2 | 草食 565 / 捕食 35 | 403 回（→捕食 390 / →草食 13） |
| 3 | 草食 561 / 捕食 39 | 814 回（→捕食 806 / →草食 8） |

どの seed でも →草食 の逆遷移が発生しており、`change-class` が可逆に効いている。

---

## 8. 調整の履歴（同じ失敗をしないために）

**捕食者が一度も出現しなかった。** 初期値 `*predator-threshold*` = 0.75 では、
攻撃性は閾値を超えるまで完全に中立なので**適応度平原**をランダムウォークで
渡りきれない。閾値 0.55・変異幅5倍で渡れるようになった。

**閾値を下げただけの版では共倒れした。** 捕食者が獲物を食い尽くし、
t=900 で草食7・捕食182 → t=1221 全滅。捕獲を確率的にし（0.35）、
捕食者の `eat-radius` を 8→5 に、維持費を 2.0 倍にして共存した。

**共存は自明ではなく、パラメータ空間の狭い領域にある。**

---

## 9. 既知の限界

- **総個体数が t=800 以降ずっと `pop-cap` 600 ちょうどに張り付いている。**
  §7.3 の表で草食+捕食が毎回きっかり 600 になるのはそのため。つまり
  「草食 562 / 捕食 38」の内訳は進化の結果でも、その合計は上限が決めている。
  **共存の一部は上限の産物。** 資源制限で自然に頭打ちになる設計に直すべき。
- **脳サイズが後半で膨らむ。** CLOS版の平均脳サイズは t=300 の 17.8 を底に、
  t=2000 では 28.9 まで戻る。増加が始まる t=800 は個体数が上限に達した時点と
  一致しており、**選択圧が弱まると bloat が再発する**ことを示している。
  GP版でも同様に 26.0 → 28.2（§7.1）。維持コストを個体数依存にするのが筋。
- **空間ハッシュの効果が限定的。** 1000オブジェクトで全走査比 2 倍
  （1.17秒 → 0.60秒 / 30 tick）止まり。感知半径が最大 130 で世界の幅 500 に
  対して大きすぎ、クエリが格子の大半を舐めている。世界を広げるか
  感知半径を絞らないと本来の効果は出ない。
- **記憶がない。** 内部状態を持つプリミティブがないので、履歴に依存する行動
  （反転回避、経路記憶）は進化しえない。
- **群れがない。** 他個体を参照する終端がないので、群れ行動も進化しえない。

最後の2つは「S式にしても Σ（部品の語彙）は人間が選ぶ」という原理的な話。
語彙に入れなければ、その行動は決して現れない。

---

## 10. 次にやるとしたら

1. **記憶の導入** — `(mem)` `(store x)` を終端・関数に足す。
   これだけで履歴依存の戦略が探索空間に入る。
2. **他個体の知覚** — `neighbor-angle` `neighbor-count` を足すと群れが可能になる。
3. **系統樹の記録** — 親のIDを個体に持たせ、脳の変遷を `print` して追う。
   S式なので系統樹の各ノードがそのまま人間可読。
4. **資源による個体数制限** — `pop-cap` を廃し、餌の再生速度だけで
   キャリング・キャパシティが決まるようにする。

---

## ライセンス

元リポジトリ https://github.com/srt-tkyk/LispCollection に準じる。
