#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <bsd/string.h>
#include <ff.h>
#include "virtual.h"
#include "ringbuffer.h"

void inspect(const char *filename);

#define VRAM ((volatile unsigned char *)0x80000000)
#define KEYBOARD ((volatile uint16_t *)0x90000020)
#define IO_SEEK ((volatile uint32_t *)0x90000040)
#define IO_WRITE ((volatile uint32_t *)0x90000048)
#define SHMEM ((volatile uint32_t *)0xa0000000)
#define CASMEM ((volatile uint32_t *)0xb0000000)

uint32_t volatile counter = 0;

static uint8_t waveform_buffer[2048];
static RingBuffer rb_waveform;
static int playing = 0;

uint32_t *irq_handler(uint32_t *regs, uint32_t irqs)
{
    if (irqs & 1)
        counter++;

    if (irqs & 2 && playing) {
       // if (ringbuffer_read_available(&rb_waveform) < 256)
       //     VRAM[0]++;
        ringbuffer_read(&rb_waveform, (void *)CASMEM, 256);
    }

    if (irqs & 4 && playing) {
        //if (ringbuffer_read_available(&rb_waveform) < 256)
        //    VRAM[1]++;
        ringbuffer_read(&rb_waveform, (void *)CASMEM + 256, 256);
    }

    return regs;
}

#define INTERRUPTS_PER_SECOND 60
#define MS_PER_INTERRUPT (1000 / INTERRUPTS_PER_SECOND)

uint32_t make_timeout_time_ms(uint32_t duration)
{
    return counter + duration/MS_PER_INTERRUPT;
}

void sleep_ms(uint32_t duration)
{
    uint32_t stop = make_timeout_time_ms(duration);
    while (counter < stop) ;
}

#define VZ_BLANK (' '+64)
#define VZ_UNKNOWN ('^'-64)

static int ascii2vz(int ch, int invert)
{
    ch = (ch >= ' ' && ch <= '?') ? ch : (ch >= '@' && ch <= '^') ? ch - 64 : VZ_UNKNOWN;
    return invert ? ch ^ 64 : ch;
}

static int cx;
static int cy;
static int invert;

#define VRAM_STEP 1

static void do_invert()
{
    VRAM[cy*VRAM_STEP*32 + VRAM_STEP*cx] ^= 64;
}

static void cls()
{
    memset((void *)VRAM, VZ_BLANK, VRAM_STEP*512);
    cx = 0;
    cy = 0;
    invert = 1;
    do_invert();
}

static void next_line()
{
    cx = 0;
    if (cy == 15) {
        memmove((void *)(VRAM), (void *)(VRAM + VRAM_STEP*32), VRAM_STEP*32*15);
        memset((void *)(VRAM + VRAM_STEP*32*15), VZ_BLANK, VRAM_STEP*32);
    } else {
        cy++;
    }
}

void putch(int ch)
{
    if (ch == '\n') {
        do_invert();
        next_line();
        do_invert();
        return;
    }

    VRAM[cy*VRAM_STEP*32 + VRAM_STEP*cx] = ascii2vz(ch, invert);
    if (cx == 31) {
        next_line();
    } else {
        cx++;
    }
    do_invert();
}

void print(const char *s)
{
    while (*s)
        putch(*s++);
}

static uint8_t hexchar[16]="0123456789ABCDEF";
void print_hex8(int v)
{
    putch(hexchar[(v>>4) & 0xf]);
    putch(hexchar[(v) & 0xf]);
}

void print_hex16(int v)
{
    putch(hexchar[(v>>12) & 0xf]);
    putch(hexchar[(v>>8) & 0xf]);
    putch(hexchar[(v>>4) & 0xf]);
    putch(hexchar[(v) & 0xf]);
}

void print_hex32(int v)
{
    print_hex16(v >> 16);
    print_hex16(v);
}

FATFS FatFs;
typedef struct {
    uint8_t mounted;
    uint8_t writable;
    char filename[13];

    uint8_t track; /* active track in shmem */
    uint8_t data[TRACKS_PER_DISK*TRACKSZ_VZ];
    uint8_t dirty;
} Disk;

static int active_drive = 3;
static Disk disk[2] = {0};

static void fdc_download(int drive)
{
    Disk *d = &disk[drive];
    if (!disk[drive].mounted)
        return;

    memcpy(d->data + d->track*TRACKSZ_VZ, (void *)SHMEM, TRACKSZ_VZ);
    d->dirty = 1;
}

typedef struct {
    uint8_t type;
    uint8_t filename[8];
    uint16_t start_addr;
    uint16_t end_addr;
    FSIZE_t file_size;
    FSIZE_t header_size;
} VirtualInfo;

static void virtual_build_track(int drive, uint8_t track, const VirtualInfo *virtual, FIL *file)
{
    Disk *d = &disk[drive];
    if (track == 0) {
        build_track0(d->data + track*TRACKSZ_VZ, virtual->type, virtual->filename, virtual->start_addr, virtual->end_addr, virtual->file_size);
    } else {
        build_track(d->data + track*TRACKSZ_VZ, file, virtual->header_size, track);
    }
}

static void fdc_upload(int drive, uint8_t track)
{
    Disk *d = &disk[drive];

    if (disk[drive].mounted) {
        memcpy((void *)SHMEM, d->data + track*TRACKSZ_VZ, TRACKSZ_VZ);
    } else {
        memset((void *)SHMEM, 0, TRACKSZ_VZ);
    }

    active_drive = drive;
    d->track = track;
}

static void save(int drive, const char *filename)
{
    Disk *d = &disk[drive];
    FIL file;

    if (active_drive == drive)
        fdc_download(drive);

    if (f_open(&file, filename, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
        print("?OPEN ERROR\n");
        return;
    }

    for (int track = 0; track < TRACKS_PER_DISK; track ++) {
        putch('.');
        UINT nwrite;
        if (f_write(&file, d->data + track*TRACKSZ_VZ, track < TRACKS_PER_DISK - 1 ? TRACKSZ_VZ : (TRACKSZ_VZ - 16), &nwrite) != FR_OK) {
            print("?WRITE ERROR\n");
            goto error;
        } else {
            d->dirty = 0;
        }
    }
    print("SAVED\n");

error:
    f_close(&file);
}

static int getch_nonce(uint8_t ch)
{
    return ch;
}

static int event_loop(int (*cb)(uint8_t ch));
static int event_once(int (*cb)(uint8_t ch));

int getch()
{
    return event_loop(getch_nonce);
}

int getch_noblock()
{
    return event_once(getch_nonce);
}

static int unmount(int drive)
{
    Disk *d = &disk[drive];

    if (!d->mounted)
        return 0;

    if (d->dirty) {
        print("DISK DIRTY, ARE YOU SURE (Y/N)?");
        while (1) {
            int ch = getch();
            if (ch == 'N')
                return -1;
            if (ch == 'Y')
                break;
        }
    }

    d->mounted = 0;
    d->track = 0xFF;
    memset(d->data, 0, sizeof(d->data));
    if (active_drive == drive)
        memset((void *)SHMEM, 0, TRACKSZ_VZ);
    d->dirty = 0;
    return 0;
}

static void strreplace(char *str, char old, char new)
{
    while (*str) {
        if (*str == old)
            *str = new;
        str++;
    }
}

static void fromdos(char *str)
{
    strreplace(str, '~', '>');
}

static char * todos(char *str)
{
    strreplace(str, '>', '~');
    return str;
}

static void cd(const char *dirname)
{
    if (f_chdir(dirname) != FR_OK)
        print("?ERROR\n");
}

static void dir(int l)
{
    DIR dirs;
    FRESULT res;
    FILINFO Finfo;

    if (f_opendir(&dirs, ".") != FR_OK) {
        print("?ERROR\n");
        return;
    }

    int col = 0;
    int line = 0;
    while (((res = f_readdir(&dirs, &Finfo)) == FR_OK) && Finfo.fname[0]) {
        fromdos(Finfo.fname);
        if (Finfo.fattrib & AM_DIR)
            invert ^= 1;
        print(Finfo.fname);
        if (Finfo.fattrib & AM_DIR)
            invert ^= 1;
        for (int i = 0; i < 13 - strlen(Finfo.fname); i++)
            putch(' ');
        if (l) {
            putch('R');
            putch(Finfo.fattrib & AM_RDO ? '-' : 'W');
            putch(Finfo.fattrib & AM_DIR ? 'D' : '-');
            if (!(Finfo.fattrib & AM_DIR)) {
                print(" ");
                print_hex32(Finfo.fsize);
            }
            print("\n");
            line++;
        } else {
            col++;
            if (col < 2) {
                print("  ");
            } else {
                putch('\n');
                col = 0;
                line++;
            }
        }

        if (line == 15) {
            print("PRESS ANY KEY... OR Q TO QUIT");
            int ch = getch();
            putch('\n');
            if (ch == 'Q')
                break;
            line = 0;
        }
    }
}

static void erase(const char *filename)
{
    if (f_unlink(filename) != FR_OK)
        print("?ERROR\n");
}

static void hexdump(const char *filename)
{
    FIL file;

    if (f_open(&file, filename, FA_READ | FA_OPEN_EXISTING) != FR_OK) {
        print("?OPEN ERROR\n");
        return;
    }
    UINT nread;
    uint16_t pos = 0;
    int line = 0;
    uint8_t buf[8];
    while (f_read(&file, buf, 8, &nread) == FR_OK && nread > 0) {
        print_hex16(pos);
        print(": ");
        for (int i = 0; i < nread; i++)
            print_hex8(buf[i]);
        for (int i = 0; i < 8 - nread; i++)
            print("  ");
        print(" ");
        for (int i = 0; i < nread; i++)
            putch(buf[i] < 0x20 || buf[i] > 0x60 ? '.' : buf[i]);
        putch('\n');
        pos += 8;
        line++;
        if (line == 15) {
            print("PRESS ANY KEY... OR Q TO QUIT");
            int ch = getch();
            putch('\n');
            if (ch == 'Q')
                break;
            line = 0;
        }
    }

    f_close(&file);
}

static int toupper(int c)
{
    return c >= 'a' && c <= 'z' ? c - 32 : c;
}

static int ends_with(const char *filename, const char *ext)
{
    size_t flen = strlen(filename);
    size_t elen = strlen(ext);
    if (flen <= elen)
       return 0;
    for (int i = 0; i < elen; i++)
        if (toupper(filename[flen - elen + i]) != ext[i])
            return 0;
    return 1;
}

static int vzfilenamesafe(int ch)
{
    if (ch == '~')
        return '-';
    return toupper(ch);
}

static int virtual_prep(VirtualInfo *virtual, FIL *file, const char *filename)
{
    FSIZE_t size = f_size(file);

    uint8_t type;
    uint16_t start_addr;
    uint16_t end_addr;
    FSIZE_t file_size;
    FSIZE_t header_size;

    if (ends_with(filename, ".VZ")) {

        VZFILE header;
        UINT nread;
        if (f_read(file, &header, sizeof(VZFILE), &nread) != FR_OK) {
            print("?READ VZ FILE HEADER FAILED\n");
            return -1;
        }

        if (nread != sizeof(VZFILE)) {
            print("?TRUNCATED VZ FILE\n");
            return -1;
        }

        switch (header.ftype) {
        case 0xF0: type = 'T'; break;
        case 0xF1: type = 'B'; break;
        default:
            print("?UNSUPPORTED VZ FILE TYPE\n");
            return -1;
        }

        start_addr = header.start_addrh*256 + header.start_addrl;

        long content_size = size - sizeof(VZFILE);

        if (content_size > 65536 - start_addr) {
            print("?FILE TOO BIG\n");
            return -1;
        }

        end_addr = start_addr + content_size;
        file_size = content_size;
        header_size = sizeof(VZFILE);
    } else {
        type = 'D';
        start_addr = 0;
        end_addr = 0;
        if (size > 39*SECTORS_PER_TRACK*SECTOR_FILEDATA_SZ) {
            print("?FILE TOO BIG\n");
            return -1;
        }
        file_size = size;
        header_size = 0;
    }

    virtual->type = type;
    virtual->start_addr = start_addr;
    virtual->end_addr = end_addr;
    virtual->file_size = file_size;
    virtual->header_size = header_size;

    const char *bn = filename;
    size_t bnlen = strlen(bn);
    int nuke = 0;
    for (int i = 0; i < 8; i++) {
        if (i < bnlen) {
            if (bn[i] == '.')
                nuke = 1;
            virtual->filename[i] = nuke ? ' ' : vzfilenamesafe(bn[i]);
        } else
            virtual->filename[i] = ' ';
    }

    putch('(');
    putch(type);
    putch(':');
    for (int i = 0; i < 8 && virtual->filename[i] != ' '; i++)
        putch(virtual->filename[i]);
    putch(')');

    return 0;
}

static void mount(int drive, const char *filename)
{
    Disk *d = &disk[drive];
    FIL file;
    VirtualInfo virtual;

    if (unmount(drive) < 0)
        return;

    if (f_open(&file, filename, FA_READ | FA_OPEN_EXISTING) != FR_OK) {
        print("?ERROR\n");
        return;
    }

    uint8_t is_virtual = !ends_with(filename, ".DSK");
    if (is_virtual) {
        if (virtual_prep(&virtual, &file, filename) < 0)
            return;
    }

    strlcpy(d->filename, filename, sizeof(d->filename));

    int read_errors = 0;
    for (int track = 0; track < 40; track++) {
        putch('.');

        if (is_virtual) {
            virtual_build_track(drive, track, &virtual, &file);
        } else {
            FSIZE_t size = f_size(&file);
            int track_sz = (size != 98560) ? TRACKSZ_VZ : (TRACKSZ_VZ - 16);
            UINT nread;
            if (f_lseek(&file, track*track_sz) != FR_OK) {
                read_errors = 1;
                nread = 0;
            } else {
                int errcode = f_read(&file, d->data + track*TRACKSZ_VZ, TRACKSZ_VZ, &nread);
                if (errcode != FR_OK) {
                    read_errors = 1;
                    nread = 0;
                }
            }
            memset(d->data + nread, 0, TRACKSZ_VZ - nread);
        }
    }
    if (read_errors)
        print("WARNING, THERE WERE READ ERRORS\n");
    print("MOUNTED\n");

    f_close(&file);

    d->mounted = 1;
    d->writable = 1;
    //other fields set by unmount

    *IO_WRITE = (!(disk[1].writable) << 1) | !disk[0].writable;
}

typedef struct {
    uint32_t fileid;
    uint32_t filesize;
    uint32_t waveid;
    uint32_t ckid;
    uint32_t cksize;
    uint16_t wFormatTag;
    uint16_t nChannels;
    uint32_t nSamplesPerSec;
    uint32_t nAvgBytesPerSec;
    uint16_t nBlockAlign;
    uint16_t wBitsPerSample;
    uint32_t dataid;
    uint32_t datasize;
} WAVEHEADER;

static void play(const char *filename)
{
    FIL file;

    if (f_open(&file, filename, FA_READ | FA_OPEN_EXISTING) != FR_OK) {
        print("?OPEN ERROR\n");
        return;
    }

    WAVEHEADER hdr;
    UINT nread;
    if (f_read(&file, &hdr, sizeof(WAVEHEADER), &nread) != FR_OK && nread != sizeof(WAVEHEADER)) {
        print("?READ HEADER ERROR\n");
        return;
    }

    if (hdr.wFormatTag != 1 ||
        hdr.nChannels != 1 ||
        hdr.wBitsPerSample != 8 ||
        hdr.nSamplesPerSec != 22050) {
        print("?WAVE FILE FORMAT\n");
        return;
    }

    print("PLAYING, PRESS Q TO QUIT\n");

    int size1, size2;
    char *data1, *data2;
    ringbuffer_where(&rb_waveform, RB_WRITE, 1024, &data1, &size1, &data2, &size2);
    memset(data1, 0, size1);
    memset(data2, 0, size2);
    ringbuffer_advance(&rb_waveform, RB_WRITE, 1024);

    playing = 1;

    while (1) {
        UINT nread;
        if (getch_noblock() == 'Q')
            break;
        if (!ringbuffer_where(&rb_waveform, RB_WRITE, 256, &data1, &size1, &data2, &size2))
            continue;
        if (f_read(&file, data1, size1, &nread) != FR_OK)
            break;
        ringbuffer_advance(&rb_waveform, RB_WRITE, nread);
        if (nread < size1)
            break;
        if (size2) {
            if (f_read(&file, data2, size2, &nread) != FR_OK)
                break;
            ringbuffer_advance(&rb_waveform, RB_WRITE, nread);
            if (nread < size2)
                break;
        }
    }

    f_close(&file);

    while (ringbuffer_read_available(&rb_waveform)) {
        getch_noblock();
    }

    int ss = ringbuffer_where(&rb_waveform, RB_WRITE, 1024, &data1, &size1, &data2, &size2);
    memset(data1, 0, size1);
    memset(data2, 0, size2);
    ringbuffer_advance(&rb_waveform, RB_WRITE, 1024);

    while (ringbuffer_read_available(&rb_waveform)) {
        getch_noblock();
    }

    playing = 0;
}

static void status(int drive)
{
    Disk *d = &disk[drive];

    print("DRIVE ");
    putch('1' + drive);
    print(": ");
    if (d->mounted) {
        print(d->filename);
        if (d->dirty)
            print(" DIRTY");
    }
    print("\n");
}

static void sdcard()
{
    unmount(0);
    unmount(1);
    f_mount(NULL, "", 0);
    if (f_mount(&FatFs, "", 0) != FR_OK)
        print("?SDCARD ERROR\n");
}

static uint8_t console_drive = 0;

static void parse(char *cmdline)
{
    if (!strncmp(cmdline, "CD ", 3)) {
        cd(todos(cmdline + 3));
    } else if (!strcmp(cmdline, "CLS")) {
        cls();
    } else if (!strcmp(cmdline, "DIR")) {
        dir(0);
    } else if (!strcmp(cmdline, "DIR -L")) {
        dir(1);
    } else if (!strcmp(cmdline, "DRIVE")) {
        putch('1' + console_drive);
        putch('\n');
    } else if (!strcmp(cmdline, "DRIVE 1")) {
        console_drive = 0;
    } else if (!strcmp(cmdline, "DRIVE 2")) {
        console_drive = 1;
    } else if (!strncmp(cmdline, "ERA ", 4)) {
        erase(todos(cmdline + 4));
    } else if (!strncmp(cmdline, "HEXDUMP ", 8)) {
        hexdump(todos(cmdline + 8));
    } else if (!strncmp(cmdline, "INSPECT ", 8)) {
        inspect(todos(cmdline + 8));
    } else if (!strncmp(cmdline, "MOUNT ", 6)) {
        mount(console_drive, todos(cmdline + 6));
    } else if (!strncmp(cmdline, "PLAY ", 5)) {
        play(todos(cmdline + 5));
    } else if (!strcmp(cmdline, "PWD")) {
        char cwd[256];
        if (f_getcwd(cwd, sizeof(cwd)) == FR_OK) {
            fromdos(cwd);
            print(cwd);
            putch('\n');
        } else
            print("?ERROR\n");
    } else if (!strncmp(cmdline, "SAVE ", 5)) {
        save(console_drive, todos(cmdline + 5));
    } else if (!strcmp(cmdline, "STATUS")) {
        status(0);
        status(1);
    } else if (!strcmp(cmdline, "UNMOUNT")) {
        unmount(console_drive);
    } else {
        print("?SYNTAX ERROR\n");
    }
}

#define ESC_LEFT  128
#define ESC_RIGHT 129
#define ESC_UP    130
#define ESC_DOWN  131
#define ESC_DEL   132

static int pos = 0;
static char cmdline[32] = {0};

//this assumes pos/cx are linked
static int tty_cb(uint8_t ch)
{
    if (ch == ESC_LEFT) {
        if (pos > 0) {
            do_invert();
            pos--;
            cx--;
            do_invert();
        }
    } else if (ch == ESC_RIGHT) {
        if (pos < strlen(cmdline)) {
            do_invert();
            pos++;
            cx++;
            do_invert();
        }
    } else if (ch == ESC_DEL) {
        if (pos < strlen(cmdline)) {
            int tail = strlen(cmdline) - pos;
            memcpy(cmdline + pos, cmdline + pos + 1, tail);

            print(cmdline + pos);
            print(" ");

            do_invert();
            cx -= tail;
            do_invert();
        }

    } else if (ch == '\n') {
        print("\n");

        parse(cmdline);

        print("READY\n");
        memset(cmdline, 0, sizeof(cmdline));
        pos = 0;
    } else if (ch < 128 && pos < sizeof(cmdline) - 1) {
        cmdline[pos] = ch;
        pos++;
        putch(ch);
    }

    return 0;
}

static const char table_4_shift[26] = {
#define _(x) ((x)-'A')
    [_('O')] = '[',
    [_('P')] = ']',
    [_('K')] = '/',
    [_('L')] = '?',
    [_('M')] = '\\',
#undef _
};

static const char table_1e_shift[] = {
#define _(x) ((x)-0x1e)
    [_(0x1e)] = '!', // 1 !
    [_(0x1f)] = '"', // 2 @
    [_(0x20)] = '#', // 3 #
    [_(0x21)] = '$', // 4 $
    [_(0x22)] = '%', // 5 %
    [_(0x23)] = '&', // 6 ^
    [_(0x24)] = '\'', // 7 &
    [_(0x25)] = '(', // 8 *
    [_(0x26)] = ')', // 9 (
#undef _
};

static const char table_4f[] = {
#define _(x) ((x)-0x4f)
    [_(0x4f)] = ESC_RIGHT, // RIGHT
    [_(0x50)] = ESC_LEFT, // LEFT
    [_(0x51)] = ESC_DOWN, // DOWN
    [_(0x52)] = ESC_UP, // UP
#undef _
};

#define KEYMOD_LSHIFT (1 << 1)
#define KEYMOD_RSHIFT (1 << 5)

static int process_scancode(int scancode, int modifiers, int (*cb)(uint8_t ch))
{
    int ret;
    if (scancode >= 0x4 && scancode <= 0x1d) { // A-Z
        if (modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT)) {
            char ch = table_4_shift[scancode - 0x4];
            ret = ch ? cb(ch) : 0;
        } else {
            ret = cb('A' + scancode - 0x4);
        }
    } else if (scancode <= 0x26) { // 1-9
        if (modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT)) {
            ret = cb(table_1e_shift[scancode - 0x1e]);
        } else {
            ret = cb('1' + scancode - 0x1e);
        }
    } else if (scancode == 0x27) { // 0
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '@' : '0');
    } else if (scancode == 0x28) { // RETURN
        ret = cb('\n');
    } else if (scancode == 0x2a) { // BACKSPACE
        ret = cb(ESC_LEFT);
    } else if (scancode == 0x2c) { // SPACE
        ret = cb(' ');
    } else if (scancode == 0x2d || scancode == 0x2e) { // - _ || = +
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '=' : '-');
    } else if (scancode == 0x33) { // ; :
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '+' : ';');
    } else if (scancode == 0x34) { // ' "
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '*' : ':');
    } else if (scancode == 0x36) { // , <
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '<' : ',');
    } else if (scancode == 0x37) { // . >
        ret = cb(modifiers & (KEYMOD_LSHIFT | KEYMOD_RSHIFT) ? '>' : '.');
    } else if (scancode == 0x4c) { // DEL
        ret = cb(ESC_DEL);
    } else if (scancode >= 0x4f && scancode <= 0x52) { // ARROW KEYS
        ret = cb(table_4f[scancode - 0x4f]);
    } else if (scancode < 0xe0 || scancode > 0xe7) { // META KEYS
#if 0
        print("?");
        print_hex16(scancode);
        print(" ");
        print_hex16(modifiers);
        print(" ");
#endif
        ret = 0;
    }
    return ret;
}

uint8_t last_scancode = 0;
uint32_t last_seek = 0x3;
uint32_t last_read = 0xffffffff;
uint32_t last_write = 0xffffffff;
static int event_once(int (*cb)(uint8_t ch))
{
        uint8_t scancode = *KEYBOARD & 0xff;
        int button_press = scancode && scancode != last_scancode;
        last_scancode = scancode;
        if (button_press) {
            int ret = process_scancode(scancode, *KEYBOARD >> 8, cb);
            if (ret)
                return ret;
        }

        uint32_t seek = *IO_SEEK;
        if (last_seek != seek) {
            int drive = seek & 3;
            int track_x2 = (seek >> 2) & 0xff;
            int dirty = (seek >> 10) & 1;

            if (dirty && active_drive < 2) {
                fdc_download(active_drive);
            }

            if (!(track_x2 & 1)) {
                if (drive < 2) {
                    fdc_upload(drive, track_x2 >> 1);
                }
            }
            last_seek = seek;
        }
    return 0;
}

static int event_loop(int (*cb)(uint8_t ch))
{
    int ret;
    while (!(ret = event_once(cb))) ;
    return ret;
}

void irq_enable();

int main()
{
    cls();
    print("I/O CONTROLLER V1.0\n");
    ringbuffer_init(&rb_waveform, waveform_buffer, sizeof(waveform_buffer));
    irq_enable();
    sdcard();
    print("READY\n");
    memset(cmdline, 0, sizeof(cmdline));
    event_loop(tty_cb);
    return 0;
}
