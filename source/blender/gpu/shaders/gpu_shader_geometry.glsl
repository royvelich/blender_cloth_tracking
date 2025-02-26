
#define INTERP_FACE_VARYING_2(result, fvarOffset, tessCoord) \
  { \
    vec2 v[4]; \
    int primOffset = (gl_PrimitiveID + PrimitiveIdBase) * 4; \
    for (int i = 0; i < 4; i++) { \
      int index = (primOffset + i) * osd_fvar_count + fvarOffset; \
      v[i] = vec2(texelFetch(FVarDataBuffer, index).s, texelFetch(FVarDataBuffer, index + 1).s); \
    } \
    result = mix(mix(v[0], v[1], tessCoord.s), mix(v[3], v[2], tessCoord.s), tessCoord.t); \
  }

#define INTERP_FACE_VARYING_ATT_2(result, fvarOffset, tessCoord) \
  { \
    vec2 tmp; \
    INTERP_FACE_VARYING_2(tmp, fvarOffset, tessCoord); \
    result = vec3(tmp, 0); \
  }

out block
{
  VertexData v;
}
outpt;

void set_mtface_vertex_attrs(vec2 st);

void emit_flat(int index, vec3 normal)
{
  outpt.v.position = inpt[index].v.position;
  outpt.v.normal = normal;

  /* Compatibility */
  varnormal = outpt.v.normal;
  varposition = outpt.v.position.xyz;

  /* TODO(sergey): Only uniform subdivisions atm. */
  vec2 quadst[4] = vec2[](vec2(0, 0), vec2(1, 0), vec2(1, 1), vec2(0, 1));
  vec2 st = quadst[index];

  INTERP_FACE_VARYING_2(outpt.v.uv, osd_active_uv_offset, st);

  set_mtface_vertex_attrs(st);

  gl_Position = ProjectionMatrix * inpt[index].v.position;
  EmitVertex();
}

void emit_smooth(int index)
{
  outpt.v.position = inpt[index].v.position;
  outpt.v.normal = inpt[index].v.normal;

  /* Compatibility */
  varnormal = outpt.v.normal;
  varposition = outpt.v.position.xyz;

  /* TODO(sergey): Only uniform subdivisions atm. */
  vec2 quadst[4] = vec2[](vec2(0, 0), vec2(1, 0), vec2(1, 1), vec2(0, 1));
  vec2 st = quadst[index];

  INTERP_FACE_VARYING_2(outpt.v.uv, osd_active_uv_offset, st);

  set_mtface_vertex_attrs(st);

  gl_Position = ProjectionMatrix * inpt[index].v.position;
  EmitVertex();
}

void main()
{
  gl_PrimitiveID = gl_PrimitiveIDIn;

  if (osd_flat_shading) {
    vec3 A = (inpt[0].v.position - inpt[1].v.position).xyz;
    vec3 B = (inpt[3].v.position - inpt[1].v.position).xyz;
    vec3 flat_normal = normalize(cross(B, A));
    emit_flat(0, flat_normal);
    emit_flat(1, flat_normal);
    emit_flat(3, flat_normal);
    emit_flat(2, flat_normal);
  }
  else {
    emit_smooth(0);
    emit_smooth(1);
    emit_smooth(3);
    emit_smooth(2);
  }
  EndPrimitive();
}

void set_mtface_vertex_attrs(vec2 st)
{
