package af

import stbimage "vendor:stb/image"
import "core:strings"
import "core:c"
import gl "vendor:OpenGL"

Image :: struct {
    data: [^]byte,
    width, height, num_channels : int,
};

Texture :: struct {
    width, height, num_channels : int,

    handle: u32,
    filtering, clamping: int,
    pixel_format, internal_pixel_format: uint,
};

texture_config_default :: Texture {
    filtering = gl.NEAREST,
    clamping = gl.CLAMP,
    pixel_format = gl.RGBA,
    internal_pixel_format = gl.RGBA,
};

Image_Load :: proc(path: string) -> ^Image {
    image := new(Image);

    path_cstr := strings.clone_to_cstring(path)
    defer delete(path_cstr)

    width, height, num_channels: c.int
    image.data = stbimage.load(path_cstr, &width, &height, &num_channels, 4);

    image.width = int(width)
    image.height = int(height)
    image.num_channels = int(num_channels)

    return image;
}

Image_Free :: proc(image: ^Image) {
    stbimage.image_free(image.data)
    free(image)
}

Texture_ApplySettings :: proc(texture: ^Texture) {
    Texture_Use(texture);

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, c.int(texture.filtering));
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, c.int(texture.filtering));

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, c.int(texture.clamping));
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, c.int(texture.clamping));
}

Texture_Upload :: proc(texture: ^Texture, width, height, num_channels: int, data: [^]byte) {
    Texture_Use(texture);

    texture.width = width;
    texture.height = height;
    texture.num_channels = num_channels;

    gl.TexImage2D(
        gl.TEXTURE_2D,          // GLenum target,
        0,                      // GLint level,
        c.int(texture.internal_pixel_format),   // GLint internalformat,
        c.int(texture.width),                   // GLsizei width,
        c.int(texture.height),                  // GLsizei height,
        0,                                      // GLint border,
        u32(texture.pixel_format),              // GLenum format,
        gl.UNSIGNED_BYTE,                       // GLenum type,
        data,                                // const void * data);
    );

    err := gl.GetError();
    if (err != gl.NO_ERROR) {
        DebugLog(
            "ERROR uploading texture - %d, %d, %d, %d - %d", 
            texture.internal_pixel_format,
            texture.width,
            texture.height,
            texture.pixel_format,
            err,
        );
        panic("xd");
    }
}

Texture_FromImage :: proc(image: ^Image) -> ^Texture {
    texture := new_clone(texture_config_default);
    gl.GenTextures(1, &texture.handle);
    
    Texture_Upload(texture, image.width, image.height, image.num_channels, image.data);
    Texture_ApplySettings(texture);
    
    gl.BindTexture(gl.TEXTURE_2D, 0);
    return texture;
}

Texture_FromSize ::  proc(width, height: int) -> ^Texture {
    texture := new_clone(texture_config_default);
    gl.GenTextures(1, &texture.handle);

    Texture_Upload(texture, width, height, 4, nil);
    Texture_ApplySettings(texture);

    gl.BindTexture(gl.TEXTURE_2D, 0);
    return texture;
}

Texture_Use :: proc(texture: ^Texture) {
    gl.BindTexture(gl.TEXTURE_2D, texture.handle);
}

@(private)
Texture_SetTextureUnit :: proc(unit: int){
    gl.ActiveTexture(u32(unit));
}

// NOTE: this will change the currently bound OpenGL texture
Texture_UpdateSubRegion :: proc(texture: ^Texture, rowPx, columnPx: int, sub_image: ^Image) {
    Texture_Use(texture);

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
    );
}

Texture_Free :: proc(texture: ^Texture) {
    gl.DeleteTextures(1, &texture.handle);
    free(texture)
}

Texture_Resize :: proc(texture: ^Texture, width, height: int) {
    if (texture.width == width && texture.height == height) {
        return;
    }

    Texture_Upload(texture, width, height, 4, nil);
}