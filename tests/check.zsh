#!/usr/bin/env zsh
set -euo pipefail

ROOT=${0:A:h:h}
PLAN=$ROOT/bin/aws-plan/aws-plan
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

fail() {
  print -u2 -r -- "FAIL: $*"
  exit 1
}

run_plan() {
  local name=$1 answers=$2
  local out=$WORKDIR/$name
  local empty=$WORKDIR/empty.env
  : > "$empty"
  mkdir -p "$out"
  if ! env NO_COLOR=1 AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 \
      AWS_SETUP_OUT=$out AWS_SETUP_CONFIG=$empty \
      "$PLAN" >"$out/stdout.log" 2>"$out/stderr.log" <<< "${answers}"$'\nn'; then
    print -u2 -r -- "----- $name stdout log -----"
    tail -n 60 "$out/stdout.log" >&2
    print -u2 -r -- "----- $name stderr log -----"
    tail -n 60 "$out/stderr.log" >&2
    fail "$name exited non-zero"
  fi
  [[ -s $out/plan.json ]] || fail "$name did not write plan.json"
  grep -q 'command not found' "$out/stderr.log" && fail "$name reported a missing command"
  grep -q 'Failed to write the plan file' "$out/stderr.log" && fail "$name failed to write the plan"
  print -r -- "$out"
}

assert_has() {
  local file=$1 needle=$2
  grep -F -q -- "$needle" "$file" || fail "missing [$needle] in ${file:t}"
}

assert_lacks() {
  local file=$1 needle=$2
  if grep -F -q -- "$needle" "$file"; then
    fail "unexpected [$needle] in ${file:t}"
  fi
}

# Needles with no producer in the planner (pure guard rails) must be absent
# from the whole run: the pre-split helper checked one merged stream, so keep
# that exact meaning by screening both split streams.
assert_lacks_any_stream() {
  local needle=$1; shift
  local file
  for file in "$@"; do
    assert_lacks "$file" "$needle"
  done
}

assert_json() {
  local file=$1 expression=$2
  jq -e "$expression" "$file" >/dev/null || fail "JSON condition failed for ${file:t}: $expression"
}

# Host-neutral mtime reads. `stat -f %m` is BSD-only (GNU stat treats -f as
# --file-system and exits 1 on '%m'); `stat -c %Y` is GNU-only and fails on
# macOS. The zsh/stat module returns integer mtime on any host, and zsh is
# already a hard requirement of this harness. If the module cannot load, say
# so explicitly instead of dying cryptically under set -e.
zmodload zsh/stat || fail "zsh/stat module is required by tests/check.zsh"

empty=$WORKDIR/empty-default.env
: > "$empty"
parent_out=${ROOT:h}/out
parent_stamp=""
[[ -d $parent_out ]] && parent_stamp=$(zstat +mtime "$parent_out")
default_out=$(env -u AWS_SETUP_OUT NO_COLOR=1 AWS_SETUP_CONFIG=$empty zsh -c '
  source "'"$ROOT"'/bin/aws-plan/aws-plan-setup-lib.zsh"
  aws_setup_init "'"$ROOT"'/bin/aws-plan/aws-plan"
  print -r -- "$AWS_SETUP_OUT"
')
[[ $default_out == $ROOT/out ]] || fail "default output is $default_out"
if [[ -n $parent_stamp ]]; then
  [[ $(zstat +mtime "$parent_out") == $parent_stamp ]] || fail "default setup touched $parent_out"
fi

spot=$(run_plan spot $'1\n\n\ny\nn\nn\ny\ny\ny\nn\nn\nn\nn')
assert_json $spot/plan.json '.schema == "pc-aws-plan/v2" and .workload.execution_model == "DIRECT_EC2"'
assert_json $spot/plan.json '[.decision.selected_services[].id] | index("SPOT") != null'
assert_has $spot/plan.json '"service_relationships"'
assert_has $spot/plan.json '"relationships"'
assert_lacks $spot/plan.json '"deployment"'
assert_has $spot/architecture.mmd 'Mountpoint for<br/>S3: /mnt/s3'
assert_has $spot/architecture.mmd 'subgraph CAT_security'
assert_has $spot/architecture.mmd 'SVC_IAM(("AWS IAM"))'
assert_has $spot/architecture.mmd 'classDef edgeTitle'
assert_has $spot/architecture.mmd 'EDGE_'
assert_lacks $spot/architecture.mmd 'configure S3 event trigger'
assert_lacks_any_stream 'falling back' $spot/stdout.log $spot/stderr.log
assert_lacks $spot/stdout.log 'rendering skipped'
assert_lacks_any_stream 'Graphviz' $spot/stdout.log $spot/stderr.log
assert_lacks $spot/mermaid.log 'Parse error'
assert_has $spot/stdout.log 'Plan:'

gpu=$(run_plan gpu $'1\n2\n\n1\n\ny\ny\nn\nn\ny\nn\nn\nn\nn')
assert_json $gpu/plan.json '.requirements.dcv == true and .requirements.gpu_kind == "1"'

api=$(run_plan api $'8\nn\ny\nn\nn')
assert_json $api/plan.json '.workload.execution_model == "MANAGED_API" and ([.decision.selected_services[].id] | index("BEDROCK") != null)'
assert_lacks $api/architecture.mmd 'configure S3 event trigger'

lambda_files=$(run_plan lambda-files $'9\ny\nn\nn\nn\nn')
assert_json $lambda_files/plan.json '.requirements.s3 == true'
assert_lacks $lambda_files/architecture.mmd 'configure S3 event trigger'

lambda_events=$(run_plan lambda-events $'9\nn\ny\nn\nn\nn')
assert_has $lambda_events/architecture.mmd 'configure S3<br/>event trigger'
assert_json $lambda_events/plan.json '.requirements.s3 == true'

pcs=$(run_plan pcs $'6\n3\n\n1\ny\nn\nn\ny\n1\nn\nn\nn\nn')
assert_json $pcs/plan.json '.workload.execution_model == "MULTI_NODE_PCS"'
assert_has $pcs/architecture.mmd 'PCSNG --- EDGE_'
assert_has $pcs/architecture.mmd 'launches<br/>Trainium'
assert_has $pcs/architecture.mmd 'allow EFA<br/>traffic'
assert_lacks $pcs/architecture.mmd 'EFA/Lustre'

# CLI-driven ParallelCluster (WORKLOAD 6, Slurm operating model 2): the sibling
# of pcs above, differing by exactly that one answer. Covers the execution mode
# MULTI_NODE_PARALLELCLUSTER and the PC/ParallelCluster graph path (PCCL node,
# PC service circle, PC-issued cluster capacity), which no other scenario asserts.
pc=$(run_plan pc $'6\n\n\ny\nn\nn\ny\n2\nn\nn\nn\nn\nn')
assert_json $pc/plan.json '.workload.execution_model == "MULTI_NODE_PARALLELCLUSTER"'
assert_json $pc/plan.json '[.decision.selected_services[].id] | index("PC") != null'
assert_json $pc/plan.json '[.decision.selected_services[].id] | index("PCS") == null'
assert_has $pc/architecture.mmd 'PCCL --- EDGE_'
assert_has $pc/architecture.mmd 'SVC_PC(("AWS<br/>ParallelCluster"))'
assert_has $pc/architecture.mmd 'managed by<br/>ParallelCluster'
assert_has $pc/architecture.mmd 'provisions EC2<br/>cluster capacity'
assert_has $pc/architecture.mmd 'use cluster IAM<br/>roles'
assert_has $pc/architecture.mmd 'allow EFA<br/>traffic'
assert_lacks $pc/architecture.mmd 'EFA/Lustre'
assert_lacks $pc/architecture.mmd 'PCSNG'
assert_lacks $pc/architecture.mmd 'PCSQ'

sage=$(run_plan sage $'7\ny\n3\n\n1\nn\ny\ny\ny\nn\nn\nn')
assert_json $sage/plan.json '.workload.execution_model == "MANAGED_ML"'
assert_has $sage/architecture.mmd 'EFAI['
assert_has $sage/architecture.mmd 'SMJOB --- EDGE_'
assert_lacks $sage/architecture.mmd 'SVC_VPC'

trn=$(run_plan trn $'7\nn\n3\n\n1\ny\nn\nn\nn\nn\nn\nn')
assert_has $trn/architecture.mmd 'EC2 Trainium'
assert_lacks $trn/architecture.mmd 'TRNNODE['
assert_lacks $trn/architecture.mmd 'type selected later'

batch=$(run_plan batch $'2\n\n\nn\nn\ny\ny\ny\nn\nn\nn\nn')
assert_json $batch/plan.json '.workload.execution_model == "BATCH"'
assert_has $batch/architecture.mmd 'configure S3<br/>access'
assert_lacks $batch/architecture.mmd 'Mountpoint for S3'

print -r -- "ok"
