#define FRAME_WIDTH 864
#define FRAME_HEIGHT 625

#include <stdlib.h>
#include <SDL.h>
#include <SDL_keycode.h>
#include "Vtop.h"

static int sdl_mod_to_usb_mod(int sdl_mod)
{
    int usb_mod = 0;

    if (sdl_mod & KMOD_LSHIFT)
        usb_mod |= 1 << 1;
    if (sdl_mod & KMOD_RSHIFT)
        usb_mod |= 1 << 5;
    if (sdl_mod & KMOD_LCTRL)
        usb_mod |= 1 << 0;
    if (sdl_mod & KMOD_RCTRL)
        usb_mod |= 1 << 4;
    return usb_mod;
}

int main(int argc, char *argv[])
{
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        "VZF (Simulation)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        FRAME_WIDTH, FRAME_HEIGHT,
        SDL_WINDOW_SHOWN
    );

    if (!window) {
        return EXIT_FAILURE;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer) {
        return 1;
    }

    SDL_Texture* texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_STREAMING,
        FRAME_WIDTH,
        FRAME_HEIGHT
    );

    Vtop* top = new Vtop;
    top->reset_n = 0;

    uint32_t image[FRAME_WIDTH*FRAME_HEIGHT];
    memset(image, 0, sizeof(image));

    int quit = 0;
    int old_vsync = 0;
    top->cx = 0;
    top->cy = 0;
    top->fdcemu_en = 1;
    top->frame_width = FRAME_WIDTH;
    top->frame_height = FRAME_HEIGHT;

    while (!quit) {
        top->vsync = !(top->cx >= 720 && top->cy >= 576);

        top->clk_pixel = 0;
        top->eval();

        top->clk_pixel = 1;
        top->eval();
        top->reset_n = 1;

        if (old_vsync && !top->vsync) {
            SDL_UpdateTexture(texture, nullptr, image, FRAME_WIDTH*4);
            SDL_RenderClear(renderer);
            SDL_RenderCopy(renderer, texture, nullptr, nullptr);
            SDL_RenderPresent(renderer);

            SDL_Event event;
            SDL_PollEvent(&event); /* only poll once */
            if (event.type == SDL_QUIT) {
                quit = true;
            } else if (event.type == SDL_KEYDOWN) {
                top->key_modifiers = sdl_mod_to_usb_mod(event.key.keysym.mod);
                top->key0 = event.key.keysym.scancode;
            } else if (event.type == SDL_KEYUP) {
                SDL_Scancode scancode = event.key.keysym.scancode;
                top->key_modifiers = sdl_mod_to_usb_mod(event.key.keysym.mod);
                top->key0 =  0;
            }
        }

        image[top->cy*FRAME_WIDTH + top->cx] = (top->rgb << 8) | 0xff;

        top->cx++;
        if (top->cx == FRAME_WIDTH) {
            top->cx = 0;
            top->cy++;
            if (top->cy == FRAME_HEIGHT) {
                top->cy=0;
            }
        }

        old_vsync = top->vsync;
    }

    top->final();
    delete top;

    return EXIT_SUCCESS;
}
