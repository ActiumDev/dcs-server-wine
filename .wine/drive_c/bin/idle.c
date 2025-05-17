// x86_64-w64-mingw32-gcc -pipe -Wall -mconsole -Os -s -nostdlib -nolibc -nostartfiles -ffreestanding -ffunction-sections -fdata-sections -Wl,--file-alignment=512,--gc-sections,--print-gc-sections idle.c -o idle -lkernel32

#include <windows.h>

void _start(void) {
	while (1) {
		Sleep(MAXDWORD);
	}
	ExitProcess(0);
}
