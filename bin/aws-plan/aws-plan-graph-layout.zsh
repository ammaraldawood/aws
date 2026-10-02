mermaid_escape() {
  local value="$1"
  value="${value//&/\&amp;}"
  value="${value//</\&lt;}"
  value="${value//>/\&gt;}"
  value="${value//\"/\&quot;}"
  print -r -- "$value"
}

mermaid_wrap() {
  local input="$1" limit="${2:-22}" word line="" out="" separator=""
  input="${input//\\n/ }"
  for word in ${(z)input}; do
    if [[ -z $line ]]; then
      line="$word"
    elif (( ${#line} + ${#word} + 1 <= limit )); then
      line+=" $word"
    else
      out+="${separator}$(mermaid_escape "$line")"
      separator='<br/>'
      line="$word"
    fi
  done
  [[ -n $line ]] && out+="${separator}$(mermaid_escape "$line")"
  print -r -- "$out"
}

aws_plan_graph_layout() {
  : > "$MERMAID_FILE"
  cat > "$MERMAID_FILE" <<'MERMAID_HEADER'
%%{init: {"theme":"base","themeVariables":{"background":"#000000","primaryTextColor":"#ffffff","lineColor":"#ffffff","fontFamily":"Menlo, Monaco, monospace","fontSize":"32px","clusterBkg":"#000000","clusterBorder":"#ffffff"},"flowchart":{"htmlLabels":true,"curve":"stepAfter","nodeSpacing":42,"rankSpacing":96,"padding":22,"defaultRenderer":"elk"},"elk":{"layeringStrategy":"COFFMAN_GRAHAM","layeringLayerBound":3,"considerModelOrder":"PREFER_NODES"}}}%%
flowchart TB
MERMAID_HEADER
  local category sid rid node_id slabel rlabel fill any
  for category in "${GRAPH_CATEGORY_ORDER[@]}"; do
    any=false
    for sid in "${GRAPH_ACTIVE[@]}"; do
      [[ "${GRAPH_SERVICE_CATEGORY[$sid]:-}" == "$category" ]] && any=true
    done
    for rid in "${RESOURCE_IDS[@]}"; do
      [[ "${RESOURCE_CATEGORY[$rid]:-}" == "$category" ]] || continue
      is_graph_resource_emitted "$rid" && any=true
    done
    [[ $any == true ]] || continue

    print -r -- "  subgraph CAT_${category}[\"${GRAPH_CATEGORY_TITLE[$category]}\"]" >> "$MERMAID_FILE"
    print -r -- '    direction TB' >> "$MERMAID_FILE"
    for sid in "${GRAPH_ACTIVE[@]}"; do
      [[ "${GRAPH_SERVICE_CATEGORY[$sid]:-}" == "$category" ]] || continue
      case "$sid" in
        IAM|VPC|SSM) fill='#1e3a8a' ;;
        EC2|LAMBDA) fill='#166534' ;;
        S3|FSXLUSTRE) fill='#9a3412' ;;
        DCV) fill='#6b21a8' ;;
        PCS|PC) fill='#9f1239' ;;
        BATCH|ECR|DEADLINE) fill='#155e75' ;;
        BEDROCK|SAGE) fill='#86198f' ;;
        BUDGET|COSTEXP|CW) fill='#854d0e' ;;
      esac
      node_id="SVC_${sid}"
      slabel="$(mermaid_wrap "${GRAPH_SERVICE_NAME[$sid]}" 14)"
      print -r -- "    ${node_id}((\"${slabel}\"))" >> "$MERMAID_FILE"
      print -r -- "    style ${node_id} fill:${fill},stroke:${GRAPH_CATEGORY_COLOR[$category]},stroke-width:3px,color:#ffffff" >> "$MERMAID_FILE"
      for rid in "${RESOURCE_IDS[@]}"; do
        [[ "${RESOURCE_OWNER[$rid]:-}" == "$sid" ]] || continue
        is_graph_resource_emitted "$rid" || continue
        rlabel="$(mermaid_wrap "${sid} / ${RESOURCE_NAME[$rid]}" 22)"
        print -r -- "    ${rid}[\"${rlabel}\"]" >> "$MERMAID_FILE"
        print -r -- "    style ${rid} fill:${fill},stroke:${GRAPH_CATEGORY_COLOR[$category]},stroke-width:2px,color:#ffffff" >> "$MERMAID_FILE"
      done
    done
    print -r -- '  end' >> "$MERMAID_FILE"
    print -r -- "  style CAT_${category} fill:#00000000,stroke:${GRAPH_CATEGORY_COLOR[$category]},stroke-width:2px,color:${GRAPH_CATEGORY_COLOR[$category]}" >> "$MERMAID_FILE"
  done

  print -r -- '  classDef edgeTitle fill:#111111,stroke:#ffffff,stroke-width:2px,color:#ffffff,font-size:26px' >> "$MERMAID_FILE"
  typeset -g GRAPH_LINK_INDEX=0
}
