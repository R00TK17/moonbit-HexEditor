// Terminal UI stubs for the hex editor TUI
#include <stdio.h>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#endif

// Enable ANSI escape codes on Windows 10+
#ifdef _WIN32
static int ansi_ok = 0;
static void enable_ansi(void) {
    if (ansi_ok) return;
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hOut != INVALID_HANDLE_VALUE) {
        DWORD dwMode = 0;
        if (GetConsoleMode(hOut, &dwMode)) {
            dwMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            SetConsoleMode(hOut, dwMode);
        }
    }
    ansi_ok = 1;
}
#endif

// Read a single key from stdin without echo.
// Returns char code, or negative for special keys:
//   -1=Up, -2=Down, -3=Left, -4=Right
//   -5=PgUp, -6=PgDn, -7=Home, -8=End, -9=Del
int tui_get_key(void) {
#ifdef _WIN32
    enable_ansi();
    int c = _getch();
    if (c == 0 || c == 0xE0) {
        int c2 = _getch();
        switch (c2) {
            case 72: return -1;   // Up
            case 80: return -2;   // Down
            case 75: return -3;   // Left
            case 77: return -4;   // Right
            case 73: return -5;   // PgUp
            case 81: return -6;   // PgDn
            case 71: return -7;   // Home
            case 79: return -8;   // End
            case 83: return -9;   // Del
            default: break;
        }
    }
    return c;
#else
    // Unix fallback: return getchar
    return getchar();
#endif
}

void tui_clear_screen(void) {
#ifdef _WIN32
    enable_ansi();
#endif
    printf("\033[2J\033[H");
    fflush(stdout);
}

void tui_goto(int row, int col) {
    printf("\033[%d;%dH", row, col);
    fflush(stdout);
}

void tui_hide_cursor(void) {
    printf("\033[?25l");
    fflush(stdout);
}

void tui_show_cursor(void) {
    printf("\033[?25h");
    fflush(stdout);
}

// Raw print - outputs bytes directly to stdout
void raw_print(const char* s) {
    printf("%s", s);
    fflush(stdout);
}
