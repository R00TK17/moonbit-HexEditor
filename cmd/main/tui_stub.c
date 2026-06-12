// Terminal UI stubs for the hex editor TUI
// Windows: conio + Virtual Terminal Processing
// Linux:   termios raw mode (persistent) + alternate screen
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#else
#include <termios.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <signal.h>

// Saved terminal state for restoration on exit
static struct termios saved_term;
static int term_saved = 0;
static int alt_screen_active = 0;

// Restore terminal to original settings (signal-safe)
static void restore_terminal(void) {
    if (alt_screen_active) {
        if (write(STDOUT_FILENO, "\033[?1049l", 8)) {}
        alt_screen_active = 0;
    }
    if (write(STDOUT_FILENO, "\033[?25h", 6)) {} // show cursor
    if (term_saved) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_term);
        term_saved = 0;
    }
}

// Signal handler: restore terminal then re-raise
static void signal_handler(int sig) {
    restore_terminal();
    signal(sig, SIG_DFL);
    raise(sig);
}

static void setup_terminal_handlers(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);
    signal(SIGQUIT, signal_handler);
}
#endif

// ====== Windows ANSI support ======
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

// ====== Alternate screen buffer ======
void tui_enter_alt_screen(void) {
#ifdef _WIN32
    enable_ansi();
    printf("\033[?1049h");
#else
    if (write(STDOUT_FILENO, "\033[?1049h", 8) < 0) {}
    alt_screen_active = 1;
#endif
    fflush(stdout);
}

void tui_exit_alt_screen(void) {
#ifdef _WIN32
    printf("\033[?1049l");
#else
    if (write(STDOUT_FILENO, "\033[?1049l", 8) < 0) {}
    alt_screen_active = 0;
#endif
    fflush(stdout);
}

// ====== Persistent raw mode (Linux) ======
#ifndef _WIN32
void tui_enter_raw(void) {
    struct termios newt;
    if (tcgetattr(STDIN_FILENO, &saved_term) != 0) return;
    term_saved = 1;
    setup_terminal_handlers();

    newt = saved_term;
    newt.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
    newt.c_oflag &= ~(OPOST);
    newt.c_lflag &= ~(ICANON | ECHO | ISIG | IEXTEN);
    newt.c_cc[VMIN] = 1;
    newt.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
}

void tui_exit_raw(void) {
    restore_terminal();
}
#else
void tui_enter_raw(void) { enable_ansi(); }
void tui_exit_raw(void) {}
#endif

// ====== Key input ======
int tui_get_key(void) {
#ifdef _WIN32
    enable_ansi();
    // Poll with _kbhit for ~100ms, then return -10 if no key
    for (int i = 0; i < 10; i++) {
        if (_kbhit()) {
            int c = _getch();
            if (c == 0 || c == 0xE0) {
                int c2 = _getch();
                switch (c2) {
                    case 72: return -1; case 80: return -2;
                    case 75: return -3; case 77: return -4;
                    case 73: return -5; case 81: return -6;
                    case 71: return -7; case 79: return -8;
                    case 83: return -9;
                    default: break;
                }
            }
            return c;
        }
        Sleep(10);
    }
    return -10;  // timeout: no key, check resize
#else
    // Use select() with 100ms timeout for the initial read
    fd_set fds;
    struct timeval tv;
    FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
    tv.tv_sec = 0; tv.tv_usec = 100000;  // 100ms
    if (select(1, &fds, NULL, NULL, &tv) <= 0) return -10;  // timeout

    char c_byte;
    int n = read(STDIN_FILENO, &c_byte, 1);
    if (n != 1) return -10;
    int c = (int)(unsigned char)c_byte;

    if (c == 27) {
        // Check for more bytes in the escape sequence
        FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
        tv.tv_sec = 0; tv.tv_usec = 50000;  // 50ms for sequence
        if (select(1, &fds, NULL, NULL, &tv) > 0) {
            char seq[8];
            ssize_t nseq = read(STDIN_FILENO, seq, sizeof(seq));
            if (nseq < 0) nseq = 0;
            if (nseq >= 1) {
                if (seq[0] == '[' && nseq >= 2) {
                    if (nseq == 2 && seq[1] >= 'A' && seq[1] <= 'Z') {
                        switch (seq[1]) {
                            case 'A': return -1; case 'B': return -2;
                            case 'C': return -4; case 'D': return -3;
                            case 'H': return -7; case 'F': return -8;
                            default: break;
                        }
                    }
                    if (seq[1] >= '0' && seq[1] <= '9') {
                        int num = seq[1] - '0';
                        int pos = 2;
                        while (pos < nseq && seq[pos] >= '0' && seq[pos] <= '9') {
                            num = num * 10 + (seq[pos] - '0'); pos++;
                        }
                        if (pos < nseq && seq[pos] == '~') {
                            switch (num) {
                                case 1: case 7: return -7;
                                case 2: case 3: return -9;
                                case 4: case 8: return -8;
                                case 5: return -5; case 6: return -6;
                                default: break;
                            }
                        }
                    }
                } else if (seq[0] == 'O' && nseq >= 2) {
                    switch (seq[1]) {
                        case 'A': return -1; case 'B': return -2;
                        case 'C': return -4; case 'D': return -3;
                        case 'H': return -7; case 'F': return -8;
                        default: break;
                    }
                }
            }
            return 27;
        }
    }

    return c;
#endif
}

// ====== Terminal size ======
int tui_get_terminal_rows(void) {
#ifdef _WIN32
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi))
        return csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
    return 0;
#else
    struct winsize ws = {0};
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_row > 0) return ws.ws_row;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_row > 0) return ws.ws_row;
    char *env = getenv("LINES");
    if (env) { int n = atoi(env); if (n > 0 && n <= 200) return n; }
    return 0;
#endif
}

// ====== Screen control ======
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

void raw_print(const char* s) {
#ifdef _WIN32
    printf("%s", s);
    fflush(stdout);
#else
    // Use write() directly in raw mode — avoids stdio buffering
    // that can rearrange output with large buffers
    size_t len = 0;
    while (s[len]) len++;
    if (write(STDOUT_FILENO, s, len) < 0) {}
#endif
}
