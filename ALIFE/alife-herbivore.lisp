;;;; alife-herbivore.lisp — 草食版 進化シミュレーション（草食のみ1種）
;;;;
;;;;   sbcl --load brain.lisp --load spatial.lisp --load alife-herbivore.lisp \
;;;;        --eval '(run-simulation)' --quit
;;;;
;;;; ゲノム = 形態パラメータ（連続値）+ 脳2本（S式の木）。
;;;; 行動は behave にハードコードされず、木の合成として進化する。
;;;; alife-predator.lisp との違いは、捕食者がなく草食のみであること、
;;;; 有性生殖（交叉）があること、近傍探索が全走査であること。
;;;;
;;;; 近傍探索は全走査のまま（構造が単純なほうを残す意図）だが、距離だけは
;;;; spatial.lisp のトーラス距離を使う。世界が mod で巻き戻る以上、
;;;; ユークリッド距離では端をまたいだ餌を見落とすため。

(defun clamp (x lo hi) (max lo (min hi x)))

(defun gauss (mean sigma)
  (let ((u1 (+ 1e-10 (random 1.0))) (u2 (random 1.0)))
    (+ mean (* sigma (sqrt (* -2.0 (log u1))) (cos (* +2pi1+ u2))))))

;;; ── ゲノム ───────────────────────────────────────────────

(defstruct genome
  speed turn-rate metabol sense-r hue
  turn-tree      ; 旋回量を決める木
  speed-tree)    ; 速度を決める木（0 を返せば休息＝省エネ）

(defun make-random-genome ()
  (make-genome :speed     (+ 0.5 (random 1.5))
               :turn-rate (+ 0.05 (random 0.15))
               :metabol   (+ 0.08 (random 0.2))
               :sense-r   (+ 30.0 (random 60.0))
               :hue       (random 360.0)
               :turn-tree  (random-tree)
               :speed-tree (random-tree)))

(defun brain-complexity (g)
  (+ (tree-size (genome-turn-tree g)) (tree-size (genome-speed-tree g))))

(defun mutate (g rate)
  "数値スロットはガウス変異、木スロットは部分木変異。"
  (let ((scale (* rate 0.05)))
    (make-genome
      :speed      (clamp (+ (genome-speed g)     (gauss 0 (* 0.1 scale)))  0.3 3.5)
      :turn-rate  (clamp (+ (genome-turn-rate g) (gauss 0 (* 0.02 scale))) 0.02 0.4)
      :metabol    (clamp (+ (genome-metabol g)   (gauss 0 (* 0.03 scale))) 0.05 0.6)
      :sense-r    (clamp (+ (genome-sense-r g)   (gauss 0 (* 5.0 scale)))  15.0 130.0)
      :hue        (mod   (+ (genome-hue g)       (gauss 0 (* 12 scale)))   360)
      :turn-tree  (mutate-tree (genome-turn-tree g))
      :speed-tree (mutate-tree (genome-speed-tree g)))))

(defun recombine (g1 g2)
  "有性生殖: 数値は平均、木は部分木交叉。"
  (make-genome
    :speed      (/ (+ (genome-speed g1)     (genome-speed g2))     2)
    :turn-rate  (/ (+ (genome-turn-rate g1) (genome-turn-rate g2)) 2)
    :metabol    (/ (+ (genome-metabol g1)   (genome-metabol g2))   2)
    :sense-r    (/ (+ (genome-sense-r g1)   (genome-sense-r g2))   2)
    :hue        (mod (/ (+ (genome-hue g1)  (genome-hue g2))       2) 360)
    :turn-tree  (mutate-tree (crossover (genome-turn-tree g1)  (genome-turn-tree g2)))
    :speed-tree (mutate-tree (crossover (genome-speed-tree g1) (genome-speed-tree g2)))))

;;; ── 個体・世界 ───────────────────────────────────────────

(defstruct organism genome
  (x (random 500.0)) (y (random 500.0))
  (angle (random +2pi1+)) (energy 50.0) (age 0))

(defstruct food (x (random 500.0)) (y (random 500.0)) (value 20.0))

(defun create-world (n-org n-food)
  (list :tick 0 :width 500.0 :height 500.0
        :organisms (loop repeat n-org collect
                         (make-organism :genome (make-random-genome)))
        :foods (loop repeat n-food collect (make-food))))

(defun world-tick      (w) (getf w :tick))
(defun world-width     (w) (getf w :width))
(defun world-height    (w) (getf w :height))
(defun world-organisms (w) (getf w :organisms))
(defun world-foods     (w) (getf w :foods))
(defun (setf world-organisms) (v w) (setf (getf w :organisms) v))
(defun (setf world-foods)     (v w) (setf (getf w :foods) v))

;;; ── 知覚 ─────────────────────────────────────────────────

(defun nearest-food (org w sense-r)
  (let ((best nil) (best-d sense-r)
        (ww (world-width w)) (hh (world-height w)))
    (dolist (f (world-foods w) best)
      (let ((d (torus-dist (organism-x org) (organism-y org)
                           (food-x f) (food-y f) ww hh)))
        (when (< d best-d) (setf best f best-d d))))))

(defun nearest-organism (org w radius)
  (let ((best nil) (best-d radius)
        (ww (world-width w)) (hh (world-height w)))
    (dolist (o (world-organisms w) best)
      (unless (eq o org)
        (let ((d (torus-dist (organism-x org) (organism-y org)
                             (organism-x o)   (organism-y o) ww hh)))
          (when (< d best-d) (setf best o best-d d)))))))

(defun relative-angle (org f w)
  "端をまたぐ場合は巻き戻った側の向きを返す。"
  (let* ((dx (torus-delta (organism-x org) (food-x f) (world-width w)))
         (dy (torus-delta (organism-y org) (food-y f) (world-height w)))
         (d  (- (atan dy dx) (organism-angle org))))
    (float (- (mod (+ d +pi1+) +2pi1+) +pi1+) 1.0)))

;;; ── 行動 ─────────────────────────────────────────────────

(defun move-org (org speed w)
  (incf (organism-x org) (* speed (cos (organism-angle org))))
  (incf (organism-y org) (* speed (sin (organism-angle org))))
  (setf (organism-x org) (mod (organism-x org) (world-width w))
        (organism-y org) (mod (organism-y org) (world-height w))))

(defun eat-food (org w)
  (let ((ww (world-width w)) (hh (world-height w)))
    (setf (world-foods w)
          (remove-if (lambda (f)
                       (when (< (torus-dist (organism-x org) (organism-y org)
                                            (food-x f) (food-y f) ww hh) 8.0)
                         (incf (organism-energy org) (food-value f)) t))
                     (world-foods w)))))

(defparameter *sexual* t)
(defparameter *mate-radius* 40.0)

(defun try-reproduce (org w)
  (when (> (organism-energy org) 75)
    (decf (organism-energy org) 38.0)
    (let* ((mate (and *sexual* (nearest-organism org w *mate-radius*)))
           (child-genome (if mate
                             (recombine (organism-genome org) (organism-genome mate))
                             (mutate (organism-genome org) 1.0))))
      (push (make-organism :genome child-genome
                           :x (+ (organism-x org) (gauss 0 5.0))
                           :y (+ (organism-y org) (gauss 0 5.0))
                           :energy 35.0)
            (world-organisms w)))))

(defun behave (org w)
  (let* ((g    (organism-genome org))
         (food (nearest-food org w (genome-sense-r g)))
         ;; 脳への入力
         (fa (if food (relative-angle org food w) 0.0))
         (fd (if food (float (/ (torus-dist (organism-x org) (organism-y org)
                                            (food-x food) (food-y food)
                                            (world-width w) (world-height w))
                                (genome-sense-r g)) 1.0)
                 1.0))
         (en (clamp (/ (organism-energy org) 100.0) 0.0 1.0))
         (ag (clamp (/ (organism-age org) 200.0) 0.0 1.0))
         ;; 脳の出力
         (turn (run-brain (genome-turn-tree g)  fa fd en ag))
         (spd  (run-brain (genome-speed-tree g) fa fd en ag))
         (v (clamp spd 0.0 (genome-speed g))))
    (incf (organism-angle org)
          (clamp turn (- (genome-turn-rate g)) (genome-turn-rate g)))
    (move-org org v w)
    (eat-food org w)
    ;; 代謝: 基礎 + 移動 + 感覚器 + 脳の維持コスト
    (decf (organism-energy org)
          (+ (genome-metabol g)
             (* v 0.018)
             (* (genome-sense-r g) 0.0008)
             (* 0.004 (brain-complexity g))))
    (incf (organism-age org))
    (try-reproduce org w)))

(defun world-step (w &key (food-cap 80) (pop-cap 400))
  (incf (getf w :tick))
  (dolist (org (world-organisms w)) (behave org w))
  (setf (world-organisms w)
        (remove-if (lambda (o) (<= (organism-energy o) 0)) (world-organisms w)))
  ;; 個体数の上限（暴走防止）
  (let ((orgs (world-organisms w)))
    (when (> (length orgs) pop-cap)
      (setf (world-organisms w) (subseq orgs 0 pop-cap))))
  (let ((n (length (world-foods w))))
    (when (< n food-cap)
      (dotimes (_ (- food-cap n)) (push (make-food) (world-foods w))))))

;;; ── 観測 ─────────────────────────────────────────────────

(defun print-stats (w)
  (let* ((orgs (world-organisms w)) (n (length orgs)))
    (if (zerop n)
        (format t "Tick ~4d | 絶滅...~%" (getf w :tick))
        (let ((avg-eng  (/ (reduce #'+ (mapcar #'organism-energy orgs)) n))
              (avg-tree (/ (reduce #'+ (mapcar (lambda (o) (brain-complexity (organism-genome o))) orgs))
                           (float n)))
              (avg-sns  (/ (reduce #'+ (mapcar (lambda (o) (genome-sense-r (organism-genome o))) orgs)) n)))
          (format t "Tick ~4d | 個体数 ~4d | 平均E ~6,1f | 脳サイズ ~5,1f | 感知半径 ~5,1f~%"
                  (getf w :tick) n avg-eng avg-tree avg-sns)))))

(defun show-brains (w &optional (n 3))
  "生き残っている個体の脳をソースコードとして印字する。
   進化した行動を人間が読めるのが S 式表現の実利。"
  (let ((top (subseq (sort (copy-list (world-organisms w)) #'>
                           :key #'organism-age)
                     0 (min n (length (world-organisms w))))))
    (format t "~%── 長寿個体の脳 ──────────────────────────~%")
    (dolist (o top)
      (let ((g (organism-genome o)))
        (format t "~%[age ~d  energy ~,1f  sense-r ~,1f]~%" (organism-age o)
                (organism-energy o) (genome-sense-r g))
        (format t "  turn : ~s~%" (genome-turn-tree g))
        (format t "  speed: ~s~%" (genome-speed-tree g))))
    (format t "~%")))

(defun run-simulation (&key (ticks 1000) (print-every 100) (n-org 100) (n-food 180))
  (format t "=== S式ゲノム 進化シミュレーション ===~%")
  (format t "コンパイル: ~a | 有性生殖: ~a~%" *use-compiler* *sexual*)
  (let ((w (create-world n-org n-food)))
    (dotimes (i ticks)
      (world-step w :food-cap n-food)
      (when (zerop (mod (1+ i) print-every)) (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (getf w :tick))
        (return)))
    (show-brains w)
    (format t "コンパイル済み脳の種類: ~d~%" (hash-table-count *brain-cache*))
    w))

;;; ── 構造進化の測定 ───────────────────────────────────────

;;; uses-p / count-node は brain.lisp に置いてある（lineage.lisp と共用）。

(defun structure-stats (w)
  "進化が『構造』を獲得したかを測る。固定次元GAでは原理的に動かない量。"
  (let* ((orgs (world-organisms w)) (n (length orgs)))
    (when (plusp n)
      (flet ((frac (pred) (/ (count-if pred orgs) (float n))))
        (list :n n
              :turn-uses-food-angle
                (frac (lambda (o) (uses-p (genome-turn-tree (organism-genome o)) 'food-angle)))
              :speed-uses-energy
                (frac (lambda (o) (uses-p (genome-speed-tree (organism-genome o)) 'energy)))
              :has-conditional
                (frac (lambda (o) (let ((g (organism-genome o)))
                                    (or (plusp (count-node (genome-turn-tree g) 'if>))
                                        (plusp (count-node (genome-speed-tree g) 'if>))))))
              :avg-brain
                (/ (reduce #'+ (mapcar (lambda (o) (brain-complexity (organism-genome o))) orgs))
                   (float n)))))))
