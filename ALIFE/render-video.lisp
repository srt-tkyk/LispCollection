;;;; render-video.lisp — evolve.lisp のシミュレーションをPPMフレームで出力し
;;;;                      ffmpeg で MP4 動画に変換する
;;;;
;;;; 使い方:
;;;;   sbcl --load evolve.lisp --load render-video.lisp --eval '(render-run)' --quit

(defparameter *frame-width* 500)
(defparameter *frame-height* 500)
(defparameter *frame-dir* "/tmp/evolve-frames/")

;;; ── HSV → RGB 変換 ──────────────────────────────────────
(defun hsv->rgb (h s v)
  "H: 0-360, S: 0-1, V: 0-1 → (values r g b) each 0-255"
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

;;; ── PPM フレーム書き出し ─────────────────────────────────
(defun make-frame ()
  "W x H x 3 の 0 初期化バッファ"
  (make-array (list *frame-height* *frame-width* 3)
              :element-type '(unsigned-byte 8) :initial-element 0))

(defun set-pixel (buf x y r g b)
  (let ((ix (floor x)) (iy (floor y)))
    (when (and (<= 0 ix (1- *frame-width*)) (<= 0 iy (1- *frame-height*)))
      (setf (aref buf iy ix 0) r
            (aref buf iy ix 1) g
            (aref buf iy ix 2) b))))

(defun draw-filled-circle (buf cx cy radius r g b)
  (let ((r2 (* radius radius)))
    (loop for dy from (- (ceiling radius)) to (ceiling radius) do
      (loop for dx from (- (ceiling radius)) to (ceiling radius) do
        (when (<= (+ (* dx dx) (* dy dy)) r2)
          (set-pixel buf (+ cx dx) (+ cy dy) r g b))))))

(defun draw-ring (buf cx cy radius r g b)
  "簡易リング（感知範囲の可視化用）"
  (let ((steps (max 36 (round (* 2 pi radius)))))
    (dotimes (i steps)
      (let ((a (* 2 pi (/ i steps))))
        (set-pixel buf (+ cx (* radius (cos a)))
                       (+ cy (* radius (sin a)))
                   r g b)))))

(defun write-ppm (buf path)
  (with-open-file (s path :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    ;; ヘッダ (ASCII部分をバイト列で書く)
    (let ((header (format nil "P6~%~d ~d~%255~%" *frame-width* *frame-height*)))
      (loop for ch across header do (write-byte (char-code ch) s)))
    ;; ピクセルデータ
    (dotimes (y *frame-height*)
      (dotimes (x *frame-width*)
        (write-byte (aref buf y x 0) s)
        (write-byte (aref buf y x 1) s)
        (write-byte (aref buf y x 2) s)))))

;;; ── 1フレーム描画 ────────────────────────────────────────
(defun render-frame (w frame-index)
  (let ((buf (make-frame)))
    ;; 背景グリッド（薄いライン）
    (loop for gx from 0 below *frame-width* by 50 do
      (dotimes (y *frame-height*)
        (set-pixel buf gx y 20 20 20)))
    (loop for gy from 0 below *frame-height* by 50 do
      (dotimes (x *frame-width*)
        (set-pixel buf x gy 20 20 20)))

    ;; 食料 — 緑の小さな点
    (dolist (f (world-foods w))
      (draw-filled-circle buf (food-x f) (food-y f) 2 40 200 40))

    ;; 生物 — hue で着色した円 + 進行方向の線
    (dolist (org (world-organisms w))
      (let* ((g (organism-genome org))
             (energy-ratio (min 1.0 (/ (organism-energy org) 80.0)))
             (radius (+ 3 (* energy-ratio 3))))
        (multiple-value-bind (r gc b)
            (hsv->rgb (genome-hue g) 0.85 (+ 0.4 (* 0.6 energy-ratio)))
          ;; 感知範囲（薄く）
          (draw-ring buf (organism-x org) (organism-y org)
                     (genome-sense-r g)
                     (round (* r 0.25)) (round (* gc 0.25)) (round (* b 0.25)))
          ;; 本体
          (draw-filled-circle buf (organism-x org) (organism-y org) radius r gc b)
          ;; 方向インジケータ
          (let ((len (+ radius 4)))
            (set-pixel buf (+ (organism-x org) (* len (cos (organism-angle org))))
                           (+ (organism-y org) (* len (sin (organism-angle org))))
                       255 255 255)))))

    ;; 情報テキストは動画に焼き込まないが、統計はターミナルに出す
    (write-ppm buf (format nil "~aframe-~5,'0d.ppm" *frame-dir* frame-index))))

;;; ── メインエントリ ───────────────────────────────────────
(defun render-run (&key (ticks 300) (output "evolve.mp4") (n-org 30) (n-food 40))
  (ensure-directories-exist *frame-dir*)
  ;; 古いフレームを削除
  (let ((old (directory (merge-pathnames "*.ppm" *frame-dir*))))
    (dolist (f old) (delete-file f)))

  (format t "=== 進化シミュレーション 動画出力 ===~%")
  (format t "フレーム数: ~d | 個体数: ~d | 食料: ~d | 出力先: ~a~%" ticks n-org n-food output)
  (let ((w (create-world n-org n-food)))
    ;; 初期フレーム
    (render-frame w 0)
    (dotimes (i ticks)
      (world-step w :food-cap n-food)
      (render-frame w (1+ i))
      (when (zerop (mod (1+ i) 20))
        (print-stats w))
      (when (null (world-organisms w))
        (format t "全個体が絶滅 (tick ~d)~%" (getf w :tick))
        (return)))
    (format t "フレーム出力完了。ffmpeg で動画に変換中...~%")

    ;; ffmpeg で MP4 に変換
    (let ((cmd (format nil
                 "ffmpeg -y -framerate 30 -i ~aframe-%05d.ppm -c:v libx264 -pix_fmt yuv420p -vf \"pad=ceil(iw/2)*2:ceil(ih/2)*2\" ~a"
                 *frame-dir* output)))
      (format t "$ ~a~%" cmd)
      (let ((ret (nth-value 2 (uiop:run-program cmd :output t :error-output t
                                                     :ignore-error-status t))))
        (if (zerop ret)
            (format t "~%動画出力完了: ~a~%" output)
            (format t "~%ffmpeg エラー (exit ~d)。ffmpeg がインストールされているか確認してください。~%" ret))))

    ;; フレーム掃除
    (let ((frames (directory (merge-pathnames "*.ppm" *frame-dir*))))
      (dolist (f frames) (delete-file f)))
    (format t "一時フレーム削除完了。~%")))
