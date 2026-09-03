#include <stdint.h>
#include <string.h>
#include "virtual.h"

static void build_sector_header(uint8_t *data, uint8_t track, uint8_t sector)
{
    memset(data, 0x80, 6);
    data[6] = 0;

    data[7] = 0xfe;
    data[8] = 0xe7;
    data[9] = 0x18;
    data[10] = 0xc3;

    data[11] = track;
    data[12] = sector;
    data[13] = data[11] + data[12]; //crc

    memset(data + 14, 0x80, 5);
    data[19] = 0;

    data[20] = 0xc3;
    data[21] = 0x18;
    data[22] = 0xe7;
    data[23] = 0xfe;
}

static uint16_t checksum(uint8_t *data, size_t size)
{
    uint16_t sum = 0;
    for (size_t i = 0; i < size; i++)
        sum += data[i];
    return sum;
}

static void build_dir_sector(uint8_t *data, uint8_t type, const char filename[8], uint16_t start_addr, uint16_t end_addr)
{
    build_sector_header(data, 0, 0);

    data[24] = type;
    data[25] = ':';
    memcpy(data + 26, filename, 8);
    data[34] = 1;
    data[35] = 0;
    data[36] = start_addr & 0xff;
    data[37] = start_addr >> 8;
    data[38] = end_addr & 0xff;
    data[39] = end_addr >> 8;

    memset(data + 40, 0, 7 * 16);
    uint16_t sum = checksum(data + 24, SECTOR_DATA_SZ);
    data[152] = sum & 0xff;
    data[153] = sum >> 8;
}

static void build_empty_sector(uint8_t *data, uint8_t track, uint8_t sector)
{
    build_sector_header(data, track, sector);
    memset(data + 24, 0, 128);
    uint16_t sum = checksum(data + 24, SECTOR_DATA_SZ);
    data[152] = sum & 0xff;
    data[153] = sum >> 8;
}

static void build_fat_sector(uint8_t *data, uint16_t size)
{
    build_sector_header(data, 0, 15);
    memset(data + 24, 0, 128);
    for (int i = 0; i < (size + SECTOR_FILEDATA_SZ - 1) / SECTOR_FILEDATA_SZ; i++) //FIXME: optimise with memset
        data[24 + (i / 8)] |= 1 << (i % 8);
    uint16_t sum = checksum(data + 24, SECTOR_DATA_SZ);
    data[152] = sum & 0xff;
    data[153] = sum >> 8;
}

static const uint8_t physical_to_logical_sector[SECTORS_PER_TRACK] = {
    0, 11, 6, 1, 12, 7, 2, 13, 8, 3, 14, 9, 4, 15, 10, 5
};

static const uint8_t logical_sector_to_physical[SECTORS_PER_TRACK] = {
    0, 3, 6, 9, 12, 15, 2, 5, 8, 11, 14, 1, 4, 7, 10, 13
};

void build_track0(uint8_t *data, uint8_t type, const char filename[8], uint16_t start_addr, uint16_t end_addr, uint16_t file_size)
{
    build_dir_sector(data, type, filename, start_addr, end_addr);
    for (int ps = 1; ps < SECTORS_PER_TRACK; ps++) {
        if (physical_to_logical_sector[ps] == 15)
            build_fat_sector(data + ps*SECTOR_RAW_SZ, end_addr - start_addr);
        else
            build_empty_sector(data + ps*SECTOR_RAW_SZ, 0, physical_to_logical_sector[ps]);

    }
    memset(data + 16*SECTOR_RAW_SZ, 0, 16); // track separator
}

static void build_sector(uint8_t *data, FIL *fp, uint8_t track, uint8_t sector)
{
    build_sector_header(data, track, sector);
    UINT nread;
    if (f_read(fp, data + 24, SECTOR_FILEDATA_SZ, &nread) != FR_OK)
        nread = 0;
    if (nread < SECTOR_FILEDATA_SZ) {
        memset(data + 24 + nread, 0x00, SECTOR_FILEDATA_SZ - nread);
        data[150] = 0;
        data[151] = 0;
    } else {
        data[150] = sector < 15 ? track        : (track + 1);
        data[151] = sector < 15 ? (sector + 1) : 0;
    }
    uint16_t sum = checksum(data + 24, SECTOR_DATA_SZ);
    data[152] = sum & 0xff;
    data[153] = sum >> 8;
}

void build_track(uint8_t *data, FIL *fp, uint16_t header_size, uint8_t track)
{
    f_lseek(fp, header_size + (track - 1) * SECTORS_PER_TRACK*SECTOR_FILEDATA_SZ);
    for (int ls = 0; ls < SECTORS_PER_TRACK; ls++)
        build_sector(data + logical_sector_to_physical[ls]*SECTOR_RAW_SZ, fp, track, ls);
    memset(data + 16*SECTOR_RAW_SZ, 0, 16); // track separator
}
