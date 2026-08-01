;;;; brain.lisp — S式ゲノム（遺伝的プログラミング）の中核
;;;;
;;;; 遺伝子はリストそのもの。変異は部分木の書き換え、交叉は部分木の交換、
;;;; 表現型は COMPILE によるネイティブコード化。
;;;; 保存形式・変異対象・ソースコードが同一の表現であることが要点。

(defconstant +pi1+  (float pi 1.0))
(defconstant +2pi1+ (* 2.0 +pi1+))

(defparameter *max-depth* 4   "初期木の最大深さ")
(defparameter *max-size*  40  "木の最大ノード数（bloat 抑制）")
(defparameter *use-compiler* t "t なら COMPILE、nil なら木の直接解釈")

;;; ── プリミティブ集合 ─────────────────────────────────────
;;; 閉包性: すべての関数・終端が single-float を返す。
;;; よって任意の部分木を任意の位置に差し込んでも文法的・型的に妥当になる。

(defparameter *terminals*
  '(food-angle   ; 最寄り餌への相対角 -π..π（見えなければ 0）
    food-dist    ; 最寄り餌への正規化距離 0..1（見えなければ 1）
    energy       ; 正規化エネルギー 0..1
    age          ; 正規化年齢 0..1
    noise))      ; -1..1 の乱数

(defparameter *functions*
  '((+ . 2) (- . 2) (* . 2) (% . 2)   ; % は保護付き除算
    (if> . 4)                          ; (if> a b c d) = a>b なら c、さもなくば d
    (sin . 1) (abs . 1)))

(defun random-elt (seq) (elt seq (random (length seq))))

(defun random-terminal ()
  (if (< (random 1.0) 0.35)
      (- (random 4.0) 2.0)             ; エフェメラル定数
      (random-elt *terminals*)))

(defun random-tree (&optional (depth *max-depth*))
  (if (or (<= depth 0) (< (random 1.0) 0.25))
      (random-terminal)
      (let ((f (random-elt *functions*)))
        (cons (car f)
              (loop repeat (cdr f) collect (random-tree (1- depth)))))))

;;; ── 木の操作 ─────────────────────────────────────────────

(defun tree-size (tree)
  (if (consp tree)
      (1+ (reduce #'+ (mapcar #'tree-size (cdr tree))))
      1))

(defun subtree-at (tree n)
  "行きがけ順で n 番目の部分木を返す。"
  (let ((i -1))
    (labels ((walk (tr)
               (incf i)
               (if (= i n)
                   (return-from subtree-at tr)
                   (when (consp tr) (mapc #'walk (cdr tr))))))
      (walk tree))
    tree))

(defun replace-subtree (tree n new)
  "行きがけ順 n 番目の部分木を NEW に差し替えた新しい木を返す（非破壊）。"
  (let ((i -1))
    (labels ((walk (tr)
               (incf i)
               (cond ((= i n) new)
                     ((consp tr) (cons (car tr) (mapcar #'walk (cdr tr))))
                     (t tr))))
      (walk tree))))

(defun prune (tree fallback)
  "大きくなりすぎた木は採用せず FALLBACK を返す。"
  (if (> (tree-size tree) *max-size*) fallback tree))

;;; ── 木の検査 ─────────────────────────────────────────────
;;; 構造進化の測定（alife-herbivore.lisp）と系統の可視化（lineage.lisp）の
;;; 両方から使うので、共通の brain.lisp に置く。

(defun uses-p (tree sym)
  "TREE のどこかに終端 SYM が現れるか。"
  (if (consp tree) (some (lambda (x) (uses-p x sym)) tree) (eq tree sym)))

(defun count-node (tree sym)
  "関数節 SYM の出現回数。"
  (if (consp tree)
      (+ (if (eq (car tree) sym) 1 0)
         (reduce #'+ (mapcar (lambda (x) (count-node x sym)) (cdr tree))))
      0))

;;; ── 変異と交叉 ───────────────────────────────────────────

(defun mutate-tree (tree &key (rate 0.20))
  "確率 RATE で部分木を1箇所書き換える。ここで構造そのものが変わる。"
  (if (> (random 1.0) rate)
      tree
      (let* ((n   (random (tree-size tree)))
             (sub (subtree-at tree n))
             (new (if (and (consp sub) (< (random 1.0) 0.3))
                      (random-terminal)          ; 縮小変異
                      (random-tree 2))))         ; 成長変異
        (prune (replace-subtree tree n new) tree))))

(defun crossover (a b)
  "A の部分木ひとつを B の部分木で置き換える。両親のどちらも持たない構造が生じうる。"
  (let ((na (random (tree-size a)))
        (nb (random (tree-size b))))
    (prune (replace-subtree a na (subtree-at b nb)) a)))

;;; ── 表現型化: 解釈実行 ───────────────────────────────────

(declaim (inline safe-div sane))

(defun safe-div (a b)
  (if (< (abs b) 1e-6) 1.0 (/ a b)))

(defun sane (x)
  "NaN / 無限大 / 発散を 0.0 に潰す。"
  (if (and (= x x) (< (abs x) 1e10)) x 0.0))

(defun brain-eval (tree fa fd en ag)
  (if (atom tree)
      (case tree
        (food-angle fa)
        (food-dist  fd)
        (energy     en)
        (age        ag)
        (noise      (- (random 2.0) 1.0))
        (t (if (numberp tree) (float tree 1.0) 0.0)))
      (let ((a (cdr tree)))
        (macrolet ((ev (k) `(brain-eval (nth ,k a) fa fd en ag)))
          (case (car tree)
            (+   (+ (ev 0) (ev 1)))
            (-   (- (ev 0) (ev 1)))
            (*   (* (ev 0) (ev 1)))
            (%   (safe-div (ev 0) (ev 1)))
            (sin (sin (ev 0)))
            (abs (abs (ev 0)))
            (if> (if (> (ev 0) (ev 1)) (ev 2) (ev 3)))   ; 遅延評価
            (t 0.0))))))

;;; ── 表現型化: ネイティブコンパイル ───────────────────────

(defun emit (tree)
  "遺伝子の木を Lisp のソースコードに変換する。ほとんど恒等写像であることに注意。"
  (cond ((numberp tree) (float tree 1.0))
        ((eq tree 'noise) '(- (random 2.0) 1.0))
        ((symbolp tree) tree)                  ; 終端はそのまま lambda の引数名になる
        (t (let ((a (cdr tree)))
             (case (car tree)
               (%   `(safe-div ,(emit (first a)) ,(emit (second a))))
               (if> `(if (> ,(emit (first a)) ,(emit (second a)))
                         ,(emit (third a))
                         ,(emit (fourth a))))
               (t   (cons (car tree) (mapcar #'emit a))))))))

(defun compile-brain (tree)
  (handler-bind ((warning #'muffle-warning))
    (compile nil
      `(lambda (food-angle food-dist energy age)
         (declare (type single-float food-angle food-dist energy age)
                  (ignorable food-angle food-dist energy age)
                  (optimize (speed 3) (safety 1)))
         (sane ,(emit tree))))))

(defvar *brain-cache* (make-hash-table :test #'equal)
  "木そのものをキーにした関数キャッシュ。無変異で継承された脳は再コンパイルしない。")

(defun brain-fn (tree)
  (if *use-compiler*
      (or (gethash tree *brain-cache*)
          (setf (gethash tree *brain-cache*) (compile-brain tree)))
      (lambda (fa fd en ag) (sane (brain-eval tree fa fd en ag)))))

(defun run-brain (tree fa fd en ag)
  (if *use-compiler*
      (funcall (brain-fn tree) fa fd en ag)
      (sane (brain-eval tree fa fd en ag))))
