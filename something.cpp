// A file from my pure C port that I abandoned in favour of Odin. I am using it as a reference. 
// TODO: delete this file

#include "af.h"

#define M_PI		3.14159265358979323846

double GetTime() {
    return glfwGetTime();
}

void SetTime(double t) {
    glfwSetTime(t);
}

GLFWwindow *window;
int target_fps;
double last_frame_time;
double delta_time;

void internal_SetTextureDirectly(Texture *texture);
void internal_UseFramebufferDirectly(Framebuffer *framebuffer);

void glfw_key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    if (action == GLFW_RELEASE) return;
    if (static_keys_just_pressed_or_repeated_count >= KEY_LAST) {
        DebugLog("WARNING - key input buffer is full");
        return;
    }

    static_keys_just_pressed_or_repeated[static_keys_just_pressed_or_repeated_count] = key;
    static_keys_just_pressed_or_repeated_count++;
}

void glfw_character_callback(GLFWwindow* window, unsigned int codepoint) {
    if (static_keys_just_pressed_or_repeated_count >= KEY_LAST) {
        DebugLog("WARNING - text buffer is full");
        return;
    }

    static_chars_just_inputted[static_chars_just_inputted_count] = codepoint;
    static_chars_just_inputted_count++;
}


int AFInitialize(int width, int height, const char *window_title) {
    int glfw_init_result = glfwInit();
    if (!glfw_init_result) {
        printf("glfw failed to initialize - %d", glfw_init_result);
        return -1;
    }

    window = glfwCreateWindow(width, height, window_title, NULL, NULL);
    if (!window) {
        printf("glfw failed to create a window - %d", glfw_init_result);
        glfwTerminate();
        return -1;
    }

    glfwSetScrollCallback(window, glfw_scroll_callback);
    glfwSetKeyCallback(window, glfw_key_callback);
    glfwSetCharCallback(window, glfw_character_callback);
    glfwSetFramebufferSizeCallback(window, glfw_framebuffer_size_callback);

    /* Make the window's context current */
    glfwMakeContextCurrent(window);

    int glew_init_result = glewInit();
    if (glew_init_result != GLEW_OK) {
        printf("glew failed to initialize - %d", glew_init_result);
        return -1;
    }

    internal_InitRendering();
    Text_Init();
    return 0;
}

void AFDeinitialize() {
    internal_DeinitRendering();
    glfwTerminate();
}

float VW() {
    return Rect_GetWidth(&layout_rect);
}

float VH() {
    return Rect_GetHeight(&layout_rect);
}


void SetTargetFPS(int fps) {
    target_fps = fps;
}

bool WindowShouldClose() {
    return glfwWindowShouldClose(window);
}

void BeginFrame() {
    internal_UpdateKeyInputsBeforePoll();
    glfwPollEvents();
    internal_UpdateMouseInput();

    glfwGetWindowSize(window, &window_width, &window_height);

    Mat4 m = Mat4_Identity();
    SetTransform(&m);
    internal_SetTextureDirectly(NULL);
    internal_UseFramebufferDirectly(NULL);

    SetLayoutRect(GetDefaultLayoutRect(), false);
}

void EndFrame(){
    Flush();
    UseFramebuffer(NULL);
    glfwSwapBuffers(window);

    double frame_end = GetTime();
    delta_time = frame_end - last_frame_time;

    if (!target_fps) {
        last_frame_time = frame_end;
        return;
    }

    // This is a power saving mechanism that will sleep the thread if we
    // have the time available to do so. It should reduce the overall CPU consumption.

    double frame_duration = 1.0 / (double)target_fps;
    double time_to_next_frame = frame_duration - delta_time;
    if (time_to_next_frame > 0.0) {
        struct timespec remaining;
        struct timespec requested = {
            .tv_sec = (long)trunc(time_to_next_frame),
            .tv_nsec = (long)(time_to_next_frame * 1000000000)
        };

        // TODO: handle error?
        nanosleep(&requested, &remaining); 
        frame_end = GetTime();
        delta_time = frame_end - last_frame_time;
    }

    last_frame_time = frame_end;
}

// -------- Keyboard input --------

const char* KEYBOARD_CHARS = "\t\b\n `1234567890-=qwertyuiop[]asdfghjkl;'\\zxcvbnm,./";

int static_keys_just_pressed_or_repeated[KEY_LAST];
int static_keys_previous_state[KEY_LAST];
unsigned int static_keys_just_pressed_or_repeated_count = 0;

unsigned int static_chars_just_inputted[KEY_LAST];
unsigned int static_chars_just_inputted_count = 0;

int is_any_down = 0;
int was_any_down = 0;

bool KeyWasDown(int key) {
    if (key == KEY_CTRL) {
        return KeyWasDown(KEY_LEFT_CTRL) || KeyWasDown(KEY_RIGHT_CTRL);
    }
    if (key == KEY_SHIFT) {
        return KeyWasDown(KEY_LEFT_SHIFT) || KeyWasDown(KEY_RIGHT_SHIFT);
    }
    if (key == KEY_ALT) {
        return KeyWasDown(KEY_LEFT_ALT) || KeyWasDown(KEY_RIGHT_ALT);
    }
    if (key == KEY_ANY) {
        return was_any_down;
    }
    if (key == KEY_UNKNOWN) {
        return 0;
    }
    return static_keys_previous_state[key];
}

bool KeyIsDown(int key) {
    if (key == KEY_CTRL) {
        return KeyIsDown(KEY_LEFT_CTRL) || KeyIsDown(KEY_RIGHT_CTRL);
    }
    if (key == KEY_SHIFT) {
        return KeyIsDown(KEY_LEFT_SHIFT) || KeyIsDown(KEY_RIGHT_SHIFT);
    }
    if (key == KEY_ALT) {
        return KeyIsDown(KEY_LEFT_ALT) || KeyIsDown(KEY_RIGHT_ALT);
    }
    if (key == KEY_ANY) {
        return is_any_down;
    }
    if (key == KEY_UNKNOWN) {
        return 0;
    }

    return glfwGetKey(window, key) == GLFW_PRESS;
}

bool KeyJustPressed(int key) {
    return (!KeyWasDown(key)) && (KeyIsDown(key));
}

bool KeyJustReleased(int key) {
    return KeyWasDown(key) && (!KeyIsDown(key));
}

void internal_UpdateKeyInputsBeforePoll() {
    static_keys_just_pressed_or_repeated_count = 0;
    static_chars_just_inputted_count = 0;

    was_any_down = is_any_down;
    is_any_down = 0;
    for(int i = 0; i < KEY_LAST; i++) {
        static_keys_previous_state[i] = KeyIsDown(i);
    }
}


// -------- Mouse input --------

float incoming_mouse_wheel_notches = 0;
float mouse_wheel_notches = 0;

bool prev_mouse_button_states[NUM_MOUSE_BUTTONS];
bool mouse_button_states[NUM_MOUSE_BUTTONS];
bool mouse_was_any_down = 0;
bool mouse_any_down = 0;

Vec2 internal_prev_mouse_position;
Vec2 internal_mouse_position;
Vec2 mouse_delta;

//Mainly used to tell if we started dragging or not, and 
//not meant to be an accurate representation of total distance dragged
float GetMouseScroll() {
    return mouse_wheel_notches;
}

// we are kinda just assuming these are 0, 1, 2

bool MouseButtonIsDown(int b) {
    return mouse_button_states[(int)b];
}

bool MouseButtonWasDown(int b) {
    return prev_mouse_button_states[(int)b];
}

bool MouseButtonJustPressed(int b) {
    return !MouseButtonWasDown(b) && MouseButtonIsDown(b);
}

bool MouseButtonJustReleased(int b) {
    return MouseButtonWasDown(b) && !MouseButtonIsDown(b);
}

Vec2 GetMousePos() {
    return Vec2_New(
        internal_mouse_position.x - layout_rect.x0,
        internal_mouse_position.y - layout_rect.y0
    );
}

void SetMousePosition(Vec2 pos) {
    double x = (double)pos.x;
    double y = (double)pos.y;
    glfwSetCursorPos(window, x, y);
}

Vec2 GetMouseDelta() {
    return mouse_delta;
}

void glfw_scroll_callback(GLFWwindow* window, double xoffset, double yoffset) {
    incoming_mouse_wheel_notches += (float)xoffset;
}

bool MouseIsOver(Rect *rect) {
    Vec2 pos = GetMousePos();
    float x = pos.x;
    float y = pos.y;

    float left = Rect_GetLeft(rect);
    float right = Rect_GetRight(rect);
    float top = Rect_GetTop(rect);
    float bottom = Rect_GetBottom(rect);

    return (x > left && x < right) && (y < top && y > bottom);
}

void internal_UpdateMouseInput() {
    for(int i = 0; i < NUM_MOUSE_BUTTONS; i++) {
        prev_mouse_button_states[i] = mouse_button_states[i];
    }

    mouse_wheel_notches = incoming_mouse_wheel_notches;
    incoming_mouse_wheel_notches = 0;

    mouse_was_any_down = mouse_any_down;
    mouse_any_down = false;
    for (int i = 0; i < NUM_MOUSE_BUTTONS; i++) {
        int state = glfwGetMouseButton(window, i);
        mouse_button_states[i] = state;
        mouse_any_down = mouse_any_down || state;
    }

    internal_prev_mouse_position = internal_mouse_position;
    double x, y;
    glfwGetCursorPos(window, &x, &y);
    internal_mouse_position.x = (float)x;
    internal_mouse_position.y = window_height - (float)y;
    mouse_delta.x = internal_mouse_position.x - internal_prev_mouse_position.x;
    mouse_delta.y = internal_mouse_position.y - internal_prev_mouse_position.y;
}

// -------- Drawing to the screen --------

int framebuffer_width = 0, framebuffer_height = 0;
// used to restore framebuffer_width/height to the correct value after we
// stop using a framebuffer
int window_width = 0, window_height = 0;  
Rect layout_rect;
Texture *current_texture = NULL; 
Texture white_pixel_texture; // TODO: free white_pixel_texture at some point
Framebuffer *current_framebuffer = NULL;
AFShader internal_shader, *current_shader;
BufferedMeshOutput output;
Color draw_color;
Mat4 transform, view, projection;

void internal_OnFramebufferResize(int width, int height) {
    framebuffer_width = width; 
    framebuffer_height = height;
    
    SetLayoutRect(GetDefaultLayoutRect(), false);
    glViewport(0, 0, width, height);
}

void glfw_framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    window_width = width;
    window_height = height;

    internal_OnFramebufferResize(width, height);
}

Rect GetDefaultLayoutRect() {
    Rect r = { .x0 = 0, .y0 = 0, .x1 = framebuffer_width, .y1 = framebuffer_height };
    return r;
}

void SetLayoutRect(Rect rect, bool clip) {
    Flush();
    layout_rect = rect;

    if (clip) {
        glScissor((int)layout_rect.x0,  (int)layout_rect.y0,
            (int)Rect_GetWidth(&layout_rect), 
            (int)Rect_GetHeight(&layout_rect));

        glEnable(GL_SCISSOR_TEST);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }

    SetViewProjection_Cartesian2D(rect.x0, rect.y0, 1, 1);
}

void internal_InitRendering() {
    // init opengl things
    {
        output = BufferedMeshOutput_Allocate(2000, 6000);
        internal_shader = AFShader_NewInternalShader();
        SetCurrentShader(&internal_shader);

        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glEnable(GL_STENCIL_TEST);
        glStencilFunc(GL_EQUAL, 0, 0xFF);

        glEnable(GL_DEPTH_TEST);    

        char buffer[1024];
        sprintf(buffer, "Context initialized. OpenGL info: %s, Version: %s", glGetString(GL_VENDOR), glGetString(GL_VERSION));
        DebugLog(buffer);

        SetBackfaceCulling(false);
    }

    // init texturing 
    {
        Image img;
        img.width = 1;
        img.height = 1;
        img.num_channels = 4;

        unsigned char data[4];
        img.data = data;
        data[0] = 0xFF; data[1] = 0xFF; data[2] = 0xFF; data[3] = 0xFF;
        white_pixel_texture = Texture_FromImage(&img);
        white_pixel_texture.filtering = GL_NEAREST;
        Texture_ApplySettings(&white_pixel_texture);
    }
}


void internal_DeinitRendering() {
    // TODO: 
    AFShader_Free(&internal_shader);
    BufferedMeshOutput_Free(&output);
    Texture_Free(&white_pixel_texture);
}


void internal_SetTextureDirectly(Texture *texture) {
    if (texture == NULL) {
        texture = &white_pixel_texture;
    }

    Texture_SetTextureUnit(GL_TEXTURE0);
    Texture_Use(texture);
    current_texture = texture;
}

void SetTexture(Texture *texture) {
    if (texture == current_texture) {
        return;
    }

    Flush();

    internal_SetTextureDirectly(texture);
}

Texture *GetTexture() {
    return current_texture;
}

void ClearScreen(Color col) {
    glStencilMask(1);
    glClearColor(col.r, col.g, col.b, col.a);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
}

void Flush() {
    BufferedMeshOutput_Flush(&output);
}

void SetViewProjection_Cartesian2D(float x, float y, float sx, float sy) {
    Flush();

    float width = sx * framebuffer_width;
    float height = sy * framebuffer_height;

    Vec3 translation = { .x = x - width / 2.f, .y = y - height / 2.f, .z = 0};
    Mat4 view = Mat4_Translation(translation);
    Mat4 projection = Mat4_Identity();
    Mat4_ScaleAniso(&projection, 2.0f / width, 2.0f / height, 1);

    SetView(&view);
    SetProjection(&projection);

    glDepthFunc(GL_LEQUAL);
}

void SetView_LookAt(Vec3 position, Vec3 target, Vec3 up) {
    Mat4 lookAt = Mat4_LookAt(position, target, up);
    SetView(&lookAt);
}

void SetView_Orientation(Vec3 position, Quat rotation) {
    Mat4 view = Mat4_FromQuat(&rotation);
    Mat4_TranslateInPlace(&view, position);
    SetView(&view);
}

static void internal_SetProjection_Perspective(float fovy, float aspect, float depth_near, float depth_far, float center_x, float center_y) {
    Mat4 projection = Mat4_Perspective(fovy, aspect, depth_near, depth_far);
    Vec3 screenCenter = { .x = center_x / VW(),  .y = center_y / VH(),  .z = 0 };
    Mat4_TranslateInPlace(&projection, screenCenter);

    Mat4 scale = Mat4_Identity();
    Mat4_ScaleAniso(&scale, -1, 1, 1);
    projection = Mat4_Mul(&projection, &scale);

    SetProjection(&projection);
}

void SetProjection_Perspective(float fovy, float aspect, float depth_near, float depth_far) {
    // is inferring the aspect a mistake ? not sure
    internal_SetProjection_Perspective(
        fovy, aspect, depth_near, depth_far,
        layout_rect.x0 + VW() * 0.5f - framebuffer_width * 0.5f,
        layout_rect.y0 + VH() * 0.5f - framebuffer_height * 0.5f
    );
}

static void internal_SetProjection_Orthographic(float width, float height, float depth_near, float depth_far, float center_x, float center_y) {
    Mat4 projection = Mat4_Ortho(center_x - width * 0.5f, center_x + width * 0.5f, 
        center_y - 0.5f * height, center_y + 0.5f * height, depth_near, depth_far);

    Mat4 scale = Mat4_Identity(); Mat4_ScaleAniso(&scale, -1, 1, 1);
    projection = Mat4_Mul(&projection, &scale);

    SetProjection(&projection);
}

void SetProjection_Orthographic(float width, float height, float depth_near, float depth_far) {
    internal_SetProjection_Orthographic(
        width, height, depth_near, depth_far,
        2.f * layout_rect.x0 + VW() - framebuffer_width,
        2.f * layout_rect.y0 + VH() - framebuffer_height
    );
}

void SetProjection(const Mat4 *matrix) {
    Flush();

    projection = *matrix;
    Shader_SetMatrix4(current_shader->projection, projection);
}

void SetTransform(const Mat4 *matrix) {
    Flush();

    transform = *matrix;
    Shader_SetMatrix4(current_shader->transform, transform);
}

void SetView(const Mat4 *matrix) {
    Flush();

    view = *matrix;
    Shader_SetMatrix4(current_shader->view, view);
}

void SetDrawColor(Color color) {
    Flush();

    draw_color = color;
    Shader_SetColor4(current_shader->color, draw_color);
}

void SetCurrentShader(AFShader *shader) {
    if (shader == NULL) {
        shader = &internal_shader;
    }

    Flush();

    current_shader = shader;
    internal_Shader_Use(&current_shader->shader);
    Shader_SetMatrix4(current_shader->transform, transform);
    Shader_SetMatrix4(current_shader->view, transform);
    Shader_SetMatrix4(current_shader->projection, projection);   
}

AFShader *GetCurrentShader() {
    return current_shader;
}

void SetBackfaceCulling(bool state) {
    Flush();

    if(state) {
        glEnable(GL_CULL_FACE);
    } else {
        glDisable(GL_CULL_FACE);
    }
}


void StartStencilling(bool canDraw, bool inverseStencil) {
    Flush();

    if (!canDraw) {
        glColorMask(false, false, false, false);
    }

    if (inverseStencil) {
        glClearStencil(1);
    } else {
        glClearStencil(0);
    }

    glStencilMask(1);
    glClear(GL_STENCIL_BUFFER_BIT);

    glEnable(GL_STENCIL_TEST);
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

    if (inverseStencil) {
        glStencilFunc(GL_ALWAYS, 0, 0);
    } else {
        glStencilFunc(GL_ALWAYS, 1, 1);
    }
}

void StartUsingStencil() {
    Flush();

    glColorMask(true, true, true, true);
    glStencilFunc(GL_NOTEQUAL, 1, 1);
    glStencilMask(0);
}


void LiftStencil() {
    Flush();

    glDisable(GL_STENCIL_TEST);
}

void internal_UseFramebufferDirectly(Framebuffer *framebuffer) {
    current_framebuffer = framebuffer;

    if (framebuffer == NULL) {
        Framebuffer_StopUsing();
        internal_OnFramebufferResize(window_width, window_height);
    } else {
        Framebuffer_Use(framebuffer);
        internal_OnFramebufferResize(framebuffer->texture.width, framebuffer->texture.height);
    }
}

void UseFramebuffer(Framebuffer *framebuffer) {
    if (current_framebuffer == framebuffer) {
        return;
    }

    Flush();

    internal_UseFramebufferDirectly(framebuffer);
}

// ---- 2D immediate mode

AFVertex NewVertex(float x, float y) {
    AFVertex v = {
        .position = { .x = x, .y = y, .z = 0.f },
        .uv = { .x = x, .y = y },
    };
    return v;
}

AFVertex NewVertexUV(float x, float y, float u, float v) {
    AFVertex vertex = {
        .position = { .x = x, .y = y, .z = 0.f },
        .uv = { .x = u, .y = v },
    };
    return vertex;
}

void DrawTriangle(AFVertex v1, AFVertex v2, AFVertex v3) {
    BufferedMeshOutput_FlushIfNotEnoughRoom(&output, 3, 3);

    unsigned int v1_index = BufferedMeshOutput_AddVertex(&output, v1);
    unsigned int v2_index = BufferedMeshOutput_AddVertex(&output, v2);
    unsigned int v3_index = BufferedMeshOutput_AddVertex(&output, v3);

    BufferedMeshOutput_MakeTriangle(&output, v1_index, v2_index, v3_index);
}

void DrawTriangleOutline(AFVertex v1, AFVertex v2, AFVertex v3, float thickness) {
    Vec3 mean = Vec3_Scale(
        Vec3_Add(Vec3_Add(v1.position, v2.position), v3.position),
        1.f / 3.f
    );

    AFVertex v1_outer = v1;
    v1_outer.position = Vec3_Add(
        v1.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v1.position, mean)), thickness)
    );
    AFVertex v2_outer = v2;
    v2_outer.position = Vec3_Add(
        v2.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v2.position, mean)), thickness)
    );
    AFVertex v3_outer = v3;
    v3_outer.position = Vec3_Add(
        v3.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v3.position, mean)), thickness)
    );

    NLine line = NLine_Start(&output);
    NLine_Extend(&line, v1, v1_outer);
    NLine_Extend(&line, v2, v2_outer);
    NLine_Extend(&line, v3, v3_outer);
    NLine_Extend(&line, v1, v1_outer);
}

void DrawQuad(AFVertex v1, AFVertex v2, AFVertex v3, AFVertex v4) {
    BufferedMeshOutput_FlushIfNotEnoughRoom(&output, 4, 6);

    unsigned int v1_index = BufferedMeshOutput_AddVertex(&output, v1);
    unsigned int v2_index = BufferedMeshOutput_AddVertex(&output, v2);
    unsigned int v3_index = BufferedMeshOutput_AddVertex(&output, v3);
    unsigned int v4_index = BufferedMeshOutput_AddVertex(&output, v4);

    BufferedMeshOutput_MakeQuad(&output, v1_index, v2_index, v3_index, v4_index);
}

void DrawQuadOutline(AFVertex v1, AFVertex v2, AFVertex v3, AFVertex v4, float thickness) {
    Vec3 mean = Vec3_Scale(
        Vec3_Add(Vec3_Add(Vec3_Add(v1.position, v2.position), v3.position), v4.position),
        1.f / 4.f
    );

    AFVertex v1_outer = v1;
    v1_outer.position = Vec3_Add(
        v1.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v1.position, mean)), thickness)
    );
    AFVertex v2_outer = v2;
    v2_outer.position = Vec3_Add(
        v2.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v2.position, mean)), thickness)
    );
    AFVertex v3_outer = v3;
    v3_outer.position = Vec3_Add(
        v3.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v3.position, mean)), thickness)
    );
    AFVertex v4_outer = v4;
    v4_outer.position = Vec3_Add(
        v4.position , 
        Vec3_Scale(Vec3_Normalize(Vec3_Sub(v4.position, mean)), thickness)
    );

    NLine line = NLine_Start(&output);
    NLine_Extend(&line, v1, v1_outer);
    NLine_Extend(&line, v2, v2_outer);
    NLine_Extend(&line, v3, v3_outer);
    NLine_Extend(&line, v4, v4_outer);
    NLine_Extend(&line, v1, v1_outer);
}

void DrawRect(Rect rect) {
    AFVertex v1 = NewVertexUV(rect.x0, rect.y0, 0.f, 0.f);
    AFVertex v2 = NewVertexUV(rect.x0, rect.y1, 0.f, 1.f);
    AFVertex v3 = NewVertexUV(rect.x1, rect.y1, 1.f, 1.f);
    AFVertex v4 = NewVertexUV(rect.x1, rect.y0, 1.f, 0.f);

    DrawQuad(v1, v2, v3, v4);
}

void DrawRectOutline(Rect rect, float thickness) {
    float x0 = rect.x0;
    float y0 = rect.y0;
    float x1 = rect.x1;
    float y1 = rect.y1;

    Rect r1 = { .x0 = x0 - thickness, .y0 = y0 - thickness, .x1 = x1, .y1 = y0 };
    DrawRect(r1);
    Rect r2 = { .x0 = x0, .y0 = y1, .x1 = x1 + thickness, .y1 = y1 + thickness };
    DrawRect(r2);
    Rect r3 = { .x0 = x0 - thickness, .y0 = y0, .x1 = x0, .y1 = y1 + thickness };
    DrawRect(r3);
    Rect r4 = { .x0 = x1, .y0 = y0 - thickness, .x1 = x1 + thickness, .y1 = y1 };
    DrawRect(r4);
}

int GetEdgeCount(float radius, float angle, int maxCircleEdgeCount) {
    float deltaAngle = 1.0f / radius;
    int edgeCount = (int)((angle) / deltaAngle) + 1;

    if (edgeCount > maxCircleEdgeCount) {
        edgeCount = maxCircleEdgeCount;
    }

    return edgeCount;
}


void DrawArc(float xCenter, float yCenter, float radius, float startAngle, float endAngle, int edgeCount) {
    NGon ngon = NGon_Start(&output);
    AFVertex center = NewVertex(xCenter, yCenter);
    NGon_Extend(&ngon, center);

    float deltaAngle = (endAngle - startAngle) / (float)edgeCount;
    for (float angle = endAngle; angle > startAngle - deltaAngle + 0.001f; angle -= deltaAngle) {
        float x = xCenter + radius * sinf(angle);
        float y = yCenter + radius * cosf(angle);

        AFVertex v = NewVertex(x, y);
        NGon_Extend(&ngon, v);
    }
}

void DrawArcOutline(float xCenter, float yCenter, float radius, float startAngle, float endAngle, int edgeCount, float thickness) {
    if (edgeCount < 0)
        return;

    float deltaAngle = (endAngle - startAngle) / edgeCount;

    NLine nline = NLine_Start(&output);
    for (float angle = startAngle; angle < endAngle + deltaAngle - 0.001f; angle += deltaAngle) {
        float sinAngle = sinf(angle);
        float cosAngle = cosf(angle);
        float X1 = xCenter + radius * sinAngle;
        float Y1 = yCenter + radius * cosAngle;

        float X2 = xCenter + (radius + thickness) * sinAngle;
        float Y2 = yCenter + (radius + thickness) * cosAngle;

        AFVertex v1 = NewVertex(X1, Y1);
        AFVertex v2 = NewVertex(X2, Y2);
        NLine_Extend(&nline, v1, v2);
    }
}

void DrawCircle(float x0, float y0, float r, int edges) {
    DrawArc(x0, y0, r, 0, 2.0f * M_PI, edges);
}

void DrawCircleOutline(float x0, float y0, float r, int edges, float thickness) {
    DrawArcOutline(x0, y0, r, 0, 2.0f * M_PI, edges, thickness);
}

void DrawLine__DrawCap(float x0, float y0, float thickness, AFCapType cap_type, float angle) {
    switch (cap_type) {
    case CAP_TYPE_CIRCLE:
        DrawArc(x0, y0, thickness, angle, angle + M_PI, GetEdgeCount(thickness, M_PI, 512));    
        break;
    default:
        break;
    }
}

void DrawLine(float x0, float y0, float x1, float y1, float thickness, AFCapType cap_type) {
    thickness /= 2;

    float dirX = x1 - x0;
    float dirY = y1 - y0;
    float mag = sqrtf(dirX * dirX + dirY * dirY);

    float perpX = -thickness * dirY / mag;
    float perpY = thickness * dirX / mag;

    AFVertex v1 = NewVertex(x0 + perpX, y0 + perpY);
    AFVertex v2 = NewVertex(x0 - perpX, y0 - perpY);
    AFVertex v3 = NewVertex(x1 - perpX, y1 - perpY);
    AFVertex v4 = NewVertex(x1 + perpX, y1 + perpY);
    DrawQuad(v1, v2, v3, v4);

    float startAngle = atan2f(dirX, dirY) + M_PI / 2;
    DrawLine__DrawCap(x0, y0, thickness, cap_type, startAngle);
    DrawLine__DrawCap(x1, y1, thickness, cap_type, startAngle + M_PI);    
}

void DrawLineOutline__DrawCapOutline(float radius, float x0, float y0, float outlineThickness, AFCapType cap_type, float angle) {
    switch (cap_type) {
    case CAP_TYPE_CIRCLE:
        DrawArcOutline(x0, y0, radius, angle, angle + M_PI, GetEdgeCount(radius, M_PI, 512), outlineThickness);
        break;
    default:
        DrawArcOutline(x0, y0, radius, angle, angle + M_PI, 1, outlineThickness);
        break;
    }
}

void DrawLineOutline(float x0, float y0, float x1, float y1, float thickness, AFCapType cap_type, float outlineThickness) {
    thickness /= 2;

    float dirX = x1 - x0;
    float dirY = y1 - y0;
    float mag = sqrtf(dirX * dirX + dirY * dirY);

    float perpXInner = -(thickness) * dirY / mag;
    float perpYInner = (thickness) * dirX / mag;

    float perpXOuter = -(thickness + outlineThickness) * dirY / mag;
    float perpYOuter = (thickness + outlineThickness) * dirX / mag;

    // draw quad on one side of the line
    AFVertex vInner = NewVertexUV(
        x0 + perpXInner, y0 + perpYInner,
        perpXInner, perpYInner
    );
    AFVertex vOuter = NewVertexUV(
        x0 + perpXOuter, y0 + perpYOuter,
        perpXOuter, perpYOuter
    );
    AFVertex v1Inner = NewVertexUV(
        x1 + perpXInner, y1 + perpYInner,
        perpXInner, perpYInner
    );
    AFVertex v1Outer = NewVertexUV(
        x1 + perpXOuter, y1 + perpYOuter,
        perpXOuter, perpYOuter
    );
    DrawQuad(vInner, vOuter, v1Outer, v1Inner);

    // draw quad on other side of the line
    vInner = NewVertexUV(
        x0 - perpXInner, y0 - perpYInner,
        -perpXInner, -perpYInner
    );
    vOuter = NewVertexUV(
        x0 - perpXOuter, y0 - perpYOuter,
        perpXOuter, perpYOuter
    );
    v1Inner = NewVertexUV(
        x1 - perpXInner, y1 - perpYInner,
        -perpXInner, -perpYInner
    );
    v1Outer = NewVertexUV(
        x1 - perpXOuter, y1 - perpYOuter,
        -perpXOuter, -perpYOuter
    );
    DrawQuad(vInner, vOuter, v1Outer, v1Inner);

    // Draw both caps
    float startAngle = atan2f(dirX, dirY) + M_PI / 2;
    DrawLineOutline__DrawCapOutline(thickness, x0, y0, outlineThickness, cap_type, startAngle);
    DrawLineOutline__DrawCapOutline(thickness, x1, y1, outlineThickness, cap_type, startAngle + M_PI);
}
