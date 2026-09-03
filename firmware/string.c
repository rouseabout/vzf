#include <string.h>
#include <stdint.h>

int memcmp(const void * s1, const void * s2, size_t n)
{
    const unsigned char * m1 = s1, * m2 = s2;
    int ret = 0;
    for (size_t i = 0; i < n && !(ret = m1[i] - m2[i]); i++) ;
    return ret;
}

void * memcpy(void * dst_, const void * src_, size_t size)
{
    uint8_t * dst = dst_;
    const uint8_t * src = src_;
    for (unsigned int i = 0; i < size; i++)
        dst[i] = src[i];
    return dst;
}

void * memmove(void * s1, const void * s2, size_t n)
{
    char * dst = s1;
    const char * src = s2;
    if (dst < src)
        memcpy(dst, src, n);
    else
        for (unsigned int i = 0; i < n; i++)
            dst[n - i - 1] = src[n - i - 1];
    return dst;
}

void * memset(void * dst_, int value, size_t size)
{
    uint8_t * dst = dst_;
    for (unsigned int i = 0; i < size; i++)
        dst[i] = value;
    return dst;
}

char * strchr(const char *s, int c)
{
    do {
        if (*s == c)
            return (char *)s;
    } while(*s++);
    return NULL;
}

int strcmp(const char * s1, const char * s2)
{
    while (*s2 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

char * strcpy(char * s1, const char * s2)
{
    char * ret = s1;
    while (*s2)
        *s1++ = *s2++;
    *s1 = 0;
    return ret;
}

size_t strlen(const char * s)
{
    size_t size = 0;
    while (s[size]) {
        size++;
    }
    return size;
}

int strncmp(const char * s1, const char * s2, size_t size)
{
    while (size && *s1 && *s1 == *s2) {
        s1++;
        s2++;
        size--;
    }
    return size ? *(unsigned char *)s1 - *(unsigned char *)s2 : 0;
}
