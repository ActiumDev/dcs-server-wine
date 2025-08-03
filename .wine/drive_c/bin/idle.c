// x86_64-w64-mingw32-gcc -pipe -Wall -mwindows -Os -nostdlib -nolibc -nostartfiles -ffreestanding -ffunction-sections -fdata-sections -Wl,--file-alignment=16,--section-alignment=16,--gc-sections,--strip-all idle.c -o idle -lkernel32

#include <windows.h>

void _start(void) {
	while (1) {
		Sleep(MAXDWORD);
	}
}
