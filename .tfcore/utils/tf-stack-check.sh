#!/usr/bin/env bash
# tf-stack-check.sh — does the code use the packages the Architecture requires? See tf_stack_check.py.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tf_stack_check.py" "$@"
