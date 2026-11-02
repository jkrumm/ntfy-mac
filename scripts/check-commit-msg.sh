#!/usr/bin/env bash
# Local commit-msg hook: the subset of @commitlint/config-conventional this repo relies on.
# Header: type(scope)!: subject, at most 100 characters, lowercase start, no trailing period.
# Body and footer lines: at most 100 characters. Merge and Revert headers pass; fixup! and squash! do not.
set -euo pipefail

file="${1:?usage: check-commit-msg.sh <commit-message-file>}"
types='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'
header_re="^($types)(\\([a-z0-9._/-]+\\))?!?: (.+)$"
max=100

problems=()
header=""
line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" == "#"* ]] && continue
  line_no=$((line_no + 1))
  if [[ -z "$header" ]]; then
    header="$line"
    continue
  fi
  if [[ ${#line} -gt $max && ! "$line" =~ https?:// ]]; then
    problems+=("line ${line_no} is ${#line} characters (max $max)")
  fi
done <"$file"

if [[ -z "$header" ]]; then
  echo "commit message is empty" >&2
  exit 1
fi
if [[ "$header" =~ ^(Merge|Revert)\  ]]; then
  [[ ${#problems[@]} -eq 0 ]] && exit 0
elif [[ ! "$header" =~ $header_re ]]; then
  problems+=("header must be 'type(scope): subject' with type one of: ${types//|/, }")
else
  subject="${BASH_REMATCH[3]}"
  [[ ${#header} -le $max ]] || problems+=("header is ${#header} characters (max $max)")
  [[ ! "$subject" =~ ^[[:upper:]] ]] || problems+=("subject must not start with an uppercase letter")
  [[ "$subject" != *. ]] || problems+=("subject must not end with a period")
fi

if [[ ${#problems[@]} -gt 0 ]]; then
  echo "commit message rejected:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi
