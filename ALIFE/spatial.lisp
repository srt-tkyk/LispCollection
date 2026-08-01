;;;; spatial.lisp — トーラス世界の空間ハッシュ
;;;;
;;;; 近傍探索を素直に全走査で書くと O(個体数 × 餌数) になる。
;;;; 格子分割して近傍セルだけ見ることで O(N) に落とす。

(defstruct (sindex (:constructor %make-sindex))
  cell-size ncols nrows width height table)

(defun make-sindex (width height &optional (cell-size 50.0))
  (%make-sindex :cell-size cell-size
                :ncols (ceiling width cell-size)
                :nrows (ceiling height cell-size)
                :width width :height height
                :table (make-hash-table :test #'eql)))

(declaim (inline cell-key))
(defun cell-key (idx cx cy)
  (+ (* (mod cy (sindex-nrows idx)) (sindex-ncols idx))
     (mod cx (sindex-ncols idx))))

(defun sindex-clear (idx) (clrhash (sindex-table idx)))

(defun sindex-insert (idx obj x y)
  (let ((cx (floor x (sindex-cell-size idx)))
        (cy (floor y (sindex-cell-size idx))))
    (push obj (gethash (cell-key idx cx cy) (sindex-table idx)))))

(defun sindex-nearby (idx x y radius)
  "半径 RADIUS に届きうるセルの中身をまとめて返す（厳密な距離判定は呼び出し側）。"
  (let* ((cs (sindex-cell-size idx))
         (r  (ceiling radius cs))
         (cx (floor x cs)) (cy (floor y cs))
         (acc '()))
    (loop for dy from (- r) to r do
      (loop for dx from (- r) to r do
        ;; NCONC は不可。バケットはハッシュテーブルが保持している実体なので
        ;; 破壊すると索引が壊れる（循環リストになりうる）。
        (let ((bucket (gethash (cell-key idx (+ cx dx) (+ cy dy)) (sindex-table idx))))
          (dolist (o bucket) (push o acc)))))
    acc))

;;; ── トーラス距離 ─────────────────────────────────────────
;;; 世界が mod で巻き戻る以上、距離もトーラス上で測るべき。

(declaim (inline torus-delta))
(defun torus-delta (a b size)
  "A から B への最短変位（符号つき）。"
  (let ((d (- b a)) (half (* 0.5 size)))
    (cond ((>  d half) (- d size))
          ((< d (- half)) (+ d size))
          (t d))))

(defun torus-dist (x1 y1 x2 y2 w h)
  (let ((dx (torus-delta x1 x2 w)) (dy (torus-delta y1 y2 h)))
    (sqrt (+ (* dx dx) (* dy dy)))))
