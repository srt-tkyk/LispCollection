;;;; render.lisp — PPM フレーム出力 + ffmpeg で MP4 化
;;;;
;;;; 旧版 render-video.lisp（git 履歴に残る）からの変更:
;;;;   - uiop を使わず sb-ext:run-program を直接叩く（(require :asdf) が不要）
;;;;   - PPM をバイト単位でなく write-sequence で一括書き出し（大幅に高速）
;;;;   - 捕食者を白いリングで縁取って描き分ける（CLOS 版のときのみ）
;;;;
;;;; evolve-gp.lisp / alife-clos.lisp のどちらとも組み合わせて使える。

(defparameter *frame-width*  500)
(defparameter *frame-height* 500)
(defparameter *frame-dir*    #p"/tmp/alife-frames/")

;;; ── HSV → RGB ────────────────────────────────────────────

(defun hsv->rgb (h s v)
  (let* ((c (* v s))
         (x (* c (- 1.0 (abs (- (mod (/ h 60.0) 2) 1.0)))))
         (m (- v c)))
    (multiple-value-bind (r1 g1 b1)
        (cond ((< h  60) (values c x 0.0))
              ((< h 120) (values x c 0.0))
              ((< h 180) (values 0.0 c x))
              ((< h 240) (values 0.0 x c))
              ((< h 300) (values x 0.0 c))
              (t         (values c 0.0 x)))
      (values (round (* (+ r1 m) 255))
              (round (* (+ g1 m) 255))
              (round (* (+ b1 m) 255))))))

;;; ── フレームバッファ ─────────────────────────────────────
;;; 1次元の (unsigned-byte 8) 配列にしておくと write-sequence が一発で使える。

(defun make-frame ()
  (make-array (* *frame-width* *frame-height* 3)
              :element-type '(unsigned-byte 8) :initial-element 0))

(declaim (inline set-pixel))
(defun set-pixel (buf x y r g b)
  (let ((ix (floor x)) (iy (floor y)))
    (when (and (<= 0 ix (1- *frame-width*)) (<= 0 iy (1- *frame-height*)))
      (let ((i (* 3 (+ (* iy *frame-width*) ix))))
        (setf (aref buf i) r (aref buf (+ i 1)) g (aref buf (+ i 2)) b)))))

(defun draw-disc (buf cx cy radius r g b)
  (let ((r2 (* radius radius)) (n (ceiling radius)))
    (loop for dy from (- n) to n do
      (loop for dx from (- n) to n do
        (when (<= (+ (* dx dx) (* dy dy)) r2)
          (set-pixel buf (+ cx dx) (+ cy dy) r g b))))))

(defun draw-ring (buf cx cy radius r g b)
  (let ((steps (max 36 (round (* 2 pi radius)))))
    (dotimes (i steps)
      (let ((a (* 2 pi (/ i steps))))
        (set-pixel buf (+ cx (* radius (cos a))) (+ cy (* radius (sin a))) r g b)))))

(defun draw-line (buf x0 y0 x1 y1 r g b)
  (let* ((dx (- x1 x0)) (dy (- y1 y0))
         (n (max 1 (ceiling (max (abs dx) (abs dy))))))
    (dotimes (i (1+ n))
      (let ((tt (/ i (float n))))
        (set-pixel buf (+ x0 (* tt dx)) (+ y0 (* tt dy)) r g b)))))

(defun write-ppm (buf path)
  (with-open-file (s path :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    (let ((header (format nil "P6~%~d ~d~%255~%" *frame-width* *frame-height*)))
      (loop for ch across header do (write-byte (char-code ch) s)))
    (write-sequence buf s)))

;;; ── 1フレーム ────────────────────────────────────────────

(defun predator-p* (o)
  "CLOS 版でだけ predator クラスが存在する。GP 版では常に nil。"
  (let ((c (find-class 'predator nil)))
    (and c (typep o c))))

(defun render-frame (w index)
  (let ((buf (make-frame)))
    ;; 背景グリッド
    (loop for gx from 0 below *frame-width* by 50 do
      (dotimes (y *frame-height*) (set-pixel buf gx y 20 20 20)))
    (loop for gy from 0 below *frame-height* by 50 do
      (dotimes (x *frame-width*) (set-pixel buf x gy 20 20 20)))

    ;; 食料
    (dolist (f (world-foods w))
      (draw-disc buf (food-x f) (food-y f) 2 40 200 40))

    ;; 個体
    (dolist (org (world-organisms w))
      (let* ((g (organism-genome org))
             (er (min 1.0 (/ (organism-energy org) 80.0)))
             (rad (+ 3 (* er 3)))
             (pred (predator-p* org)))
        (multiple-value-bind (r gc b) (hsv->rgb (genome-hue g) 0.85 (+ 0.4 (* 0.6 er)))
          ;; 感知範囲
          (draw-ring buf (organism-x org) (organism-y org) (genome-sense-r g)
                     (round (* r 0.25)) (round (* gc 0.25)) (round (* b 0.25)))
          ;; 本体（捕食者は一回り大きく + 白縁）
          (when pred
            (draw-ring buf (organism-x org) (organism-y org) (+ rad 2) 255 255 255))
          (draw-disc buf (organism-x org) (organism-y org) rad r gc b)
          ;; 進行方向
          (let ((len (+ rad 5)) (a (organism-angle org)))
            (draw-line buf (organism-x org) (organism-y org)
                       (+ (organism-x org) (* len (cos a)))
                       (+ (organism-y org) (* len (sin a)))
                       255 255 255)))))
    (write-ppm buf (merge-pathnames (format nil "frame-~5,'0d.ppm" index) *frame-dir*))))

;;; ── メイン ───────────────────────────────────────────────

(defun clear-frames ()
  (dolist (f (directory (merge-pathnames "*.ppm" *frame-dir*))) (delete-file f)))

(defun run-ffmpeg (output fps)
  (let ((args (list "-y" "-framerate" (princ-to-string fps)
                    "-i" (namestring (merge-pathnames "frame-%05d.ppm" *frame-dir*))
                    "-c:v" "libx264" "-pix_fmt" "yuv420p"
                    "-vf" "pad=ceil(iw/2)*2:ceil(ih/2)*2"
                    output)))
    (format t "$ ffmpeg ~{~a ~}~%" args)
    (handler-case
        (let ((p (sb-ext:run-program "ffmpeg" args :search t
                                     :output *standard-output* :error *standard-output*)))
          (if (zerop (sb-ext:process-exit-code p))
              (format t "~%動画出力完了: ~a~%" output)
              (format t "~%ffmpeg がエラー終了しました。~%")))
      (error (e)
        (format t "~%ffmpeg を実行できません: ~a~%PPM は ~a に残してあります。~%"
                e *frame-dir*)
        :no-ffmpeg))))

(defun render-run (&key (ticks 400) (output "alife.mp4")
                        (n-org 120) (n-food 200) (fps 30) (keep-frames nil))
  (ensure-directories-exist *frame-dir*)
  (clear-frames)
  (format t "=== 動画出力 ===~%フレーム ~d | 個体 ~d | 餌 ~d | 出力 ~a~%"
          ticks n-org n-food output)
  (let ((w (create-world n-org n-food)))
    (render-frame w 0)
    (dotimes (i ticks)
      (world-step w :food-cap n-food)
      (render-frame w (1+ i))
      (when (zerop (mod (1+ i) 50)) (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (world-tick w))
        (return)))
    (format t "フレーム書き出し完了。ffmpeg で変換します...~%")
    (let ((res (run-ffmpeg output fps)))
      (unless (or keep-frames (eq res :no-ffmpeg)) (clear-frames)))
    w))
