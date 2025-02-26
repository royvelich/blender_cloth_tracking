
#pragma BLENDER_REQUIRE(common_view_lib.glsl)
#pragma BLENDER_REQUIRE(common_math_lib.glsl)
#pragma BLENDER_REQUIRE(gpu_shader_codegen_lib.glsl)

vec3 g_emission;
vec3 g_transmittance;
float g_holdout;

/* The Closure type is never used. Use float as dummy type. */
#define Closure float

/* Sampled closure parameters. */
ClosureDiffuse g_diffuse_data;
ClosureReflection g_reflection_data;
ClosureRefraction g_refraction_data;
/* Random number per sampled closure type. */
float g_diffuse_rand;
float g_reflection_rand;
float g_refraction_rand;

/**
 * Returns true if the closure is to be selected based on the input weight.
 */
bool closure_select(float weight, inout float total_weight, inout float r)
{
  total_weight += weight;
  float x = weight / total_weight;
  bool chosen = (r < x);
  /* Assuming that if r is in the interval [0,x] or [x,1], it's still uniformly distributed within
   * that interval, so you remaping to [0,1] again to explore this space of probability. */
  r = (chosen) ? (r / x) : ((r - x) / (1.0 - x));
  return chosen;
}

#define SELECT_CLOSURE(destination, random, candidate) \
  if (closure_select(candidate.weight, destination.weight, random)) { \
    destination = candidate; \
  }

void closure_weights_reset()
{
  g_diffuse_data.weight = 0.0;
  g_diffuse_data.color = vec3(0.0);
  g_diffuse_data.N = vec3(0.0);
  g_diffuse_data.sss_radius = vec3(0.0);
  g_diffuse_data.sss_id = uint(0);

  g_reflection_data.weight = 0.0;
  g_reflection_data.color = vec3(0.0);
  g_reflection_data.N = vec3(0.0);
  g_reflection_data.roughness = 0.0;

  g_refraction_data.weight = 0.0;
  g_refraction_data.color = vec3(0.0);
  g_refraction_data.N = vec3(0.0);
  g_refraction_data.roughness = 0.0;
  g_refraction_data.ior = 0.0;

  /* TEMP */
#define P(x) ((x + 0.5) / 16.0)
  const vec4 dither_mat4x4[4] = vec4[4](vec4(P(0.0), P(8.0), P(2.0), P(10.0)),
                                        vec4(P(12.0), P(4.0), P(14.0), P(6.0)),
                                        vec4(P(3.0), P(11.0), P(1.0), P(9.0)),
                                        vec4(P(15.0), P(7.0), P(13.0), P(5.0)));
#undef P
#if defined(GPU_FRAGMENT_SHADER)
  ivec2 pix = ivec2(gl_FragCoord.xy) % ivec2(4);
  g_diffuse_rand = dither_mat4x4[pix.x][pix.y];
  g_reflection_rand = dither_mat4x4[pix.x][pix.y];
  g_refraction_rand = dither_mat4x4[pix.x][pix.y];
#else
  g_diffuse_rand = 0.0;
  g_reflection_rand = 0.0;
  g_refraction_rand = 0.0;
#endif

  g_emission = vec3(0.0);
  g_transmittance = vec3(0.0);
  g_holdout = 0.0;
}

/* Single BSDFs. */
Closure closure_eval(ClosureDiffuse diffuse)
{
  SELECT_CLOSURE(g_diffuse_data, g_diffuse_rand, diffuse);
  return Closure(0);
}

Closure closure_eval(ClosureTranslucent translucent)
{
  /* TODO */
  return Closure(0);
}

Closure closure_eval(ClosureReflection reflection)
{
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  return Closure(0);
}

Closure closure_eval(ClosureRefraction refraction)
{
  SELECT_CLOSURE(g_refraction_data, g_refraction_rand, refraction);
  return Closure(0);
}

Closure closure_eval(ClosureEmission emission)
{
  g_emission += emission.emission * emission.weight;
  return Closure(0);
}

Closure closure_eval(ClosureTransparency transparency)
{
  g_transmittance += transparency.transmittance * transparency.weight;
  g_holdout += transparency.holdout * transparency.weight;
  return Closure(0);
}

Closure closure_eval(ClosureVolumeScatter volume_scatter)
{
  /* TODO */
  return Closure(0);
}

Closure closure_eval(ClosureVolumeAbsorption volume_absorption)
{
  /* TODO */
  return Closure(0);
}

Closure closure_eval(ClosureHair hair)
{
  /* TODO */
  return Closure(0);
}

/* Glass BSDF. */
Closure closure_eval(ClosureReflection reflection, ClosureRefraction refraction)
{
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  SELECT_CLOSURE(g_refraction_data, g_refraction_rand, refraction);
  return Closure(0);
}

/* Dielectric BSDF. */
Closure closure_eval(ClosureDiffuse diffuse, ClosureReflection reflection)
{
  SELECT_CLOSURE(g_diffuse_data, g_diffuse_rand, diffuse);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  return Closure(0);
}

/* ClearCoat BSDF. */
Closure closure_eval(ClosureReflection reflection, ClosureReflection clearcoat)
{
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, clearcoat);
  return Closure(0);
}

/* Volume BSDF. */
Closure closure_eval(ClosureVolumeScatter volume_scatter,
                     ClosureVolumeAbsorption volume_absorption,
                     ClosureEmission emission)
{
  /* TODO */
  return Closure(0);
}

/* Specular BSDF. */
Closure closure_eval(ClosureDiffuse diffuse,
                     ClosureReflection reflection,
                     ClosureReflection clearcoat)
{
  SELECT_CLOSURE(g_diffuse_data, g_diffuse_rand, diffuse);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, clearcoat);
  return Closure(0);
}

/* Principled BSDF. */
Closure closure_eval(ClosureDiffuse diffuse,
                     ClosureReflection reflection,
                     ClosureReflection clearcoat,
                     ClosureRefraction refraction)
{
  SELECT_CLOSURE(g_diffuse_data, g_diffuse_rand, diffuse);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, reflection);
  SELECT_CLOSURE(g_reflection_data, g_reflection_rand, clearcoat);
  SELECT_CLOSURE(g_refraction_data, g_refraction_rand, refraction);
  return Closure(0);
}

/* Noop since we are sampling closures. */
Closure closure_add(Closure cl1, Closure cl2)
{
  return Closure(0);
}
Closure closure_mix(Closure cl1, Closure cl2, float fac)
{
  return Closure(0);
}

float ambient_occlusion_eval(vec3 normal,
                             float distance,
                             const float inverted,
                             const float sample_count)
{
  /* TODO */
  return 1.0;
}

#ifndef GPU_METAL
void attrib_load();
Closure nodetree_surface();
Closure nodetree_volume();
vec3 nodetree_displacement();
float nodetree_thickness();
vec4 closure_to_rgba(Closure cl);
#endif

/* Stubs. */
vec2 btdf_lut(float a, float b, float c)
{
  return vec2(1, 0);
}
vec2 brdf_lut(float a, float b)
{
  return vec2(1, 0);
}
vec3 F_brdf_multi_scatter(vec3 a, vec3 b, vec2 c)
{
  return a;
}
vec3 F_brdf_single_scatter(vec3 a, vec3 b, vec2 c)
{
  return a;
}
float F_eta(float a, float b)
{
  return a;
}
void output_aov(vec4 color, float value, uint hash)
{
}

#ifdef EEVEE_MATERIAL_STUBS
#  define attrib_load()
#  define nodetree_displacement() vec3(0.0)
#  define nodetree_surface() Closure(0)
#  define nodetree_volume() Closure(0)
#  define nodetree_thickness() 0.1
#endif

/* -------------------------------------------------------------------- */
/** \name Fragment Displacement
 *
 * Displacement happening in the fragment shader.
 * Can be used in conjunction with a per vertex displacement.
 *
 * \{ */

#ifdef MAT_DISPLACEMENT_BUMP
/* Return new shading normal. */
vec3 displacement_bump()
{
#  ifdef GPU_FRAGMENT_SHADER
  vec2 dHd;
  dF_branch(dot(nodetree_displacement(), g_data.N + dF_impl(g_data.N)), dHd);

  vec3 dPdx = dFdx(g_data.P);
  vec3 dPdy = dFdy(g_data.P);

  /* Get surface tangents from normal. */
  vec3 Rx = cross(dPdy, g_data.N);
  vec3 Ry = cross(g_data.N, dPdx);

  /* Compute surface gradient and determinant. */
  float det = dot(dPdx, Rx);

  vec3 surfgrad = dHd.x * Rx + dHd.y * Ry;

  float facing = FrontFacing ? 1.0 : -1.0;
  return normalize(abs(det) * g_data.N - facing * sign(det) * surfgrad);
#  else
  return g_data.N;
#  endif
}
#endif

void fragment_displacement()
{
#ifdef MAT_DISPLACEMENT_BUMP
  g_data.N = displacement_bump();
#endif
}

/** \} */

/* -------------------------------------------------------------------- */
/** \name Coordinate implementations
 *
 * Callbacks for the texture coordinate node.
 *
 * \{ */

vec3 coordinate_camera(vec3 P)
{
  vec3 vP;
  if (false /* probe */) {
    /* Unsupported. It would make the probe camera-dependent. */
    vP = P;
  }
  else {
#ifdef MAT_WORLD
    vP = transform_direction(ViewMatrix, P);
#else
    vP = transform_point(ViewMatrix, P);
#endif
  }
  vP.z = -vP.z;
  return vP;
}

vec3 coordinate_screen(vec3 P)
{
  vec3 window = vec3(0.0);
  if (false /* probe */) {
    /* Unsupported. It would make the probe camera-dependent. */
    window.xy = vec2(0.5);
  }
  else {
    /* TODO(fclem): Actual camera tranform. */
    window.xy = project_point(ViewProjectionMatrix, P).xy * 0.5 + 0.5;
    window.xy = window.xy * CameraTexCoFactors.xy + CameraTexCoFactors.zw;
  }
  return window;
}

vec3 coordinate_reflect(vec3 P, vec3 N)
{
#ifdef MAT_WORLD
  return N;
#else
  return -reflect(cameraVec(P), N);
#endif
}

vec3 coordinate_incoming(vec3 P)
{
#ifdef MAT_WORLD
  return -P;
#else
  return cameraVec(P);
#endif
}

/** \} */
