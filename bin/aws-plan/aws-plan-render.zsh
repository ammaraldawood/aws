aws_plan_render_graph() {
  local input="$1" svg="$2" output="$3" err="$4"
  if ! command -v mmdc >/dev/null 2>&1; then
    say "${Y}Mermaid rendering skipped. Install Mermaid CLI (mmdc). The source is at $input.${R}"
    return 0
  fi

  if ! mmdc -i "$input" -o "$svg" -b '#000000' 2>"$err"; then
    say "${Y}Mermaid SVG rendering failed; source retained at $input.${R}"
    say "Error log: $err"
    return 0
  fi
  if ! mmdc -i "$input" -o "$output" -b '#000000' --size 4800 2>>"$err"; then
    say "${Y}Mermaid PNG rendering failed; SVG retained at $svg.${R}"
    say "Error log: $err"
    return 0
  fi

  say "${G}Mermaid architecture SVG: $svg${R}"
  say "${G}Mermaid architecture PNG: $output${R}"
  if [[ -t 1 ]] && command -v chafa >/dev/null 2>&1; then
    local term_width
    term_width="$(tput cols 2>/dev/null || print 120)"
    local -a fmt=()
    if [[ -n ${KITTY_WINDOW_ID:-} || ${TERM:-} == *kitty* || ${TERM:-} == *ghostty* || ${TERM_PROGRAM:-} == (ghostty|WezTerm) ]]; then
      fmt=(--format=kitty)
    fi
    chafa "${fmt[@]}" --size="${term_width}x9000" "$output"
    print
  fi
}
