aws_plan_graph_edges() {
  typeset -gA SERVICE_REL_KIND SERVICE_REL_LABEL
  local entry rel_key src dst edge_id title link_operator style_label
  local edge_index=0

  for entry in "${RESOURCE_EDGES[@]}"; do
    resource_edge_parts "$entry"
    [[ "$RES_CONDITION" == NOPROJ ]] && continue
    resource_condition_ok "$RES_CONDITION" || continue
    is_graph_resource_emitted "$RES_SRC" || continue
    is_graph_resource_emitted "$RES_DST" || continue
    src="${RESOURCE_OWNER[$RES_SRC]}"
    dst="${RESOURCE_OWNER[$RES_DST]}"
    [[ $src == $dst ]] && continue
    is_graph_service_active "$src" || continue
    is_graph_service_active "$dst" || continue
    rel_key="$src|$dst"
    if [[ $RES_KIND == architecture ]]; then
      SERVICE_REL_KIND[$rel_key]=architecture
      SERVICE_REL_LABEL[$rel_key]="$RES_LABEL"
    elif [[ -z ${SERVICE_REL_KIND[$rel_key]:-} ]]; then
      SERVICE_REL_KIND[$rel_key]=setup
      SERVICE_REL_LABEL[$rel_key]="$RES_LABEL"
    fi
  done

  if [[ $REQ_DEADLINE == true && $MAC_REQUIRED == true && $REQ_EC2 == true ]]; then
    SERVICE_REL_KIND["DEADLINE|EC2"]=setup
    SERVICE_REL_LABEL["DEADLINE|EC2"]='install/register Mac worker agent'
  fi

  for rel_key in ${(ok)SERVICE_REL_KIND}; do
    src="${rel_key%%|*}"
    dst="${rel_key#*|}"
    if [[ ${SERVICE_REL_KIND[$rel_key]} == setup ]]; then
      print -r -- "  SVC_${src} -.-> SVC_${dst}" >> "$MERMAID_FILE"
      print -r -- "  linkStyle ${GRAPH_LINK_INDEX} stroke:#ffffff,stroke-width:2px,stroke-dasharray:4 4" >> "$MERMAID_FILE"
    else
      print -r -- "  SVC_${src} --> SVC_${dst}" >> "$MERMAID_FILE"
      print -r -- "  linkStyle ${GRAPH_LINK_INDEX} stroke:#ffffff,stroke-width:2px" >> "$MERMAID_FILE"
    fi
    GRAPH_LINK_INDEX=$((GRAPH_LINK_INDEX + 1))
  done

  for entry in "${RESOURCE_EDGES[@]}"; do
    resource_edge_parts "$entry"
    resource_condition_ok "$RES_CONDITION" || continue
    is_graph_resource_emitted "$RES_SRC" || continue
    is_graph_resource_emitted "$RES_DST" || continue
    title="$(mermaid_wrap "$(resource_display_label)" 16)"
    edge_id="EDGE_${edge_index}"
    print -r -- "  ${edge_id}(\"${title}\"):::edgeTitle" >> "$MERMAID_FILE"
    if [[ $RES_KIND == setup ]]; then
      print -r -- "  ${RES_SRC} -.- ${edge_id} -.-> ${RES_DST}" >> "$MERMAID_FILE"
      print -r -- "  linkStyle ${GRAPH_LINK_INDEX},$((GRAPH_LINK_INDEX + 1)) stroke:#ffffff,stroke-width:2px,stroke-dasharray:4 4" >> "$MERMAID_FILE"
    else
      print -r -- "  ${RES_SRC} --- ${edge_id} --> ${RES_DST}" >> "$MERMAID_FILE"
      print -r -- "  linkStyle ${GRAPH_LINK_INDEX},$((GRAPH_LINK_INDEX + 1)) stroke:#ffffff,stroke-width:2px" >> "$MERMAID_FILE"
    fi
    GRAPH_LINK_INDEX=$((GRAPH_LINK_INDEX + 2))
    edge_index=$((edge_index + 1))
  done
}
