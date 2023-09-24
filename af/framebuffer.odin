package af

import "core:c"
import "core:strings"
import gl "vendor:OpenGL"

Framebuffer :: struct  {
    framebuffer_handle: c.uint,
    renderbuffer_handle: c.uint,
    texture: ^Texture
}


Framebuffer_MakeFromTexture :: proc(texture: ^Texture) -> ^Framebuffer {
    framebuffer := new(Framebuffer)

    framebuffer.texture = texture
    gl.GenFramebuffers(1, &framebuffer.framebuffer_handle);
    gl.GenRenderbuffers(1, &framebuffer.renderbuffer_handle);

    Framebuffer_Resize(framebuffer, texture.width, texture.height);
    return framebuffer;
}

Framebuffer_Resize :: proc(fb: ^Framebuffer, width, height: int) {
    Framebuffer_Use(fb);

    Texture_Resize(fb.texture, width, height);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fb.texture.handle, 0);
    gl.BindRenderbuffer(gl.RENDERBUFFER, fb.renderbuffer_handle);
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, c.int(width), c.int(height));
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, fb.renderbuffer_handle);

    fb_status := gl.CheckFramebufferStatus(gl.FRAMEBUFFER);
    if (fb_status != gl.FRAMEBUFFER_COMPLETE) {
        // https://registry.khronos.org/OpenGL-Refpages/gl.4/html/gl.CheckFramebufferStatus.xhtml
        DebugLog("ERROR while resizing framebuffer - gl.CheckFramebufferStatus(gl.FRAMEBUFFER) = %d", fb_status);
        panic("error")
    } 

    Framebuffer_StopUsing();
}

Framebuffer_Use :: proc(fb: ^Framebuffer) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, fb.framebuffer_handle);
}

Framebuffer_StopUsing :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
}

Framebuffer_Free :: proc(fb: ^Framebuffer) {
    Texture_Free(fb.texture);
    gl.DeleteRenderbuffers(1, &fb.renderbuffer_handle);
    gl.DeleteFramebuffers(1, &fb.framebuffer_handle);

    free(fb)
}