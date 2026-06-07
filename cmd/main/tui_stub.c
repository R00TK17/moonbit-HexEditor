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
#include <signal.h>

// Saved terminal state for signal-safe restoration
static struct termios saved_term;
static int term_saved = 0;

// Restore terminal to original settings
static void restore_terminal(void) {
    if (term_saved) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_term);
        term_saved = 0;
    }
}

// Signal handler: restore terminal then re-raise with default behavior.
// Uses write() instead of printf for async-signal-safety.
static void signal_handler(int sig) {
    restore_terminal();
    if (write(STDOUT_FILENO, "\033[?25h", 6)) {}
    signal(sig, SIG_DFL);
    raise(sig);
}

// Register signal handlers for clean terminal restoration on exit
static void setup_terminal_handlers(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);
    signal(SIGQUIT, signal_handler);
}
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
    // Unix: use termios for non-canonical, no-echo mode.
    // Use read() directly on the fd instead of getchar() to avoid stdio
    // buffering: stdio can pre-read extra bytes, hiding them from select().
    struct termios oldt, newt;
    char c_byte;
    if (tcgetattr(STDIN_FILENO, &oldt) != 0) {
        if (read(STDIN_FILENO, &c_byte, 1) == 1) return (int)(unsigned char)c_byte;
        return -1;
    }

    // Save terminal state for signal handlers (once)
    if (!term_saved) {
        saved_term = oldt;
        term_saved = 1;
        setup_terminal_handlers();
    }

    newt = oldt;
    // Disable: canonical mode, echo, signal generation (Ctrl+C/Z/\)
    newt.c_lflag &= ~(ICANON | ECHO | ISIG);
    // Disable: software flow control (Ctrl+S/Q), CR→NL mapping
    newt.c_iflag &= ~(IXON | ICRNL);
    // Disable: output post-processing (NL→CRNL mapping on output)
    newt.c_oflag &= ~(OPOST);
    newt.c_cc[VMIN] = 1;
    newt.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSANOW, &newt) != 0) {
        // Fallback if can't set terminal mode
        if (read(STDIN_FILENO, &c_byte, 1) == 1) return (int)(unsigned char)c_byte;
        return -1;
    }

    int c = read(STDIN_FILENO, &c_byte, 1) == 1 ? (int)(unsigned char)c_byte : -1;
    if (c < 0) { tcsetattr(STDIN_FILENO, TCSANOW, &oldt); return -1; }

    if (c == 27) {
        // ESC received — wait briefly to distinguish bare ESC from escape sequences.
        fd_set fds;
        struct timeval tv;
        FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
        tv.tv_sec = 0; tv.tv_usec = 100000;  // 100ms
        if (select(1, &fds, NULL, NULL, &tv) > 0) {
            // Read all available bytes of the escape sequence directly from
            // the fd (not stdio) to avoid stdio buffering hiding bytes from select().
            char seq[8];
            ssize_t n = read(STDIN_FILENO, seq, sizeof(seq));
            if (n < 0) n = 0;

            tcsetattr(STDIN_FILENO, TCSANOW, &oldt);

            // Parse the collected escape sequence
            if (n >= 1) {
                if (seq[0] == '[' && n >= 2) {
                    // ESC [ final-byte  (e.g. ESC [ A = Up)
                    if (n == 2 && seq[1] >= 'A' && seq[1] <= 'Z') {
                        switch (seq[1]) {
                            case 'A': return -1;  // Up
                            case 'B': return -2;  // Down
                            case 'C': return -4;  // Right
                            case 'D': return -3;  // Left
                            case 'H': return -7;  // Home
                            case 'F': return -8;  // End
                            default: break;
                        }
                    }
                    // ESC [ num ~  (e.g. ESC [ 5 ~ = PgUp)
                    if (seq[1] >= '0' && seq[1] <= '9') {
                        int num = seq[1] - '0';
                        int pos = 2;
                        while (pos < n && seq[pos] >= '0' && seq[pos] <= '9') {
                            num = num * 10 + (seq[pos] - '0');
                            pos++;
                        }
                        switch (num) {
                            case 1: case 7: return -7;  // Home
                            case 2: case 3: return -9;  // Ins/Del
                            case 4: case 8: return -8;  // End
                            case 5: return -5;          // PgUp
                            case 6: return -6;          // PgDn
                            default: break;
                        }
                    }
                } else if (seq[0] == 'O' && n >= 2) {
                    // ESC O final-byte  (e.g. ESC O A = Up, xterm style)
                    switch (seq[1]) {
                        case 'A': return -1;  // Up
                        case 'B': return -2;  // Down
                        case 'C': return -4;  // Right
                        case 'D': return -3;  // Left
                        case 'H': return -7;  // Home
                        case 'F': return -8;  // End
                        default: break;
                    }
                }
            }
            // Unrecognized escape sequence — treat as bare ESC
            return 27;
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
