;;;; viz.lisp — ゲノム（S式）と行動の可視化
;;;;
;;;; 構成:
;;;;   Lisp が全世代分の SVG を生成 → 1枚の HTML に全部埋め込む
;;;;   → JS はスライダで表示を切り替えるだけ
;;;; JSON も、クライアント側の描画も要らない。単一ファイルで完結する。
;;;;
;;;;   (report "lineage.html" w)

;;; ── SVG の下ごしらえ ─────────────────────────────────────

(defun esc (s)
  (with-output-to-string (o)
    (loop for c across (princ-to-string s) do
      (case c (#\< (write-string "&lt;" o)) (#\> (write-string "&gt;" o))
              (#\& (write-string "&amp;" o)) (t (write-char c o))))))

(defun hex (r g b) (format nil "#~2,'0x~2,'0x~2,'0x" r g b))

;;; ── 木のレイアウト ───────────────────────────────────────
;;; 葉を左から順に並べ、内部ノードは子の平均に置く。

(defstruct node label x y depth changed children)

(defun layout-tree (tree diff &optional (depth 0))
  "TREE と並行構造 DIFF から、座標未定のノード木を作る。"
  (let ((changed (if (consp diff) (eq (car diff) :changed) (eq diff :changed))))
    (if (consp tree)
        (make-node :label (string (car tree)) :depth depth :changed changed
                   :children (loop for c in (cdr tree)
                                   for d in (if (consp diff) (cdr diff)
                                                (make-list (length (cdr tree))
                                                           :initial-element diff))
                                   collect (layout-tree c d (1+ depth))))
        (make-node :label (if (numberp tree) (format nil "~,2f" tree) (string tree))
                   :depth depth :changed changed :children nil))))

(defun assign-coords (node &key (xstep 62) (ystep 58))
  (let ((leaf 0))
    (labels ((walk (n)
               (setf (node-y n) (+ 30 (* ystep (node-depth n))))
               (if (node-children n)
                   (progn (mapc #'walk (node-children n))
                          (setf (node-x n)
                                (/ (+ (node-x (first (node-children n)))
                                      (node-x (car (last (node-children n))))) 2)))
                   (progn (setf (node-x n) (+ 40 (* xstep leaf))) (incf leaf)))))
      (walk node))
    (values node (* xstep (max 1 leaf)))))

(defun node-depth-max (n)
  (if (node-children n)
      (reduce #'max (mapcar #'node-depth-max (node-children n)))
      (node-depth n)))

;;; ── 脳の木を SVG に ──────────────────────────────────────

(defparameter *terminal-colors*
  '(("FOOD-ANGLE" . "#4ea3ff") ("FOOD-DIST" . "#46c8a0")
    ("ENERGY" . "#ffb23e") ("AGE" . "#c58cff") ("NOISE" . "#7a8390")))

(defun node-fill (n)
  (cond ((node-changed n) "#ff4d5e")
        ((cdr (assoc (node-label n) *terminal-colors* :test #'string=)))
        ((node-children n) "#2c3440")
        (t "#3a3f4a")))

(defun brain->svg (tree diff &key (title ""))
  (multiple-value-bind (root width) (assign-coords (layout-tree tree diff))
    (let* ((w (max 420 (+ width 80)))
           (h (+ 80 (* 58 (1+ (node-depth-max root))))))
      (with-output-to-string (o)
        (format o "<svg viewBox='0 0 ~d ~d' width='100%' xmlns='http://www.w3.org/2000/svg' font-family='ui-monospace,Menlo,monospace'>" w h)
        (format o "<text x='10' y='16' fill='#8b95a5' font-size='11'>~a</text>" (esc title))
        ;; 枝
        (labels ((edges (n)
                   (dolist (c (node-children n))
                     (format o "<line x1='~,1f' y1='~,1f' x2='~,1f' y2='~,1f' stroke='~a' stroke-width='~a'/>"
                             (node-x n) (node-y n) (node-x c) (node-y c)
                             (if (node-changed c) "#ff4d5e" "#39404d")
                             (if (node-changed c) 2.2 1.4))
                     (edges c))))
          (edges root))
        ;; ノード
        (labels ((nodes (n)
                   (let ((r (if (node-children n) 17 20)))
                     (format o "<circle cx='~,1f' cy='~,1f' r='~d' fill='~a' stroke='~a' stroke-width='~a'/>"
                             (node-x n) (node-y n) r (node-fill n)
                             (if (node-changed n) "#ff8a94" "#4a5464")
                             (if (node-changed n) 2.5 1))
                     (format o "<text x='~,1f' y='~,1f' fill='#e8edf4' font-size='~d' text-anchor='middle'>~a</text>"
                             (node-x n) (+ (node-y n) 4)
                             (if (> (length (node-label n)) 6) 8 11)
                             (esc (node-label n))))
                   (mapc #'nodes (node-children n))))
          (nodes root))
        (format o "</svg>")))))

;;; ── 応答面（遺伝子型→表現型） ────────────────────────────

(defparameter *color-levels* 14
  "階調数。少なくすると等高線として読めるようになり、同時に SVG が軽くなる。")

(defun diverging-color (v scale)
  "0 を中心に 青 ← 灰 → 赤。階調は *color-levels* 段に量子化する。"
  (let* ((raw (max -1.0 (min 1.0 (/ v (max 1e-6 scale)))))
         (tt (/ (fround (* raw *color-levels*)) (float *color-levels*)))
         (a (abs tt)))
    (if (minusp tt)
        (hex (round (* 60 (- 1 a))) (round (+ 70 (* 90 a))) (round (+ 90 (* 165 a))))
        (hex (round (+ 90 (* 165 a))) (round (* 80 (- 1 a))) (round (* 90 (- 1 a)))))))

(defun surface->svg (tree &key (n 40) (title "") (scale nil))
  (let* ((arr (response-surface tree :nx n :ny n))
         (mx (let ((m 1e-6))
               (dotimes (i (array-total-size arr) m)
                 (setf m (max m (abs (row-major-aref arr i)))))))
         (s (or scale mx))
         (cell 7) (side (* n cell)))
    (with-output-to-string (o)
      (format o "<svg viewBox='0 0 ~d ~d' width='100%' xmlns='http://www.w3.org/2000/svg' font-family='ui-monospace,Menlo,monospace'>"
              (+ side 70) (+ side 52))
      (format o "<text x='0' y='12' fill='#8b95a5' font-size='11'>~a</text>" (esc title))
      ;; 横方向に同色のセルを結合してから出力する。
      ;; 応答面は滑らかなのでこれだけでノード数が数分の一になる。
      (dotimes (j n)
        (let ((run-start 0) (run-col (diverging-color (aref arr j 0) s)))
          (loop for i from 1 to n do
            (let ((c (if (< i n) (diverging-color (aref arr j i) s) nil)))
              (when (or (null c) (string/= c run-col))
                (format o "<rect x='~d' y='~d' width='~d' height='~d' fill='~a'/>"
                        (+ 34 (* run-start cell)) (+ 22 (* j cell))
                        (1+ (* (- i run-start) cell)) (1+ cell) run-col)
                (setf run-start i run-col c))))))
      ;; 軸
      (format o "<text x='~d' y='~d' fill='#6b7484' font-size='10' text-anchor='middle'>food-angle  -π → π</text>"
              (+ 34 (/ side 2)) (+ side 40))
      (format o "<text x='8' y='~d' fill='#6b7484' font-size='10' transform='rotate(-90 8 ~d)' text-anchor='middle'>food-dist 0→1</text>"
              (+ 22 (/ side 2)) (+ 22 (/ side 2)))
      (format o "<text x='~d' y='~d' fill='#6b7484' font-size='10'>±~,2f</text>"
              (+ side 38) 30 s)
      (format o "</svg>"))))

;;; ── 集団統計の時系列 ─────────────────────────────────────

(defparameter *timeline-series*
  '((:uses-angle  "#4ea3ff" "turn が food-angle 参照" :ratio)
    (:uses-energy "#ffb23e" "speed が energy 参照"    :ratio)
    (:has-cond    "#c58cff" "if> を保有"              :ratio)
    (:brain       "#46c8a0" "脳サイズ"                :brain)
    (:pred        "#ff4d5e" "捕食者数"                :pred)))

(defun timeline->svg (timeline &key (w 920) (ph 260))
  "0..1 の比率系列と、正規化した個数系列を重ねる。凡例はプロットの外に置く。"
  (let* ((tl (sort (copy-list timeline) #'< :key (lambda (r) (getf r :tick))))
         (n (length tl)))
    (when (< n 2) (return-from timeline->svg "<svg/>"))
    (let* ((tmax (max 1 (getf (car (last tl)) :tick)))
           (pmax (max 1 (reduce #'max (mapcar (lambda (r) (getf r :pred)) tl))))
           (bmax (max 1 (reduce #'max (mapcar (lambda (r) (getf r :brain)) tl))))
           (top 16) (bot (- ph 34)) (left 52) (right (- w 18))
           (h (+ ph 46)))
      (flet ((px (tk) (+ left (* (- right left) (/ tk (float tmax)))))
             (py (v)  (- bot (* (- bot top) (max 0.0 (min 1.0 v)))))
             (norm (v kind) (case kind
                              (:ratio v)
                              (:brain (/ v bmax))
                              (:pred  (/ v (float pmax))))))
        (with-output-to-string (o)
          (format o "<svg viewBox='0 0 ~d ~d' width='100%' xmlns='http://www.w3.org/2000/svg' font-family='ui-monospace,Menlo,monospace'>" w h)
          ;; 横罫線
          (dolist (g '(0.0 0.25 0.5 0.75 1.0))
            (format o "<line x1='~d' y1='~,1f' x2='~d' y2='~,1f' stroke='#242a34'/>"
                    left (py g) right (py g))
            (format o "<text x='~d' y='~,1f' fill='#5c6472' font-size='9' text-anchor='end'>~,2f</text>"
                    (- left 6) (+ 3 (py g)) g))
          ;; 系列
          (dolist (spec *timeline-series*)
            (destructuring-bind (key color label kind) spec
              (declare (ignore label))
              (format o "<polyline fill='none' stroke='~a' stroke-width='2' opacity='0.92' points='" color)
              (dolist (r tl)
                (format o "~,1f,~,1f " (px (getf r :tick)) (py (norm (getf r key) kind))))
              (format o "'/>")))
          ;; 横軸
          (format o "<text x='~d' y='~,1f' fill='#5c6472' font-size='9'>0</text>" left (+ bot 14))
          (format o "<text x='~d' y='~,1f' fill='#5c6472' font-size='9' text-anchor='end'>tick ~d</text>"
                  right (+ bot 14) tmax)
          ;; 凡例（プロットの下、横並び）
          (let ((x left) (y (+ bot 34)))
            (dolist (spec *timeline-series*)
              (destructuring-bind (key color label kind) spec
                (declare (ignore key))
                (format o "<rect x='~d' y='~d' width='12' height='3' rx='1.5' fill='~a'/>" x y color)
                (format o "<text x='~d' y='~d' fill='#8b95a5' font-size='10'>~a~a</text>"
                        (+ x 17) (+ y 4) (esc label)
                        (case kind (:brain (format nil " (最大 ~,1f)" bmax))
                                   (:pred  (format nil " (最大 ~d)" pmax))
                                   (t "")))
                (incf x (+ 30 (* 6.6 (+ (length label) 12))))
                (when (> x (- right 160)) (setf x left) (incf y 17)))))
          (format o "</svg>"))))))

;;; ── HTML レポート ────────────────────────────────────────

(defparameter *css* "
body{background:#12151b;color:#dbe2ea;font-family:ui-monospace,Menlo,monospace;margin:0;padding:24px}
h1{font-size:16px;color:#8b95a5;font-weight:500;margin:0 0 4px}
h2{font-size:13px;color:#8b95a5;font-weight:500;margin:28px 0 8px;
   border-bottom:1px solid #232935;padding-bottom:6px}
.panel{background:#181c24;border:1px solid #232935;border-radius:8px;padding:14px;margin-bottom:14px}
.row{display:flex;gap:14px;flex-wrap:wrap}
.col{flex:1;min-width:320px}
.gen{display:none}.gen.on{display:block}
code{background:#0e1116;padding:2px 6px;border-radius:4px;color:#9fd2ff;font-size:12px;
     display:block;white-space:pre-wrap;word-break:break-all;line-height:1.5;margin:4px 0}
.meta{color:#6b7484;font-size:11px;margin-bottom:6px}
input[type=range]{width:100%;margin:8px 0}
.tag{display:inline-block;padding:2px 8px;border-radius:10px;font-size:10px;margin-right:6px}
.hd{background:#3a2830;color:#ff8a94}
.legend{font-size:10px;color:#6b7484;margin-top:6px}
.sw{display:inline-block;width:9px;height:9px;border-radius:50%;margin:0 4px 0 10px;vertical-align:-1px}
")

(defun genome-card (before after diff idx)
  "1世代分のパネル。左に木の図、右に応答面。"
  (with-output-to-string (o)
    (format o "<div class='gen' id='g~d'>" idx)
    (format o "<div class='meta'><span class='tag hd'>変異 ~d</span> id ~a (tick ~a) → id ~a (tick ~a) / 変化ノード ~d</div>"
            (1+ idx) (rec-id before) (rec-birth before) (rec-id after) (rec-birth after)
            (changed-node-count diff))
    (format o "<div class='row'>")
    ;; 木
    (format o "<div class='col panel'>~a" (brain->svg (rec-turn after) diff :title "turn-tree（赤 = 親から変化）"))
    (format o "<div class='legend'>親: <code>~a</code>子: <code>~a</code></div></div>"
            (esc (format nil "~s" (rec-turn before))) (esc (format nil "~s" (rec-turn after))))
    ;; 応答面 2枚
    (format o "<div class='col panel'><div class='row'>")
    (format o "<div class='col'>~a</div>" (surface->svg (rec-turn before) :title "親の行動"))
    (format o "<div class='col'>~a</div>" (surface->svg (rec-turn after)  :title "子の行動"))
    (format o "</div><div class='legend'>応答面RMS差 ~,3f — 0 に近ければ<b>中立変異</b>（S式は変わったが行動は同じ）<br>"
            (surface-distance (response-surface (rec-turn before) :nx 40 :ny 40)
                              (response-surface (rec-turn after)  :nx 40 :ny 40)))
    (format o "<span class='sw' style='background:#4ea3ff'></span>左旋回<span class='sw' style='background:#c85a5a'></span>右旋回</div></div>")
    (format o "</div></div>")))

(defun write-report (path w &key (max-gens 40))
  "系統・脳の変化・行動・集団統計を1枚の HTML にまとめる。"
  (let* ((chain (or (richest-lineage w) '()))
         (muts  (mutation-points chain))
         (muts  (if (> (length muts) max-gens)
                    (last muts max-gens) muts))
         (n (length muts)))
    (with-open-file (o path :direction :output :if-exists :supersede)
      (format o "<!DOCTYPE html><html><head><meta charset='utf-8'><title>ALIFE lineage</title><style>~a</style></head><body>" *css*)
      (format o "<h1>S式ゲノムの変化と行動</h1>")
      (format o "<div class='meta'>tick ~d / 記録個体 ~d / 系統長 ~d 世代 / うち turn-tree が変化した世代 ~d</div>"
              (world-tick w) (hash-table-count *lineage*) (length chain) (length muts))

      (format o "<h2>1. 集団全体の構造進化</h2><div class='panel'>~a</div>"
              (timeline->svg *timeline*))

      ;; 中立変異の集計
      (when (plusp n)
        (let* ((rms (mapcar (lambda (m)
                              (surface-distance
                                (response-surface (rec-turn (first m))  :nx 32 :ny 32)
                                (response-surface (rec-turn (second m)) :nx 32 :ny 32)))
                            muts))
               (neutral (count-if (lambda (v) (< v 0.01)) rms)))
          (format o "<h2>2. 中立変異</h2><div class='panel'><div class='meta'>~d 変異のうち <b style='color:#46c8a0'>~d 件が中立</b>（応答面RMS &lt; 0.01 — S式は変わったが行動は同一）</div>" n neutral)
          (format o "<div class='legend'>各変異の行動変化量（RMS）: ~{~,3f ~}</div></div>" rms)))

      (if (zerop n)
          (format o "<h2>3. 系統上の変異</h2><div class='panel'>変異が記録されませんでした。tick を増やしてください。</div>")
          (progn
            (format o "<h2>3. 系統をたどる（~d 変異）</h2>" n)
            (format o "<div class='panel'><input type='range' min='0' max='~d' value='~d' id='sl' oninput='show(this.value)'>" (1- n) (1- n))
            (format o "<div class='meta' id='lbl'></div></div>")
            (loop for m in muts for i from 0
                  do (write-string (genome-card (first m) (second m) (third m) i) o))
            (format o "<script>
function show(v){document.querySelectorAll('.gen').forEach(function(e){e.classList.remove('on')});
document.getElementById('g'+v).classList.add('on');
document.getElementById('lbl').textContent='変異 '+(+v+1)+' / ~d';}
show(~d);document.addEventListener('keydown',function(e){var s=document.getElementById('sl');
if(e.key=='ArrowRight'&&+s.value<+s.max){s.value=+s.value+1;show(s.value)}
if(e.key=='ArrowLeft'&&+s.value>0){s.value=+s.value-1;show(s.value)}});
</script>" n (1- n))))

      (format o "<h2>4. 現存個体の脳</h2><div class='panel'>")
      (dolist (org (subseq (sort (copy-list (world-organisms w)) #'> :key #'organism-age)
                           0 (min 4 (length (world-organisms w)))))
        (let ((g (organism-genome org)))
          (format o "<div class='meta'>~a  age ~d  agg ~,2f</div><code>turn : ~a</code><code>speed: ~a</code>"
                  (class-name (class-of org)) (organism-age org) (genome-aggression g)
                  (esc (format nil "~s" (genome-turn-tree g)))
                  (esc (format nil "~s" (genome-speed-tree g))))))
      (format o "</div></body></html>"))
    (format t "~%レポート出力: ~a  (変異 ~d コマ)~%" path n)
    path))

;;; ── ワンショット実行 ─────────────────────────────────────

(defun run-report (&key (ticks 3000) (n-org 200) (n-food 250)
                        (snap-every 25) (output "lineage.html"))
  (setf *timeline* '() *speciation-log* '())
  (let ((w (create-world n-org n-food)))
    (start-logging) (log-founders w)
    (dotimes (i ticks)
      (world-step w :food-cap n-food)
      (when (zerop (mod i snap-every)) (snapshot w))
      (when (zerop (mod (1+ i) 500)) (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (world-tick w)) (return)))
    (stop-logging)
    (write-report output w)
    w))
