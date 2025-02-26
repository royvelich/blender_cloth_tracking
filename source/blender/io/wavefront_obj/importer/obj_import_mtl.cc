/* SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup obj
 */

#include "BKE_image.h"
#include "BKE_node.h"

#include "BLI_map.hh"
#include "BLI_math_vector.h"

#include "DNA_material_types.h"
#include "DNA_node_types.h"

#include "IO_string_utils.hh"

#include "NOD_shader.h"

/* TODO: move eMTLSyntaxElement out of following file into a more neutral place */
#include "obj_export_io.hh"
#include "obj_import_mtl.hh"

namespace blender::io::obj {

/**
 * Set the socket's (of given ID) value to the given number(s).
 * Only float value(s) can be set using this method.
 */
static void set_property_of_socket(eNodeSocketDatatype property_type,
                                   StringRef socket_id,
                                   Span<float> value,
                                   bNode *r_node)
{
  BLI_assert(r_node);
  bNodeSocket *socket{nodeFindSocket(r_node, SOCK_IN, socket_id.data())};
  BLI_assert(socket && socket->type == property_type);
  switch (property_type) {
    case SOCK_FLOAT: {
      BLI_assert(value.size() == 1);
      static_cast<bNodeSocketValueFloat *>(socket->default_value)->value = value[0];
      break;
    }
    case SOCK_RGBA: {
      /* Alpha will be added manually. It is not read from the MTL file either. */
      BLI_assert(value.size() == 3);
      copy_v3_v3(static_cast<bNodeSocketValueRGBA *>(socket->default_value)->value, value.data());
      static_cast<bNodeSocketValueRGBA *>(socket->default_value)->value[3] = 1.0f;
      break;
    }
    case SOCK_VECTOR: {
      BLI_assert(value.size() == 3);
      copy_v4_v4(static_cast<bNodeSocketValueVector *>(socket->default_value)->value,
                 value.data());
      break;
    }
    default: {
      BLI_assert(0);
      break;
    }
  }
}

static bool load_texture_image_at_path(Main *bmain,
                                       const tex_map_XX &tex_map,
                                       bNode *r_node,
                                       const std::string &path)
{
  Image *tex_image = BKE_image_load(bmain, path.c_str());
  if (!tex_image) {
    fprintf(stderr, "Cannot load image file: '%s'\n", path.c_str());
    return false;
  }
  fprintf(stderr, "Loaded image from: '%s'\n", path.c_str());
  r_node->id = reinterpret_cast<ID *>(tex_image);
  NodeTexImage *image = static_cast<NodeTexImage *>(r_node->storage);
  image->projection = tex_map.projection_type;
  return true;
}

/**
 * Load image for Image Texture node and set the node properties.
 * Return success if Image can be loaded successfully.
 */
static bool load_texture_image(Main *bmain, const tex_map_XX &tex_map, bNode *r_node)
{
  BLI_assert(r_node && r_node->type == SH_NODE_TEX_IMAGE);

  /* First try treating texture path as relative. */
  std::string tex_path{tex_map.mtl_dir_path + tex_map.image_path};
  if (load_texture_image_at_path(bmain, tex_map, r_node, tex_path)) {
    return true;
  }
  /* Then try using it directly as absolute path. */
  std::string raw_path{tex_map.image_path};
  if (load_texture_image_at_path(bmain, tex_map, r_node, raw_path)) {
    return true;
  }
  /* Try removing quotes. */
  std::string no_quote_path{tex_path};
  auto end_pos = std::remove(no_quote_path.begin(), no_quote_path.end(), '"');
  no_quote_path.erase(end_pos, no_quote_path.end());
  if (no_quote_path != tex_path &&
      load_texture_image_at_path(bmain, tex_map, r_node, no_quote_path)) {
    return true;
  }
  /* Try replacing underscores with spaces. */
  std::string no_underscore_path{no_quote_path};
  std::replace(no_underscore_path.begin(), no_underscore_path.end(), '_', ' ');
  if (no_underscore_path != no_quote_path && no_underscore_path != tex_path &&
      load_texture_image_at_path(bmain, tex_map, r_node, no_underscore_path)) {
    return true;
  }

  return false;
}

ShaderNodetreeWrap::ShaderNodetreeWrap(Main *bmain, const MTLMaterial &mtl_mat, Material *mat)
    : mtl_mat_(mtl_mat)
{
  nodetree_.reset(ntreeAddTree(nullptr, "Shader Nodetree", ntreeType_Shader->idname));
  bsdf_ = add_node_to_tree(SH_NODE_BSDF_PRINCIPLED);
  shader_output_ = add_node_to_tree(SH_NODE_OUTPUT_MATERIAL);

  set_bsdf_socket_values(mat);
  add_image_textures(bmain, mat);
  link_sockets(bsdf_, "BSDF", shader_output_, "Surface", 4);

  nodeSetActive(nodetree_.get(), shader_output_);
}

/**
 * Assert if caller hasn't acquired nodetree.
 */
ShaderNodetreeWrap::~ShaderNodetreeWrap()
{
  if (nodetree_) {
    /* nodetree's ownership must be acquired by the caller. */
    nodetree_.reset();
    BLI_assert(0);
  }
}

bNodeTree *ShaderNodetreeWrap::get_nodetree()
{
  /* If this function has been reached, we know that nodes and the nodetree
   * can be added to the scene safely. */
  return nodetree_.release();
}

bNode *ShaderNodetreeWrap::add_node_to_tree(const int node_type)
{
  return nodeAddStaticNode(nullptr, nodetree_.get(), node_type);
}

std::pair<float, float> ShaderNodetreeWrap::set_node_locations(const int pos_x)
{
  int pos_y = 0;
  bool found = false;
  while (true) {
    for (Span<int> location : node_locations) {
      if (location[0] == pos_x && location[1] == pos_y) {
        pos_y += 1;
        found = true;
      }
      else {
        found = false;
      }
    }
    if (!found) {
      node_locations.append({pos_x, pos_y});
      return {pos_x * node_size_, pos_y * node_size_ * 2.0 / 3.0};
    }
  }
}

void ShaderNodetreeWrap::link_sockets(bNode *from_node,
                                      StringRef from_node_id,
                                      bNode *to_node,
                                      StringRef to_node_id,
                                      const int from_node_pos_x)
{
  std::tie(from_node->locx, from_node->locy) = set_node_locations(from_node_pos_x);
  std::tie(to_node->locx, to_node->locy) = set_node_locations(from_node_pos_x + 1);
  bNodeSocket *from_sock{nodeFindSocket(from_node, SOCK_OUT, from_node_id.data())};
  bNodeSocket *to_sock{nodeFindSocket(to_node, SOCK_IN, to_node_id.data())};
  BLI_assert(from_sock && to_sock);
  nodeAddLink(nodetree_.get(), from_node, from_sock, to_node, to_sock);
}

void ShaderNodetreeWrap::set_bsdf_socket_values(Material *mat)
{
  const int illum = mtl_mat_.illum;
  bool do_highlight = false;
  bool do_tranparency = false;
  bool do_reflection = false;
  bool do_glass = false;
  /* See https://wikipedia.org/wiki/Wavefront_.obj_file for possible values of illum. */
  switch (illum) {
    case 1: {
      /* Base color on, ambient on. */
      break;
    }
    case 2: {
      /* Highlight on. */
      do_highlight = true;
      break;
    }
    case 3: {
      /* Reflection on and Ray trace on. */
      do_reflection = true;
      break;
    }
    case 4: {
      /* Transparency: Glass on, Reflection: Ray trace on. */
      do_glass = true;
      do_reflection = true;
      do_tranparency = true;
      break;
    }
    case 5: {
      /* Reflection: Fresnel on and Ray trace on. */
      do_reflection = true;
      break;
    }
    case 6: {
      /* Transparency: Refraction on, Reflection: Fresnel off and Ray trace on. */
      do_reflection = true;
      do_tranparency = true;
      break;
    }
    case 7: {
      /* Transparency: Refraction on, Reflection: Fresnel on and Ray trace on. */
      do_reflection = true;
      do_tranparency = true;
      break;
    }
    case 8: {
      /* Reflection on and Ray trace off. */
      do_reflection = true;
      break;
    }
    case 9: {
      /* Transparency: Glass on, Reflection: Ray trace off. */
      do_glass = true;
      do_reflection = false;
      do_tranparency = true;
      break;
    }
    default: {
      std::cerr << "Warning! illum value = " << illum
                << "is not supported by the Principled-BSDF shader." << std::endl;
      break;
    }
  }
  /* Approximations for trying to map obj/mtl material model into
   * Principled BSDF: */
  /* Specular: average of Ks components. */
  float specular = (mtl_mat_.Ks[0] + mtl_mat_.Ks[1] + mtl_mat_.Ks[2]) / 3;
  /* Roughness: map 0..1000 range to 1..0 and apply non-linearity. */
  float clamped_ns = std::max(0.0f, std::min(1000.0f, mtl_mat_.Ns));
  float roughness = 1.0f - sqrt(clamped_ns / 1000.0f);
  /* Metallic: average of Ka components. */
  float metallic = (mtl_mat_.Ka[0] + mtl_mat_.Ka[1] + mtl_mat_.Ka[2]) / 3;
  float ior = mtl_mat_.Ni;
  float alpha = mtl_mat_.d;

  if (specular < 0.0f) {
    specular = static_cast<float>(do_highlight);
  }
  if (mtl_mat_.Ns < 0.0f) {
    roughness = static_cast<float>(!do_highlight);
  }
  if (metallic < 0.0f) {
    if (do_reflection) {
      metallic = 1.0f;
    }
  }
  else {
    metallic = 0.0f;
  }
  if (ior < 0) {
    if (do_tranparency) {
      ior = 1.0f;
    }
    if (do_glass) {
      ior = 1.5f;
    }
  }
  if (alpha < 0) {
    if (do_tranparency) {
      alpha = 1.0f;
    }
  }
  float3 base_color = {std::max(0.0f, mtl_mat_.Kd[0]),
                       std::max(0.0f, mtl_mat_.Kd[1]),
                       std::max(0.0f, mtl_mat_.Kd[2])};
  float3 emission_color = {std::max(0.0f, mtl_mat_.Ke[0]),
                           std::max(0.0f, mtl_mat_.Ke[1]),
                           std::max(0.0f, mtl_mat_.Ke[2])};

  set_property_of_socket(SOCK_RGBA, "Base Color", {base_color, 3}, bsdf_);
  set_property_of_socket(SOCK_RGBA, "Emission", {emission_color, 3}, bsdf_);
  if (mtl_mat_.texture_maps.contains_as(eMTLSyntaxElement::map_Ke)) {
    set_property_of_socket(SOCK_FLOAT, "Emission Strength", {1.0f}, bsdf_);
  }
  set_property_of_socket(SOCK_FLOAT, "Specular", {specular}, bsdf_);
  set_property_of_socket(SOCK_FLOAT, "Roughness", {roughness}, bsdf_);
  set_property_of_socket(SOCK_FLOAT, "Metallic", {metallic}, bsdf_);
  set_property_of_socket(SOCK_FLOAT, "IOR", {ior}, bsdf_);
  set_property_of_socket(SOCK_FLOAT, "Alpha", {alpha}, bsdf_);
  if (do_tranparency) {
    mat->blend_method = MA_BM_BLEND;
  }
}

void ShaderNodetreeWrap::add_image_textures(Main *bmain, Material *mat)
{
  for (const Map<const eMTLSyntaxElement, tex_map_XX>::Item texture_map :
       mtl_mat_.texture_maps.items()) {
    if (texture_map.value.image_path.empty()) {
      /* No Image texture node of this map type can be added to this material. */
      continue;
    }

    bNode *image_texture = add_node_to_tree(SH_NODE_TEX_IMAGE);
    if (!load_texture_image(bmain, texture_map.value, image_texture)) {
      /* Image could not be added, so don't add or link further nodes. */
      continue;
    }

    /* Add normal map node if needed. */
    bNode *normal_map = nullptr;
    if (texture_map.key == eMTLSyntaxElement::map_Bump) {
      normal_map = add_node_to_tree(SH_NODE_NORMAL_MAP);
      const float bump = std::max(0.0f, mtl_mat_.map_Bump_strength);
      set_property_of_socket(SOCK_FLOAT, "Strength", {bump}, normal_map);
    }

    /* Add UV mapping & coordinate nodes only if needed. */
    if (texture_map.value.translation != float3(0, 0, 0) ||
        texture_map.value.scale != float3(1, 1, 1)) {
      bNode *mapping = add_node_to_tree(SH_NODE_MAPPING);
      bNode *texture_coordinate = add_node_to_tree(SH_NODE_TEX_COORD);
      set_property_of_socket(SOCK_VECTOR, "Location", {texture_map.value.translation, 3}, mapping);
      set_property_of_socket(SOCK_VECTOR, "Scale", {texture_map.value.scale, 3}, mapping);

      link_sockets(texture_coordinate, "UV", mapping, "Vector", 0);
      link_sockets(mapping, "Vector", image_texture, "Vector", 1);
    }

    if (normal_map) {
      link_sockets(image_texture, "Color", normal_map, "Color", 2);
      link_sockets(normal_map, "Normal", bsdf_, "Normal", 3);
    }
    else if (texture_map.key == eMTLSyntaxElement::map_d) {
      link_sockets(image_texture, "Alpha", bsdf_, texture_map.value.dest_socket_id, 2);
      mat->blend_method = MA_BM_BLEND;
    }
    else {
      link_sockets(image_texture, "Color", bsdf_, texture_map.value.dest_socket_id, 2);
    }
  }
}
}  // namespace blender::io::obj
