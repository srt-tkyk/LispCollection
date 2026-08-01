;;;; lineage.lisp — 系統の記録と、S式の差分計算
;;;;
;;;; ログはS式のまま書き出す。PRINT で吐いて READ で戻せるので
;;;; シリアライザもパーサも要らない。ゲノムがS式であることの直接の帰結。

(defvar *lineage* (make-hash-table :test #'eql)
  "id → 記録。個体が死んでも記録は残る（祖先をたどるため）。")

(defvar *log-stream* nil)
(defvar *logging* nil)

(defstruct (rec (:type list) :named)
  id parent birth class turn speed
  aggression sense-r speed-g          ; 形態
  death age-at-death)

(defun record-of (id) (gethash id *lineage*))

(defun log-birth (child parent w)
  "出生を記録する。alife-clos.lisp の *BIRTH-HOOK* に差し込んで使う。"
  (when *logging*
    (let* ((g (organism-genome child))
           (r (make-rec :id (organism-id child)
                        :parent (and parent (organism-id parent))
                        :birth (world-tick w)
                        :class (class-name (class-of child))
                        :turn  (genome-turn-tree g)
                        :speed (genome-speed-tree g)
                        :aggression (genome-aggression g)
                        :sense-r (genome-sense-r g)
                        :speed-g (genome-speed g))))
      (setf (gethash (organism-id child) *lineage*) r)
      (when *log-stream* (print r *log-stream*)))))

;;; このファイルをロードした時点でフックが刺さる。
;;; 実際に記録が走るかどうかは *LOGGING*（START-LOGGING）が決める。
(setf *birth-hook* #'log-birth)

(defun log-founders (w)
  "初期個体も記録に入れる（親なし）。"
  (dolist (o (world-organisms w))
    (let ((g (organism-genome o)))
      (setf (gethash (organism-id o) *lineage*)
            (make-rec :id (organism-id o) :parent nil :birth 0
                      :class (class-name (class-of o))
                      :turn (genome-turn-tree g) :speed (genome-speed-tree g)
                      :aggression (genome-aggression g)
                      :sense-r (genome-sense-r g) :speed-g (genome-speed g))))))

(defun start-logging (&optional path)
  (setf *logging* t)
  (clrhash *lineage*)
  (when path
    (setf *log-stream* (open path :direction :output :if-exists :supersede))))

(defun stop-logging ()
  (setf *logging* nil)
  (when *log-stream* (close *log-stream*) (setf *log-stream* nil)))

(defun load-log (path)
  "書き出したログを読み戻す。READ 一発で構造が復元する。"
  (clrhash *lineage*)
  (with-open-file (s path)
    (loop for r = (read s nil :eof)
          until (eq r :eof)
          do (setf (gethash (rec-id r) *lineage*) r)))
  (hash-table-count *lineage*))

;;; ── 祖先チェーン ─────────────────────────────────────────

(defun ancestors-of (id)
  "ID から始祖までの記録のリスト（古い順）。"
  (let ((chain '()))
    (loop for cur = id then (rec-parent r)
          while cur
          for r = (record-of cur)
          while r
          do (push r chain))
    chain))

(defun deepest-lineage (w)
  "現存個体のうち、最も長い祖先チェーンを持つものの系統を返す。"
  (let ((best nil) (best-len 0))
    (dolist (o (world-organisms w) best)
      (let* ((chain (ancestors-of (organism-id o))) (n (length chain)))
        (when (> n best-len) (setf best chain best-len n))))))

(defun lineage-of-oldest (w)
  (let ((o (first (sort (copy-list (world-organisms w)) #'> :key #'organism-age))))
    (and o (ancestors-of (organism-id o)))))

;;; ── 木の差分 ─────────────────────────────────────────────

(defun mark-all (tree flag)
  (if (consp tree)
      (cons flag (mapcar (lambda (x) (mark-all x flag)) (cdr tree)))
      flag))

(defun tree-diff (old new)
  "NEW の各ノードが OLD と一致するかを表す並行構造を返す。
   t = 一致、:changed = この部分木が変わった。"
  (cond ((equal old new) (mark-all new t))
        ((or (atom old) (atom new)) (mark-all new :changed))
        ((not (eq (car old) (car new))) (mark-all new :changed))
        ((/= (length old) (length new)) (mark-all new :changed))
        (t (cons t (mapcar #'tree-diff (cdr old) (cdr new))))))

(defun changed-node-count (diff)
  (if (consp diff)
      (+ (if (eq (car diff) :changed) 1 0)
         (reduce #'+ (mapcar #'changed-node-count (cdr diff))))
      (if (eq diff :changed) 1 0)))

;;; ── 系統上で「実際に変化があった世代」だけ抜き出す ───────

(defun mutation-points (chain &key (key #'rec-turn))
  "CHAIN のうち、親と木が違う世代だけを (前 後 差分) で返す。
   無変異世代を捨てるので、可視化すべきコマ数が激減する。"
  (let ((out '()) (prev nil))
    (dolist (r chain (nreverse out))
      (let ((tr (funcall key r)))
        (when (and prev (not (equal (funcall key prev) tr)))
          (push (list prev r (tree-diff (funcall key prev) tr)) out))
        (setf prev r)))))

(defun richest-lineage (w &key (key #'rec-turn))
  "現存個体のうち、祖先チェーン上で木が最も多く変化したものを選ぶ。
   最長寿個体は初期個体（祖先なし）になりがちなので、可視化にはこちらが適する。
   MUTATION-POINTS を呼ぶので、その定義より後ろに置いてある。"
  (let ((best nil) (best-n -1))
    (dolist (o (world-organisms w) best)
      (let* ((chain (ancestors-of (organism-id o)))
             (n (length (mutation-points chain :key key))))
        (when (> n best-n) (setf best chain best-n n))))))

;;; ── 行動の応答面 ─────────────────────────────────────────

(defun response-surface (tree &key (nx 48) (ny 48) (energy 0.5) (age 0.2))
  "food-angle × food-dist の格子で脳を評価し、出力の2次元配列を返す。
   遺伝子型ではなく表現型を直接見るための関数。"
  (let ((arr (make-array (list ny nx) :element-type 'single-float))
        (fn (brain-fn tree)))
    (dotimes (j ny arr)
      (dotimes (i nx)
        (let ((fa (float (- (* (/ i (float (1- nx))) +2pi1+) +pi1+) 1.0))
              (fd (float (/ j (float (1- ny))) 1.0)))
          (setf (aref arr j i)
                (funcall fn fa fd (float energy 1.0) (float age 1.0))))))))

(defun surface-distance (a b)
  "2つの応答面のRMS差。S式が違っても行動が同じ（中立変異）かを判定できる。"
  (let ((n (array-total-size a)) (acc 0.0))
    (dotimes (i n (sqrt (/ acc n)))
      (incf acc (expt (- (row-major-aref a i) (row-major-aref b i)) 2)))))

;;; ── 集団統計の時系列 ─────────────────────────────────────

(defvar *timeline* '())

(defun snapshot (w)
  (let* ((orgs (world-organisms w)) (n (length orgs)))
    (when (plusp n)
      (flet ((frac (pred) (/ (count-if pred orgs) (float n))))
        (push (list :tick (world-tick w)
                    :herb (count-class w 'herbivore)
                    :pred (count-class w 'predator)
                    :brain (/ (reduce #'+ (mapcar (lambda (o) (brain-complexity (organism-genome o))) orgs))
                              (float n))
                    :uses-angle
                      (frac (lambda (o) (uses-p (genome-turn-tree (organism-genome o)) 'food-angle)))
                    :uses-energy
                      (frac (lambda (o) (uses-p (genome-speed-tree (organism-genome o)) 'energy)))
                    :has-cond
                      (frac (lambda (o) (let ((g (organism-genome o)))
                                          (or (plusp (count-node (genome-turn-tree g) 'if>))
                                              (plusp (count-node (genome-speed-tree g) 'if>)))))))
              *timeline*)))))

;;; USES-P / COUNT-NODE は brain.lisp に置いてある（evolve-gp.lisp と共用）。
