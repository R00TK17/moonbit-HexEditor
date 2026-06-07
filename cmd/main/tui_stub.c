// Terminal UI stubs for the hex editor TUI
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#else
#include <termios.h>
#include <unistd.h>
#include <sys/time.h>
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
    // Unix: use termios for non-canonical, no-echo mode
    struct termios oldt, newt;
    if (tcgetattr(STDIN_FILENO, &oldt) != 0) return getchar();
    newt = oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    newt.c_cc[VMIN] = 1;
    newt.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &newt) != 0) {
        // Fallback if can't set terminal mode
        return getchar();
    }

    int c = getchar();

    if (c == 27) {
        // Check for escape sequence
        fd_set fds;
        struct timeval tv;
        FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
        tv.tv_sec = 0; tv.tv_usec = 150000; // 150ms for first byte after ESC
        if (select(1, &fds, NULL, NULL, &tv) > 0) {
            int c2 = getchar();
            if (c2 == '[') {
                FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
                tv.tv_sec = 0; tv.tv_usec = 100000; // 100ms
                if (select(1, &fds, NULL, NULL, &tv) > 0) {
                    int c3 = getchar();
                    if (c3 >= '0' && c3 <= '9') {
                        int num = c3 - '0';
                        FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
                        tv.tv_sec = 0; tv.tv_usec = 80000;
                        if (select(1, &fds, NULL, NULL, &tv) > 0) {
                            int c4 = getchar();
                            if (c4 >= '0' && c4 <= '9') {
                                num = num * 10 + (c4 - '0');
                                FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
                                tv.tv_sec = 0; tv.tv_usec = 80000;
                                if (select(1, &fds, NULL, NULL, &tv) > 0) {
                                    getchar();
                                }
                            }
                        }
                        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
                        switch (num) {
                            case 5: return -5; case 6: return -6;
                            case 2: case 3: return -9;
                            case 1: case 7: return -7;
                            case 4: case 8: return -8;
                            default: break;
                        }
                    } else {
                        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
                        switch (c3) {
                            case 'A': return -1; case 'B': return -2;
                            case 'C': return -4; case 'D': return -3;
                            case 'H': return -7; case 'F': return -8;
                            default: break;
                        }
                    }
                }
            } else if (c2 == 'O') {
                FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
                tv.tv_sec = 0; tv.tv_usec = 100000;
                if (select(1, &fds, NULL, NULL, &tv) > 0) {
                    int c3 = getchar();
                    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
                    switch (c3) {
                        case 'A': return -1; case 'B': return -2;
                        case 'C': return -4; case 'D': return -3;
                        case 'H': return -7; case 'F': return -8;
                        default: break;
                    }
                }
            }
        }
    }

    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    return c;
#endif
}

void tui_clear_screen(void) {
#ifdef _WIN32
    enable_ansi();
#endif
    printf("\033[2J\033[H");
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
