package af

import "core:c"
import "core:strings"
import gl "vendor:OpenGL"
import stbimage "vendor:stb/image"

Image :: struct {
	data:                        [^]byte,
	width, height, num_channels: int,
}

Texture :: struct {
	width, height, num_channels:         int,
	handle:                              u32,
	filtering, clamping:                 int,
	pixel_format, internal_pixel_format: uint,
}

TEXTURE_FILTERING_NEAREST :: gl.NEAREST
TEXTURE_FILTERING_LINEAR :: gl.LINEAR

DEFAULT_TEXTURE_CONFIG :: Texture {
	filtering             = gl.NEAREST,
	clamping              = gl.CLAMP,
	pixel_format          = gl.RGBA,
	internal_pixel_format = gl.RGBA,
}

new_image :: proc(path: string) -> ^Image {
	image := new(Image)

	path_cstr := strings.clone_to_cstring(path)
	defer delete(path_cstr)

	width, height, num_channels: c.int
	stbimage.set_flip_vertically_on_load(1)
	image.data = stbimage.load(path_cstr, &width, &height, &num_channels, 4)

	image.width = int(width)
	image.height = int(height)
	image.num_channels = int(num_channels)

	return image
}

free_image :: proc(image: ^Image) {
	stbimage.image_free(image.data)
	free(image)
}

upload_texture_settings :: proc(texture: ^Texture) {
	use_texture(texture)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, c.int(texture.filtering))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, c.int(texture.filtering))

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, c.int(texture.clamping))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, c.int(texture.clamping))
}

upload_texture :: proc(texture: ^Texture, width, height, num_channels: int, data: [^]byte) {
	use_texture(texture)

	texture.width = width
	texture.height = height
	texture.num_channels = num_channels

	gl.TexImage2D(
		gl.TEXTURE_2D, // GLenum target,
		0, // GLint level,
		c.int(texture.internal_pixel_format), // GLint internalformat,
		c.int(texture.width), // GLsizei width,
		c.int(texture.height), // GLsizei height,
		0, // GLint border,
		u32(texture.pixel_format), // GLenum format,
		gl.UNSIGNED_BYTE, // GLenum type,
		data, // const void * data);
	)

	err := gl.GetError()
	if (err != gl.NO_ERROR) {
		debug_log(
			"ERROR uploading texture - %d, %d, %d, %d - %d",
			texture.internal_pixel_format,
			texture.width,
			texture.height,
			texture.pixel_format,
			err,
		)
		panic("xd")
	}
}

new_texture_image :: proc(image: ^Image, config: Texture = DEFAULT_TEXTURE_CONFIG) -> ^Texture {
	texture := new_clone(config)
	gl.GenTextures(1, &texture.handle)

	upload_texture(texture, image.width, image.height, image.num_channels, image.data)
	upload_texture_settings(texture)

	gl.BindTexture(gl.TEXTURE_2D, 0)
	return texture
}

new_texture_size :: proc(
	width, height: int,
	config: Texture = DEFAULT_TEXTURE_CONFIG,
) -> ^Texture {
	texture := new_clone(config)
	gl.GenTextures(1, &texture.handle)

	upload_texture(texture, width, height, 4, nil)
	upload_texture_settings(texture)

	gl.BindTexture(gl.TEXTURE_2D, 0)
	return texture
}

use_texture :: proc(texture: ^Texture) {
	gl.BindTexture(gl.TEXTURE_2D, texture.handle)
}

@(private)
internal_set_texture_unit :: proc(unit: int) {
	gl.ActiveTexture(u32(unit))
}

// NOTE: this will change the currently bound OpenGL texture
upload_texture_subregion :: proc(texture: ^Texture, rowPx, columnPx: int, sub_image: ^Image) {
	use_texture(texture)

	gl.TexSubImage2D(
		gl.TEXTURE_2D,
		0,
		c.int(rowPx),
		c.int(columnPx),
		c.int(sub_image.width),
		c.int(sub_image.height),
		u32(texture.pixel_format),
		gl.UNSIGNED_BYTE,
		sub_image.data,
	)
}

free_texture :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, &texture.handle)
	free(texture)
}

resize_texture :: proc(texture: ^Texture, width, height: int) {
	if (texture.width == width && texture.height == height) {
		return
	}

	upload_texture(texture, width, height, 4, nil)
}
