#!/usr/bin/env sh
# 使い方:
#   ./run.sh predator        捕食者版（捕食者が進化する）をテキスト実行
#   ./run.sh herbivore       草食版（草食のみ）をテキスト実行
#   ./run.sh video           捕食者版を MP4 出力
#   ./run.sh video-herbivore 草食版を MP4 出力
#   ./run.sh report          系統・ゲノム・行動の HTML レポートを出力
#   ./run.sh repl            可視化まで込みでロードして REPL に入る
set -e
cd "$(dirname "$0")"
CMD="${1:-predator}"

case "$CMD" in
  predator)
    sbcl --load brain.lisp --load spatial.lisp --load alife-predator.lisp \
         --eval '(run-simulation)' --quit ;;
  herbivore)
    sbcl --load brain.lisp --load spatial.lisp --load alife-herbivore.lisp \
         --eval '(run-simulation)' --quit ;;
  video)
    # render-run の既定値（個体120 / 400 tick）では捕食者が出現しないまま終わる。
    # run-simulation と同じ個体200 / 餌250 にし、捕食者が育つ 600 tick まで回す。
    sbcl --load brain.lisp --load spatial.lisp --load alife-predator.lisp --load render.lisp \
         --eval '(render-run :ticks 600 :n-org 200 :n-food 250 :output "alife.mp4")' --quit ;;
  video-herbivore)
    sbcl --load brain.lisp --load spatial.lisp --load alife-herbivore.lisp --load render.lisp \
         --eval '(render-run :output "alife-herbivore.mp4" :n-org 60 :n-food 120)' --quit ;;
  report)
    sbcl --load brain.lisp --load spatial.lisp --load alife-predator.lisp \
         --load lineage.lisp --load viz.lisp \
         --eval '(run-report :output "lineage.html")' --quit ;;
  repl)
    sbcl --load brain.lisp --load spatial.lisp --load alife-predator.lisp \
         --load lineage.lisp --load viz.lisp ;;
  *)
    echo "unknown: $CMD"
    echo "usage: ./run.sh [predator|herbivore|video|video-herbivore|report|repl]"; exit 1 ;;
esac
