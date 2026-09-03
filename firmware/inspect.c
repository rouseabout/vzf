#include <stddef.h>
#include <ff.h>

#include "virtual.h"

void putch(int ch);
void print(const char *s);
void print_hex8(uint8_t v);
void print_hex16(int v);
int getch();

static void print_fixed_string(const char *s, size_t count)
{
    for (size_t i = 0; i < count; i++)
        putch(s[i]);
}

static uint16_t track_checksum(const uint8_t *data, int offset, size_t size)
{
    uint16_t sum = 0;
    for (size_t i = 0; i < size; i++)
        sum += data[(offset + i) % TRACKSZ_VZ];
    return sum;
}

static int find_sector(const uint8_t *data, int track, int sector)
{
    for (int i = 0; i < TRACKSZ_VZ; i++) {
        if (data[(i + 0) % TRACKSZ_VZ] == 0x80 &&
            data[(i + 1) % TRACKSZ_VZ] == 0x00 &&
            data[(i + 2) % TRACKSZ_VZ] == 0xfe &&
            data[(i + 3) % TRACKSZ_VZ] == 0xe7 &&
            data[(i + 4) % TRACKSZ_VZ] == 0x18 &&
            data[(i + 5) % TRACKSZ_VZ] == 0xc3 &&
            data[(i + 6) % TRACKSZ_VZ] == track &&
            data[(i + 7) % TRACKSZ_VZ] == sector &&
            data[(i + 8) % TRACKSZ_VZ] == track + sector) {

            for (int j = i + 9; j < i + 9 + 6; j++) {
                if (data[(j + 0) % TRACKSZ_VZ] == 0x80 &&
                    data[(j + 1) % TRACKSZ_VZ] == 0x00 &&
                    data[(j + 2) % TRACKSZ_VZ] == 0xc3 &&
                    data[(j + 3) % TRACKSZ_VZ] == 0x18 &&
                    data[(j + 4) % TRACKSZ_VZ] == 0xe7 &&
                    data[(j + 5) % TRACKSZ_VZ] == 0xfe) {

                    uint16_t sum = track_checksum(data, j + 6, 128);
                    if (data[(j + 6 + 128) % TRACKSZ_VZ] == (sum & 0xff) &&
                        data[(j + 6 + 128 + 1) % TRACKSZ_VZ] == (sum >> 8)) {
                        //printf(">> track %d, sector %d data starts at 0x%x\n", track, sector, j+ 6);
                        return j + 6;
                    }
                }
            }
        }
    }

    return -1;
}

static void sector_memcpy(void *dstv, const uint8_t *data, int offset, int size)
{
    uint8_t *dst = dstv;
    for (int i = 0; i < size; i++)
        dst[i] = data[(offset + i) % TRACKSZ_VZ];
}

typedef struct {
    uint8_t filetype;
    uint8_t separator;
    char filename[8];
    uint8_t track;
    uint8_t sector;
    uint16_t start;
    uint16_t end;
} DirEnt;

void inspect(const char *filename)
{
    FIL file;

    if (f_open(&file, filename, FA_READ | FA_OPEN_EXISTING) != FR_OK) {
        print("?ERROR\n");
        return;
    }

    uint8_t track[TRACKSZ_VZ];

    UINT nread;
    int errcode = f_read(&file, track, TRACKSZ_VZ, &nread);
    f_close(&file);
    if (errcode != FR_OK) {
        print("?ERROR\n");
        return;
    }

    int run = 1;
    int line = 0;
    for (int ls = 0; run && ls < 15; ls ++) {
        int offset = find_sector(track, 0, ls);
        if (offset < 0) {
            print("COULD NOT FIND SECTOR 0\n");
            return;
        }
        DirEnt de[8];
        sector_memcpy(&de, track, offset, sizeof(de));

        for (int i = 0; i < 8; i++) {
            if (de[i].filename[0] < ' ') {
                run = 0;
            } else {
                putch(de[i].filetype);
                putch(':');
                print_fixed_string(de[i].filename, 8);
                putch(' ');
                print_hex8(de[i].track);
                putch(' ');
                print_hex8(de[i].sector);
                putch(' ');
                print_hex16(de[i].start);
                putch(' ');
                print_hex16(de[i].end);
                putch(' ');
                print_hex16(de[i].end - de[i].start);
                putch('\n');

                line++;
                if (line == 15) {
                    print("PRESS ANY KEY... OR Q TO QUIT");
                    int ch = getch();
                    putch('\n');
                    if (ch == 'Q') {
                        run = 0;
                        break;
                    }
                    line = 0;
                }
            }
        }
    }

    int offset = find_sector(track, 0, 15);
    if (offset < 0) {
        print("COULD NOT FIND SECTOR 15\n");
        return;
    }

    uint8_t fat[39*2];
    sector_memcpy(fat, track, offset, sizeof(fat));
    uint16_t count = 0;
    for (int i = 0; i < sizeof(fat); i++)
        for (int j = 0; j < 8; j++)
            if (fat[i] & (1 << j))
                count++;
    uint16_t sfree = 16*39 - count;
    print("0X"); print_hex16(sfree); print(" (0X"); print_hex16(sfree * 128); print(" BYTES) FREE\n");

    return;
}
