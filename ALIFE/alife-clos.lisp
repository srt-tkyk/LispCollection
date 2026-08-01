;;;; alife-clos.lisp — CLOS 版 進化シミュレーション
;;;;
;;;;   sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp \
;;;;        --eval '(run-simulation)' --quit
;;;;
;;;; 前版からの変更:
;;;;   1. 個体を CLOS クラスにし、種間の相互作用を多重ディスパッチで書く
;;;;   2. change-class により、同一性を保ったまま個体が種を変える
;;;;   3. 知覚対象を総称関数にしたので、同じ脳が体ごとに別の意味を持つ
;;;;   4. 空間ハッシュで近傍探索を O(N) に

(defun clamp (x lo hi) (max lo (min hi x)))

(defun gauss (mean sigma)
  (let ((u1 (+ 1e-10 (random 1.0))) (u2 (random 1.0)))
    (+ mean (* sigma (sqrt (* -2.0 (log u1))) (cos (* +2pi1+ u2))))))

;;; ── ゲノム ───────────────────────────────────────────────

(defstruct genome
  speed turn-rate metabol sense-r hue
  aggression      ; 0..1。閾値を超えると捕食者に転じる
  turn-tree speed-tree)

(defun make-random-genome ()
  (make-genome :speed      (+ 0.5 (random 1.5))
               :turn-rate  (+ 0.05 (random 0.15))
               :metabol    (+ 0.08 (random 0.15))
               :sense-r    (+ 30.0 (random 60.0))
               :hue        (+ 60.0 (random 120.0))   ; 初期は緑〜黄
               :aggression (random 0.3)              ; 最初は全員おとなしい
               :turn-tree  (random-tree)
               :speed-tree (random-tree)))

(defun brain-complexity (g)
  (+ (tree-size (genome-turn-tree g)) (tree-size (genome-speed-tree g))))

(defun mutate (g rate)
  (let ((scale (* rate 0.05)))
    (make-genome
      :speed      (clamp (+ (genome-speed g)      (gauss 0 (* 0.1 scale)))  0.3 3.5)
      :turn-rate  (clamp (+ (genome-turn-rate g)  (gauss 0 (* 0.02 scale))) 0.02 0.4)
      :metabol    (clamp (+ (genome-metabol g)    (gauss 0 (* 0.03 scale))) 0.05 0.6)
      :sense-r    (clamp (+ (genome-sense-r g)    (gauss 0 (* 5.0 scale)))  15.0 130.0)
      :hue        (mod   (+ (genome-hue g)        (gauss 0 (* 12 scale)))   360)
      :aggression (clamp (+ (genome-aggression g) (gauss 0 (* 3.0 scale)))  0.0 1.0)
      :turn-tree  (mutate-tree (genome-turn-tree g))
      :speed-tree (mutate-tree (genome-speed-tree g)))))

;;; ── クラス階層 ───────────────────────────────────────────

(defclass organism ()
  ((genome :initarg :genome :accessor organism-genome)
   (x      :initarg :x      :accessor organism-x)
   (y      :initarg :y      :accessor organism-y)
   (angle  :initarg :angle  :accessor organism-angle)
   (energy :initarg :energy :accessor organism-energy :initform 50.0)
   (age    :initform 0      :accessor organism-age)))

(defclass herbivore (organism) ())
(defclass predator  (organism) ())

(defstruct food (x 0.0) (y 0.0) (value 20.0))

(defun make-organism (&key genome x y angle (energy 50.0) (class 'herbivore))
  (make-instance class :genome genome
                       :x (or x (random 500.0)) :y (or y (random 500.0))
                       :angle (or angle (random +2pi1+))
                       :energy energy))

;;; ── 種分化: change-class ─────────────────────────────────
;;; 個体の同一性 (EQ) を保ったままクラスだけが変わる。
;;; オブジェクトを作り直さないので、世界のリストや進行中の参照が壊れない。

(defparameter *predator-threshold* 0.55)
(defparameter *capture-rate* 0.35 "捕食の成功率。INTERACT が参照するので定義はその前に置く。")
(defvar *speciation-log* '())

(defmethod update-instance-for-different-class :after
    ((old herbivore) (new predator) &key)
  "草食獣が捕食者に転じたときの後処理。CLOS の標準プロトコルに乗せる。"
  (setf (genome-hue (organism-genome new)) 0.0)      ; 赤くなる
  (push (cons (organism-age new) :to-predator) *speciation-log*))

(defmethod update-instance-for-different-class :after
    ((old predator) (new herbivore) &key)
  (setf (genome-hue (organism-genome new)) 120.0)    ; 緑に戻る
  (push (cons (organism-age new) :to-herbivore) *speciation-log*))

(defun maybe-speciate (org)
  (let ((a (genome-aggression (organism-genome org))))
    (cond ((and (typep org 'herbivore) (> a *predator-threshold*))
           (change-class org 'predator))
          ((and (typep org 'predator) (< a (- *predator-threshold* 0.15)))
           (change-class org 'herbivore)))))

;;; ── 世界 ─────────────────────────────────────────────────

(defun create-world (n-org n-food)
  (list :tick 0 :width 500.0 :height 500.0
        :organisms (loop repeat n-org collect
                         (make-organism :genome (make-random-genome)))
        :foods (loop repeat n-food collect
                     (make-food :x (random 500.0) :y (random 500.0)))
        :index (make-sindex 500.0 500.0 50.0)))

(defun world-tick      (w) (getf w :tick))
(defun world-width     (w) (getf w :width))
(defun world-height    (w) (getf w :height))
(defun world-organisms (w) (getf w :organisms))
(defun world-foods     (w) (getf w :foods))
(defun world-index     (w) (getf w :index))
(defun (setf world-organisms) (v w) (setf (getf w :organisms) v))
(defun (setf world-foods)     (v w) (setf (getf w :foods) v))

(defun rebuild-index (w)
  (let ((idx (world-index w)))
    (sindex-clear idx)
    (dolist (f (world-foods w))     (sindex-insert idx f (food-x f) (food-y f)))
    (dolist (o (world-organisms w)) (sindex-insert idx o (organism-x o) (organism-y o)))
    idx))

;;; ── 知覚: 総称関数 ───────────────────────────────────────
;;; ここが要点。脳のS式は同じでも、TARGET-OF がクラスごとに違う対象を返すので
;;; food-angle / food-dist の指す先が体によって変わる。

(defgeneric edible-p (eater thing)
  (:documentation "EATER が THING を食べられるか。"))

(defmethod edible-p ((e organism)  thing)          nil)
(defmethod edible-p ((e herbivore) (thing food))   t)
(defmethod edible-p ((e predator)  (thing herbivore)) t)
(defmethod edible-p ((e predator)  (thing predator))  nil)

(defun thing-x (o) (if (food-p o) (food-x o) (organism-x o)))
(defun thing-y (o) (if (food-p o) (food-y o) (organism-y o)))

(defun target-of (org w)
  "感知範囲内で自分が食べられるもののうち最寄りを返す。"
  (let* ((g (organism-genome org))
         (r (genome-sense-r g))
         (ww (world-width w)) (hh (world-height w))
         (best nil) (best-d r))
    (dolist (c (sindex-nearby (world-index w) (organism-x org) (organism-y org) r) best)
      (when (and (not (eq c org)) (edible-p org c))
        (let ((d (torus-dist (organism-x org) (organism-y org)
                             (thing-x c) (thing-y c) ww hh)))
          (when (< d best-d) (setf best c best-d d)))))))

(defun relative-angle (org target w)
  (let* ((dx (torus-delta (organism-x org) (thing-x target) (world-width w)))
         (dy (torus-delta (organism-y org) (thing-y target) (world-height w)))
         (d  (- (atan dy dx) (organism-angle org))))
    (float (- (mod (+ d +pi1+) +2pi1+) +pi1+) 1.0)))

;;; ── 摂食: 多重ディスパッチ ───────────────────────────────
;;; 新しい種を足すときは INTERACT のメソッドを増やすだけでよく、
;;; 既存のコードに触れる必要がない。

(defgeneric interact (a b w)
  (:documentation "A が B に対して行う相互作用。"))

(defmethod interact ((a organism) b w) nil)

(defmethod interact ((a herbivore) (b food) w)
  (incf (organism-energy a) (food-value b))
  (setf (world-foods w) (delete b (world-foods w) :count 1)))

(defmethod interact ((a predator) (b herbivore) w)
  "捕食。捕獲は確率的で、失敗すると空振りのコストだけ払う。"
  (if (< (random 1.0) *capture-rate*)
      (progn (incf (organism-energy a) (+ 10.0 (* 0.35 (organism-energy b))))
             (setf (organism-energy b) -1.0))
      (decf (organism-energy a) 1.0)))

;;; 捕獲難度も種ごとの性質なので総称関数にする
(defgeneric eat-radius (org))
(defmethod eat-radius ((o organism)) 8.0)
(defmethod eat-radius ((o predator))  5.0)   ; 動く獲物は捕まえにくい

(defun try-eat (org w)
  (let ((r (eat-radius org)) (ww (world-width w)) (hh (world-height w)))
    (dolist (c (sindex-nearby (world-index w) (organism-x org) (organism-y org) r))
      (when (and (not (eq c org)) (edible-p org c)
                 (< (torus-dist (organism-x org) (organism-y org)
                                (thing-x c) (thing-y c) ww hh) r))
        (interact org c w)
        (return)))))

;;; ── 行動 ─────────────────────────────────────────────────

(defun move-org (org speed w)
  (incf (organism-x org) (* speed (cos (organism-angle org))))
  (incf (organism-y org) (* speed (sin (organism-angle org))))
  (setf (organism-x org) (mod (organism-x org) (world-width w))
        (organism-y org) (mod (organism-y org) (world-height w))))

(defgeneric metabolic-cost (org v)
  (:documentation "1 tick あたりのエネルギー消費。種ごとに違ってよい。"))

(defmethod metabolic-cost ((org organism) v)
  (let ((g (organism-genome org)))
    (+ (genome-metabol g) (* v 0.018)
       (* (genome-sense-r g) 0.0008)
       (* 0.004 (brain-complexity g)))))

(defmethod metabolic-cost ((org predator) v)
  "捕食者は維持費が高い。"
  (* 2.0 (call-next-method)))

(defgeneric reproduce-threshold (org))
(defmethod reproduce-threshold ((o herbivore)) 75.0)
(defmethod reproduce-threshold ((o predator))  140.0)

(defun try-reproduce (org w)
  (when (> (organism-energy org) (reproduce-threshold org))
    (decf (organism-energy org) (* 0.5 (reproduce-threshold org)))
    (let ((child (make-organism :genome (mutate (organism-genome org) 1.0)
                                :x (+ (organism-x org) (gauss 0 5.0))
                                :y (+ (organism-y org) (gauss 0 5.0))
                                :energy (* 0.45 (reproduce-threshold org))
                                :class (class-name (class-of org)))))
      (maybe-speciate child)
      (push child (world-organisms w)))))

(defun behave (org w)
  (let* ((g (organism-genome org))
         (target (target-of org w))
         (fa (if target (relative-angle org target w) 0.0))
         (fd (if target (float (/ (torus-dist (organism-x org) (organism-y org)
                                              (thing-x target) (thing-y target)
                                              (world-width w) (world-height w))
                                  (genome-sense-r g)) 1.0)
                 1.0))
         (en (clamp (/ (organism-energy org) 100.0) 0.0 1.0))
         (ag (clamp (/ (organism-age org) 200.0) 0.0 1.0))
         (turn (run-brain (genome-turn-tree g)  fa fd en ag))
         (spd  (run-brain (genome-speed-tree g) fa fd en ag))
         (v (clamp spd 0.0 (genome-speed g))))
    (incf (organism-angle org)
          (clamp turn (- (genome-turn-rate g)) (genome-turn-rate g)))
    (move-org org v w)
    (try-eat org w)
    (decf (organism-energy org) (metabolic-cost org v))
    (incf (organism-age org))
    (maybe-speciate org)
    (try-reproduce org w)))

(defun world-step (w &key (food-cap 150) (pop-cap 600))
  (incf (getf w :tick))
  (rebuild-index w)
  (dolist (org (world-organisms w)) (behave org w))
  (setf (world-organisms w)
        (remove-if (lambda (o) (<= (organism-energy o) 0)) (world-organisms w)))
  (let ((orgs (world-organisms w)))
    (when (> (length orgs) pop-cap)
      (setf (world-organisms w) (subseq orgs 0 pop-cap))))
  (let ((n (length (world-foods w))))
    (when (< n food-cap)
      (dotimes (_ (- food-cap n))
        (push (make-food :x (random 500.0) :y (random 500.0)) (world-foods w))))))

;;; ── 観測 ─────────────────────────────────────────────────

(defun count-class (w class) (count-if (lambda (o) (typep o class)) (world-organisms w)))

(defun print-stats (w)
  (let* ((orgs (world-organisms w)) (n (length orgs)))
    (if (zerop n)
        (format t "Tick ~4d | 絶滅...~%" (getf w :tick))
        (format t "Tick ~4d | 草食 ~4d | 捕食 ~3d | 平均E ~5,1f | 脳 ~4,1f | 攻撃性 ~4,2f~%"
                (getf w :tick)
                (count-class w 'herbivore) (count-class w 'predator)
                (/ (reduce #'+ (mapcar #'organism-energy orgs)) n)
                (/ (reduce #'+ (mapcar (lambda (o) (brain-complexity (organism-genome o))) orgs))
                   (float n))
                (/ (reduce #'+ (mapcar (lambda (o) (genome-aggression (organism-genome o))) orgs))
                   (float n))))))

(defun show-brains (w &optional (n 4))
  (let ((top (subseq (sort (copy-list (world-organisms w)) #'> :key #'organism-age)
                     0 (min n (length (world-organisms w))))))
    (format t "~%── 長寿個体の脳 ──────────────────────────~%")
    (dolist (o top)
      (let ((g (organism-genome o)))
        (format t "~%[~a age ~d E ~,1f agg ~,2f]~%"
                (class-name (class-of o)) (organism-age o) (organism-energy o)
                (genome-aggression g))
        (format t "  turn : ~s~%  speed: ~s~%"
                (genome-turn-tree g) (genome-speed-tree g))))
    (format t "~%")))

(defun run-simulation (&key (ticks 2000) (print-every 100) (n-org 200) (n-food 250))
  (format t "=== CLOS + S式ゲノム 進化シミュレーション ===~%")
  (setf *speciation-log* '())
  (let ((w (create-world n-org n-food)))
    (dotimes (i ticks)
      (world-step w :food-cap n-food)
      (when (zerop (mod (1+ i) print-every)) (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (getf w :tick)) (return)))
    (show-brains w)
    (format t "種転換イベント: ~d 回 (→捕食 ~d / →草食 ~d)~%"
            (length *speciation-log*)
            (count :to-predator  *speciation-log* :key #'cdr)
            (count :to-herbivore *speciation-log* :key #'cdr))
    (format t "コンパイル済み脳: ~d 種類~%" (hash-table-count *brain-cache*))
    w))
