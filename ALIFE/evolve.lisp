(defun clamp (x lo hi) (max lo (min hi x)))

(defun gauss (mean sigma)
  (let* ((u1 (+ 1e-10 (random 1.0))) (u2 (random 1.0)))
    (+ mean (* sigma (sqrt (* -2.0 (log u1))) (cos (* 2.0 pi u2))))))

(defun dist (x1 y1 x2 y2)
  (sqrt (+ (expt (- x2 x1) 2) (expt (- y2 y1) 2))))

(defstruct genome speed turn-rate metabol sense-r hue)

(defun make-random-genome ()
  (make-genome :speed (+ 0.5 (random 1.5)) :turn-rate (+ 0.05 (random 0.15))
               :metabol (+ 0.08 (random 0.2)) :sense-r (+ 30.0 (random 60.0))
               :hue (random 360.0)))

(defun mutate (g rate)
  (let ((scale (* rate 0.05)))
    (make-genome
      :speed     (clamp (+ (genome-speed g)    (gauss 0 (* 0.1 scale)))  0.3 3.5)
      :turn-rate (clamp (+ (genome-turn-rate g) (gauss 0 (* 0.02 scale))) 0.02 0.4)
      :metabol   (clamp (+ (genome-metabol g)   (gauss 0 (* 0.03 scale))) 0.05 0.6)
      :sense-r   (clamp (+ (genome-sense-r g)   (gauss 0 (* 5.0 scale)))  15 130)
      :hue       (mod   (+ (genome-hue g)        (gauss 0 (* 12 scale))) 360))))

(defstruct organism genome
  (x (random 500.0)) (y (random 500.0))
  (angle (random (* 2.0 pi))) (energy 50.0) (age 0))

(defstruct food
  (x (random 500.0)) (y (random 500.0)) (value 20.0))

;;; 世界はリストで管理（defstruct を使わない）
(defun create-world (n-org n-food)
  (list :tick 0
        :width 500.0 :height 500.0
        :organisms (loop repeat n-org collect
                         (make-organism :genome (make-random-genome)))
        :foods (loop repeat n-food collect (make-food))))

(defun world-tick      (w) (getf w :tick))
(defun world-width     (w) (getf w :width))
(defun world-height    (w) (getf w :height))
(defun world-organisms (w) (getf w :organisms))
(defun world-foods     (w) (getf w :foods))
(defun (setf world-tick)      (v w) (setf (getf w :tick) v))
(defun (setf world-organisms) (v w) (setf (getf w :organisms) v))
(defun (setf world-foods)     (v w) (setf (getf w :foods) v))

(defun nearest-food (org w sense-r)
  (let ((best nil) (best-d most-positive-single-float))
    (dolist (f (world-foods w) best)
      (let ((d (dist (organism-x org) (organism-y org) (food-x f) (food-y f))))
        (when (and (< d sense-r) (< d best-d))
          (setf best f best-d d))))))

(defun steer-toward (org food turn-rate)
  (let* ((dx (- (food-x food) (organism-x org)))
         (dy (- (food-y food) (organism-y org)))
         (target (atan dy dx))
         (diff (- (mod (+ (- target (organism-angle org)) pi) (* 2 pi)) pi)))
    (incf (organism-angle org) (* turn-rate (if (> diff 0) 1 -1)))))

(defun wander (org turn-rate)
  (incf (organism-angle org) (gauss 0 turn-rate)))

(defun move-org (org speed w)
  (incf (organism-x org) (* speed (cos (organism-angle org))))
  (incf (organism-y org) (* speed (sin (organism-angle org))))
  (setf (organism-x org) (mod (organism-x org) (world-width w))
        (organism-y org) (mod (organism-y org) (world-height w))))

(defun eat-food (org w)
  (setf (world-foods w)
        (remove-if (lambda (f)
                     (when (< (dist (organism-x org) (organism-y org)
                                    (food-x f) (food-y f)) 8.0)
                       (incf (organism-energy org) (food-value f)) t))
                   (world-foods w))))

(defun try-reproduce (org w)
  (when (> (organism-energy org) 70)
    (decf (organism-energy org) 35.0)
    (push (make-organism :genome (mutate (organism-genome org) 1.0)
                         :x (+ (organism-x org) (gauss 0 5.0))
                         :y (+ (organism-y org) (gauss 0 5.0))
                         :energy 35.0)
          (world-organisms w))))

(defun behave (org w)
  (let* ((g (organism-genome org))
         (food (nearest-food org w (genome-sense-r g))))
    (if food (steer-toward org food (genome-turn-rate g))
             (wander org (genome-turn-rate g)))
    (move-org org (genome-speed g) w)
    (eat-food org w)
    (decf (organism-energy org)
          (+ (genome-metabol g)
             (* (genome-speed g) 0.018)
             (* (genome-sense-r g) 0.0008)))
    (incf (organism-age org))
    (try-reproduce org w)))

(defun world-step (w &key (food-cap 80))
  (incf (getf w :tick))
  (dolist (org (world-organisms w)) (behave org w))
  (setf (world-organisms w)
        (remove-if (lambda (o) (<= (organism-energy o) 0)) (world-organisms w)))
  (let ((n (length (world-foods w))))
    (when (< n food-cap)
      (dotimes (_ (- food-cap n))
        (push (make-food) (world-foods w))))))

(defun print-stats (w)
  (let* ((orgs (world-organisms w)) (n (length orgs)))
    (if (zerop n)
        (format t "Tick ~4d | 絶滅...~%" (getf w :tick))
        (let* ((speeds (mapcar (lambda (o) (genome-speed (organism-genome o))) orgs))
               (avg-spd (/ (reduce #'+ speeds) n))
               (avg-eng (/ (reduce #'+ (mapcar #'organism-energy orgs)) n)))
          (format t "Tick ~4d | 個体数: ~3d | 平均速度: ~5,2f | 平均エネルギー: ~6,1f~%"
                  (getf w :tick) n avg-spd avg-eng)))))

(defun run-simulation (&key (ticks 200) (print-every 10))
  (format t "=== 進化シミュレーション開始 ===~%")
  (let ((w (create-world 30 80)))
    (dotimes (i ticks)
      (world-step w)
      (when (zerop (mod (1+ i) print-every)) (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (getf w :tick))
        (return)))
    (format t "=== シミュレーション終了 ===~%")))
