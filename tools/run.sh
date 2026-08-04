#!/usr/bin/env bash
# Compile and run a bench suite against one or more standalone BYOND builds.
# The Linux counterpart of run.ps1, with the same refusals.
#
# Builds live in byond-standalones/<label>/, either as <label>/bin/ or as
# <label>/byond/bin/ depending on how the release was extracted. Nothing is
# installed and the system BYOND is never used, so the build under test is
# always explicit.
#
# Usage:
#   tools/run.sh --list
#   tools/run.sh --suite suite --version 516.1666
#   tools/run.sh --suite suite_del --version all --port 47950
#   tools/run.sh --suite suite --version 516.1666 --priority high
#
# Standalones are looked for in, first hit wins:
#   $DMBENCH_BYOND, <repo>/byond-standalones, ~/byond-standalones

set -u

SUITE=suite
VERSION=all
PORT=47899
PRIORITY=normal
TIMEOUT=900
STDOUT_BINDING=file
LIST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --list)     LIST=1 ;;
        --suite)    SUITE="$2"; shift ;;
        --version)  VERSION="$2"; shift ;;
        --port)     PORT="$2"; shift ;;
        --priority) PRIORITY="$2"; shift ;;
        --timeout)  TIMEOUT="$2"; shift ;;
        --stdout)   STDOUT_BINDING="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RESULTS="$ROOT/results"

# Which source produced this result. Twelve Linux runs were discarded on
# 2026-08-02 for having been built from a checkout two commits behind, and
# nothing in the output said so: all twelve read 52 assertions and 0 failed.
# A green summary cannot see a stale checkout, so the runner records the
# commit and merge-runs.ps1 refuses to blend two of them, the way it already
# refuses to blend builds and priorities. A dirty tree is stamped as such,
# because "which commit" stops being an answer the moment the tree is edited.
SOURCE_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
if [ "$SOURCE_COMMIT" != "unknown" ] && [ -n "$(git -C "$ROOT" status --porcelain -- suite tools 2>/dev/null)" ]; then
    SOURCE_COMMIT="$SOURCE_COMMIT+dirty"
fi

if [ -n "${DMBENCH_BYOND:-}" ] && [ -d "$DMBENCH_BYOND" ]; then
    STANDALONE="$DMBENCH_BYOND"
elif [ -d "$ROOT/byond-standalones" ]; then
    STANDALONE="$ROOT/byond-standalones"
elif [ -d "$HOME/byond-standalones" ]; then
    STANDALONE="$HOME/byond-standalones"
else
    echo "no byond-standalones directory found; set DMBENCH_BYOND" >&2
    exit 1
fi

# A release extracts either as <label>/bin or as <label>/byond/bin. Find the
# one that actually holds the binaries rather than assuming a depth.
bindir_for() {
    for cand in "$1/bin" "$1/byond/bin"; do
        [ -x "$cand/DreamMaker" ] && [ -x "$cand/DreamDaemon" ] && { echo "$cand"; return 0; }
    done
    return 1
}

# The folder name is a hint, not truth. Linux binaries carry no version
# metadata, but DreamMaker prints its version when run with no arguments, so
# the check that run.ps1 makes against the file's VersionInfo is made here
# against that banner. A folder called 516.1685 holding 1666 binaries would
# otherwise produce a baseline attributed to the wrong engine.
reported_version() {
    LD_LIBRARY_PATH="$1" "$1/DreamMaker" 2>&1 | sed -n 's/^DM compiler version \([0-9.]*\).*/\1/p' | head -1
}

builds=""
for d in "$STANDALONE"/*/; do
    [ -d "$d" ] || continue
    label=$(basename "$d")
    bin=$(bindir_for "${d%/}") || continue
    builds="$builds $label"
done

if [ -z "$builds" ]; then
    echo "no usable builds under $STANDALONE (need <label>/bin or <label>/byond/bin)" >&2
    exit 1
fi

if [ "$LIST" = "1" ]; then
    echo "Discovered builds:"
    for label in $builds; do
        bin=$(bindir_for "$STANDALONE/$label")
        rep=$(reported_version "$bin")
        if [ "$rep" = "$label" ]; then state=ok; else state="MISLABELLED"; fi
        printf "%-12s binaries report %-12s %s\n" "$label" "$rep" "$state"
    done
    exit 0
fi

targets=""
for label in $builds; do
    if [ "$VERSION" = "all" ] || [ "$VERSION" = "$label" ]; then
        targets="$targets $label"
    fi
done
[ -n "$targets" ] || { echo "no build matching '$VERSION'. Try --list." >&2; exit 1; }

DME="$ROOT/suite/$SUITE.dme"
[ -f "$DME" ] || { echo "no such suite: $DME" >&2; exit 1; }
mkdir -p "$RESULTS"

# One measurement at a time on a machine, enforced rather than assumed.
#
# Killing an SSH client does not kill the command it started, so twice on
# 2026-08-02 a run kept going on this box after its local task was stopped and
# competed with the replacement started moments later. Two del runs were
# measured while a second del suite ran alongside them, which only came to
# light by comparing file timestamps. A benchmark that silently shares the CPU
# with another copy of itself reports numbers nobody can interpret.
mkdir -p "$ROOT/build"
LOCK="$ROOT/build/.run.lock"
if [ -f "$LOCK" ]; then
    holder=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        echo "another run is in progress (pid $holder). Wait for it, or clear $LOCK if that process is gone." >&2
        exit 1
    fi
    echo "stale lock from pid ${holder:-unknown}, taking it"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

port=$PORT
status=0

for label in $targets; do
    echo "=== $SUITE on $label ==="
    bin=$(bindir_for "$STANDALONE/$label")
    export LD_LIBRARY_PATH="$bin"

    rep=$(reported_version "$bin")
    if [ "$rep" != "$label" ]; then
        echo "  folder '$label' holds binaries reporting '$rep'; fix the folder name" >&2
        status=1
        continue
    fi

    wd="$ROOT/build/$label"
    mkdir -p "$wd"

    compile=$("$bin/DreamMaker" "$DME" 2>&1)
    echo "  compile: $(echo "$compile" | grep -E 'errors?,' | tail -1)"
    if echo "$compile" | grep -qE '\b[1-9][0-9]* error'; then
        echo "  compile failed on $label" >&2
        status=1
        continue
    fi

    cp "$ROOT/suite/$SUITE.dmb" "$wd/" || { status=1; continue; }
    [ -f "$ROOT/suite/$SUITE.rsc" ] && cp "$ROOT/suite/$SUITE.rsc" "$wd/"

    before=$(ls "$wd"/results-*.tsv 2>/dev/null | wc -l)
    started=$(date +%s)
    RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # How stdout is bound changes what world.log costs, by 20x on Windows and
    # in the opposite direction on Linux, where a file is fully buffered and a
    # terminal is line buffered. It is therefore a measurement condition and is
    # stamped into the result, not left to whoever ran it.
    log="$wd/$SUITE-stdout.log"
    # The PID is taken directly, not passed through a file. An earlier version
    # launched inside a subshell and wrote $! to $wd/.ddpid for the parent to
    # read back, which is a race: when the read lost, ddpid was empty, the wait
    # loop below never ran, and the script carried on while the run was still
    # going. That produced a 437 byte results file copied out of a run that had
    # not finished writing it, and left an orphan DreamDaemon holding a port.
    here=$(pwd)
    cd "$wd" || { echo "cannot enter $wd" >&2; status=1; continue; }
    case "$STDOUT_BINDING" in
        file) "$bin/DreamDaemon" "$SUITE.dmb" "$port" -trusted -invisible > "$log" 2>&1 & ;;
        tty)  "$bin/DreamDaemon" "$SUITE.dmb" "$port" -trusted -invisible & ;;
        *)    echo "unknown --stdout binding: $STDOUT_BINDING" >&2; cd "$here"; exit 2 ;;
    esac
    ddpid=$!
    cd "$here"
    [ -n "$ddpid" ] || { echo "could not start DreamDaemon for $label" >&2; status=1; continue; }

    # Elevation, and the verification that it happened. `nice -n -5` prints a
    # permission error and then runs the command at normal priority anyway,
    # exiting 0, so a runner that trusts its own request records a priority the
    # process never had. Read the achieved value out of /proc and stamp that.
    if [ "$PRIORITY" = "high" ] && [ -n "$ddpid" ]; then
        renice -n -10 -p "$ddpid" >/dev/null 2>&1 || true
    fi
    achieved=0
    if [ -n "$ddpid" ] && [ -r "/proc/$ddpid/stat" ]; then
        achieved=$(awk '{print $19}' "/proc/$ddpid/stat" 2>/dev/null || echo 0)
    fi
    if [ "$PRIORITY" = "high" ] && [ "$achieved" -ge 0 ] 2>/dev/null; then
        echo "  priority: requested high, ACHIEVED nice $achieved (needs root; recorded as normal)"
        PRIORITY_STAMP=normal
    elif [ "$PRIORITY" = "high" ]; then
        echo "  priority: high, nice $achieved"
        PRIORITY_STAMP=high
    else
        PRIORITY_STAMP=normal
    fi

    waited=0
    while kill -0 "$ddpid" 2>/dev/null; do
        sleep 2
        waited=$((waited + 2))
        if [ "$waited" -ge "$TIMEOUT" ]; then
            kill -9 "$ddpid" 2>/dev/null
            echo "  timed out after ${TIMEOUT}s on $label" >&2
            status=1
            break
        fi
    done
    elapsed=$(( $(date +%s) - started ))
    echo "  ran in ${elapsed}s"

    # A run that produces nothing must fail loudly. DreamDaemon prints
    # "FAILED to open port" and exits 0, so the exit code proves nothing, and a
    # suite run measured in seconds has not run. run.ps1 used to fall back to
    # the newest file lying around and filed the previous run's data under the
    # new run's name; there is no fallback here either.
    if [ "$elapsed" -lt 30 ]; then
        echo "  $SUITE on $label exited after ${elapsed}s. A port collision looks exactly like this: DreamDaemon fails to open port $port, says so, and exits 0. Try another port." >&2
        status=1
        port=$((port + 1))
        continue
    fi

    produced=$(find "$wd" -maxdepth 1 -name 'results-*.tsv' -newermt "@$started" | head -1)
    if [ -z "$produced" ]; then
        echo "  no results file produced on $label; the run wrote nothing this session" >&2
        status=1
        port=$((port + 1))
        continue
    fi

    # Trust the file's own header over anything this script believes.
    ver=$(sed -n 's/^# byond_version\t//p' "$produced" | head -1)
    bld=$(sed -n 's/^# byond_build\t//p' "$produced" | head -1)
    if [ "$ver.$bld" != "$rep" ]; then
        echo "  result header says $ver.$bld but binaries report $rep" >&2
        status=1
        port=$((port + 1))
        continue
    fi

    {
        printf '# runner_priority\t%s\n' "$PRIORITY_STAMP"
        printf '# runner_nice\t%s\n' "$achieved"
        printf '# stdout_binding\t%s\n' "$STDOUT_BINDING"
        printf '# host\t%s\n' "$(hostname)"
        printf '# source_commit\t%s\n' "$SOURCE_COMMIT"
        # See run.ps1 for why: this is what lets a merge refuse a triple
        # stitched across hours, which no other stamp can detect.
        printf '# run_started\t%s\n' "$RUN_STARTED"
    } >> "$produced"

    cp "$produced" "$RESULTS/$(basename "$produced")"
    echo "  $(basename "$produced")"
    sed -n 's/^# \(passed\|failed\|measured\|low_resolution\|result\)\t/\1=/p' "$produced" | tr '\n' ' '
    echo
    port=$((port + 1))
done

echo "done. baselines in $RESULTS"
exit $status
