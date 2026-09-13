#!/bin/bash
# Fake CLI shim for ProcessRunner tests — never touches the real container/opossum binaries.
set -u
mode="${1:-}"
case "$mode" in
  echo-args)
    shift
    echo "ARGS:$*"
    exit 0
    ;;
  interleave)
    # Emit on both streams so a test can prove neither is starved by the other.
    for i in 1 2 3; do
      echo "out-$i"
      echo "err-$i" 1>&2
    done
    exit 0
    ;;
  progress)
    # Carriage-return progress lines collapsing to one, then a final newline-terminated line.
    printf 'progress 10%%\rprogress 50%%\rprogress 100%%\n'
    echo "done"
    exit 0
    ;;
  fail)
    echo "about to fail" 1>&2
    exit 7
    ;;
  sleep-then-exit)
    sleep "${2:-5}"
    echo "woke up"
    exit 0
    ;;
  *)
    echo "unknown mode: $mode" 1>&2
    exit 64
    ;;
esac
