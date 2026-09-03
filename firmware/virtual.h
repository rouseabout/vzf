#include <stdint.h>
#include <ff.h>

#define SECTOR_RAW_SZ 154
#define SECTOR_DATA_SZ 128
#define SECTOR_FILEDATA_SZ 126
#define SECTORS_PER_TRACK 16
#define TRACKSZ_VZ 2480
#define TRACK_SEP 16
#define TRACKS_PER_DISK 40

typedef struct {
    uint8_t vzmagic[4];
    uint8_t filename[17];
    uint8_t ftype;
    uint8_t start_addrl;
    uint8_t start_addrh;
} VZFILE;


void build_track0(uint8_t *data, uint8_t type, const char filename[8], uint16_t start_addr, uint16_t end_addr, uint16_t file_size);
void build_track(uint8_t *data, FIL *fp, uint16_t header_size, uint8_t track);
