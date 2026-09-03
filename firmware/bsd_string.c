#include <bsd/string.h>

size_t strlcpy(char *dst, const char *src, size_t size)
{
    size_t i;
    for (i = 0; i < size - 1 && src[i]; i++)
        dst[i] = src[i];
    dst[i] = 0;
    return i;
}
