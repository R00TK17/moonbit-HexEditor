// Terminal UI stubs for the hex editor TUI
// Windows: conio + Virtual Terminal Processing
// Linux:   termios raw mode (persistent) + alternate screen
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#else
#include <termios.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <dirent.h>
#include <sys/stat.h>

// Saved terminal state for restoration on exit
static struct termios saved_term;
static volatile sig_atomic_t term_saved = 0;
static volatile sig_atomic_t alt_screen_active = 0;

// Restore terminal to original settings (signal-safe)
static void restore_terminal(void) {
    if (alt_screen_active) {
        if (write(STDOUT_FILENO, "\033[?1000l\033[?1006l\033[?1049l", 24)) {}
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
    SetConsoleOutputCP(65001);
    SetConsoleCP(65001);
    ansi_ok = 1;
}

// Init console for CLI (UTF-8 output without full TUI setup)
void tui_init_console(void) {
    enable_ansi();
}
#endif

// Linux: no-op console init
#ifndef _WIN32
void tui_init_console(void) {}
#endif

// ====== Alternate screen buffer ======
void tui_enter_alt_screen(void) {
#ifdef _WIN32
    enable_ansi();
    printf("\033[?1049h");
#else
    if (write(STDOUT_FILENO, "\033[?1049h\033[?1000h\033[?1006h", 24) >= 0) {
        alt_screen_active = 1;
    }
#endif
    fflush(stdout);
}

void tui_exit_alt_screen(void) {
#ifdef _WIN32
    printf("\033[?1049l");
#else
    if (write(STDOUT_FILENO, "\033[?1000l\033[?1006l\033[?1049l", 24) < 0) {}
    alt_screen_active = 0;
#endif
    fflush(stdout);
}

// ====== Persistent raw mode (Linux) ======
#ifndef _WIN32
void tui_enter_raw(void) {
    struct termios newt;
    if (tcgetattr(STDIN_FILENO, &saved_term) != 0) return;
    setup_terminal_handlers();

    newt = saved_term;
    newt.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
    newt.c_oflag &= ~(OPOST);
    newt.c_lflag &= ~(ICANON | ECHO | ISIG | IEXTEN);
    newt.c_cc[VMIN] = 1;
    newt.c_cc[VTIME] = 0;
    term_saved = (tcsetattr(STDIN_FILENO, TCSANOW, &newt) == 0);
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
                    case 82: return -11;
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
            char seq[64];
            ssize_t nseq = read(STDIN_FILENO, seq, sizeof(seq));
            if (nseq < 0) nseq = 0;
            if (nseq >= 1) {
                if (seq[0] == '[' && nseq >= 2) {
                    // SGR mouse: ESC [ < button ; x ; y M/m
                    if (seq[1] == '<') {
                        int btn = 0, pos = 2;
                        while (pos < nseq && seq[pos] >= '0' && seq[pos] <= '9') {
                            btn = btn * 10 + (seq[pos] - '0'); pos++;
                        }
                        // Drain any remaining mouse bytes from stdin
                        fd_set dfds; struct timeval dtv;
                        FD_ZERO(&dfds); FD_SET(STDIN_FILENO, &dfds);
                        dtv.tv_sec = 0; dtv.tv_usec = 5000; // 5ms
                        while (select(1, &dfds, NULL, NULL, &dtv) > 0) {
                            char discard[64];
                            if (read(STDIN_FILENO, discard, sizeof(discard)) <= 0) break;
                            FD_ZERO(&dfds); FD_SET(STDIN_FILENO, &dfds);
                            dtv.tv_sec = 0; dtv.tv_usec = 5000;
                        }
                        if (btn == 64) return -1;  // scroll up
                        if (btn == 65) return -2;  // scroll down
                        return -10;  // ignore other mouse events
                    }
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
                                case 2: return -11; case 3: return -9;
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
            return -10; // unrecognized escape sequence: ignore (don't emit ESC)
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
    return 24;
#else
    struct winsize ws = {0};
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_row > 0) return ws.ws_row;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_row > 0) return ws.ws_row;
    char *env = getenv("LINES");
    if (env) { int n = atoi(env); if (n > 0 && n <= 200) return n; }
    return 24;
#endif
}

int tui_get_terminal_cols(void) {
#ifdef _WIN32
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi))
        return csbi.srWindow.Right - csbi.srWindow.Left + 1;
    return 80;
#else
    struct winsize ws = {0};
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_col > 0) return ws.ws_col;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) != -1 && ws.ws_col > 0) return ws.ws_col;
    char *env = getenv("COLUMNS");
    if (env) { int n = atoi(env); if (n > 0 && n <= 500) return n; }
    return 80;
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
    size_t len = strlen(s);
    if (write(STDOUT_FILENO, s, len) < 0) {}
#endif
}

// ====== Memory-mapped file I/O ======
// Returns a pointer to the mapped file data. Sets *size to the file size.
// Returns NULL on failure.
#ifdef _WIN32
void* mmap_file(const char* path, int* size) {
    HANDLE hFile = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ,
        NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return NULL;
    *size = (int)GetFileSize(hFile, NULL);
    if (*size <= 0) { CloseHandle(hFile); return NULL; }
    HANDLE hMap = CreateFileMappingA(hFile, NULL, PAGE_READONLY, 0, 0, NULL);
    CloseHandle(hFile);
    if (!hMap) return NULL;
    void* ptr = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(hMap);
    return ptr;
}
void munmap_file(void* ptr, int size) {
    if (ptr) UnmapViewOfFile(ptr);
}
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
void* mmap_file(const char* path, int* size) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) < 0) { close(fd); return NULL; }
    *size = (int)st.st_size;
    if (*size <= 0) { close(fd); return NULL; }
    void* ptr = mmap(NULL, *size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (ptr == MAP_FAILED) return NULL;
    return ptr;
}
void munmap_file(void* ptr, int size) {
    if (ptr) munmap(ptr, size);
}
#endif

// Get file size via mmap (0 on failure)
int mmap_file_size(const char* path) {
    int size = 0;
    void* ptr = mmap_file(path, &size);
    if (!ptr) return 0;
    munmap_file(ptr, size);
    return size;
}

// Load file via mmap into pre-allocated buffer. Returns bytes read (0 on failure).
// Caller must allocate buf with mmap_file_size first.
int mmap_load(const char* path, unsigned char* buf) {
    int size = 0;
    void* ptr = mmap_file(path, &size);
    if (!ptr || size <= 0 || !buf) return 0;
    memcpy(buf, ptr, size);
    munmap_file(ptr, size);
    return size;
}

// ====== Directory listing (UTF-8 output) ======
int tui_get_cwd(char* buf, int buf_size) {
#ifdef _WIN32
    wchar_t wbuf[1024];
    int wlen = GetCurrentDirectoryW(1024, wbuf);
    if (wlen <= 0) return 0;
    int n = WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, buf_size, NULL, NULL);
return n > 0 ? n - 1 : n;
#else
    if (getcwd(buf, buf_size)) { int i = 0; while(buf[i]) i++; return i; }
    return 0;
#endif
}

int tui_list_dir(const char* path, char* buf, int buf_size) {
    int pos = 0;
#ifdef _WIN32
    // Convert UTF-8 path to wide, append \*
    wchar_t wpath[1024];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1000);
    wcscat(wpath, L"\\*");
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(wpath, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    do {
        if (fd.cFileName[0] == L'.' && fd.cFileName[1] == L'\0') continue;
        char type = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 'D' : 'F';
        char name[512];
        int nlen = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, name, 512, NULL, NULL);
        if (nlen <= 0) continue;
        int len = snprintf(buf + pos, buf_size - pos, "%c:%s\n", type, name);
        if (len < 0 || pos + len >= buf_size) break;
        pos += len;
    } while (FindNextFileW(h, &fd));
    FindClose(h);
#else
    DIR* d = opendir(path);
    if (!d) return 0;
    struct dirent* e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.' && e->d_name[1] == '\0') continue;
        char type = (e->d_type == DT_DIR) ? 'D' : 'F';
        int len = snprintf(buf + pos, buf_size - pos, "%c:%s\n", type, e->d_name);
        if (len < 0 || pos + len >= buf_size) break;
        pos += len;
    }
    closedir(d);
#endif
    return pos;
}

// ====== Persistence helpers ======
int tui_get_home(char* buf, int buf_size) {
#ifdef _WIN32
    wchar_t wbuf[1024];
    DWORD len = GetEnvironmentVariableW(L"USERPROFILE", wbuf, 1024);
    if (len == 0) return 0;
    int n = WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, buf_size, NULL, NULL);
return n > 0 ? n - 1 : n;
#else
    const char* home = getenv("HOME");
    if (!home) return 0;
    int i = 0;
    while (home[i] && i < buf_size - 1) { buf[i] = home[i]; i++; }
    buf[i] = 0;
    return i;
#endif
}

void tui_mkdir_p(const char* path) {
#ifdef _WIN32
    wchar_t wpath[1024];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1024);
    CreateDirectoryW(wpath, NULL);
#else
    mkdir(path, 0755);
#endif
}

int tui_realpath(const char* path, char* buf, int buf_size) {
#ifdef _WIN32
    wchar_t wpath[1024], wout[1024];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1024);
    DWORD len = GetFullPathNameW(wpath, 1024, wout, NULL);
    if (len == 0) return 0;
    int n = WideCharToMultiByte(CP_UTF8, 0, wout, -1, buf, buf_size, NULL, NULL);
	    return n > 0 ? n - 1 : n;
#else
    char resolved[4096];
    if (!realpath(path, resolved)) return 0;
    int i = 0;
    while (resolved[i] && i < buf_size - 1) { buf[i] = resolved[i]; i++; }
    buf[i] = 0;
    return i;
#endif
}
