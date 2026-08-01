#!/usr/bin/env sh
# 使い方:
#   ./run.sh clos          CLOS版（捕食者が進化する）をテキスト実行
#   ./run.sh gp            S式ゲノム版（草食のみ）をテキスト実行
#   ./run.sh video         CLOS版を MP4 出力
#   ./run.sh video-gp      GP版を MP4 出力
#   ./run.sh repl          CLOS版をロードして REPL に入る
set -e
cd "$(dirname "$0")"
CMD="${1:-clos}"

case "$CMD" in
  clos)
    sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp \
         --eval '(run-simulation)' --quit ;;
  gp)
    sbcl --load brain.lisp --load spatial.lisp --load evolve-gp.lisp \
         --eval '(run-simulation)' --quit ;;
  video)
    # render-run の既定値（個体120 / 400 tick）では捕食者が出現しないまま終わる。
    # run-simulation と同じ個体200 / 餌250 にし、捕食者が育つ 600 tick まで回す。
    sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp --load render.lisp \
         --eval '(render-run :ticks 600 :n-org 200 :n-food 250 :output "alife.mp4")' --quit ;;
  video-gp)
    sbcl --load brain.lisp --load spatial.lisp --load evolve-gp.lisp --load render.lisp \
         --eval '(render-run :output "alife-gp.mp4" :n-org 60 :n-food 120)' --quit ;;
  repl)
    sbcl --load brain.lisp --load spatial.lisp --load alife-clos.lisp ;;
  *)
    echo "unknown: $CMD"; echo "usage: ./run.sh [clos|gp|video|video-gp|repl]"; exit 1 ;;
esac
