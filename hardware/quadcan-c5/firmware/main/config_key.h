// Exact CAN config-key parsing; sscanf("can%d_fd") also accepts "can1_listen".
#pragma once
#include <string.h>

typedef enum { CAN_KEY_NONE, CAN_KEY_BITRATE, CAN_KEY_DATA_RATE, CAN_KEY_LISTEN } can_key_t;

static inline can_key_t can_config_key(const char *key, unsigned channels, unsigned *index)
{
    if (strncmp(key, "can", 3) || key[3] < '1' || key[3] > '9') return CAN_KEY_NONE;
    unsigned ch = (unsigned)(key[3] - '1');
    if (ch >= channels) return CAN_KEY_NONE;
    can_key_t kind = CAN_KEY_NONE;
    if (!key[4]) kind = CAN_KEY_BITRATE;
    else if (!strcmp(key + 4, "_fd")) kind = CAN_KEY_DATA_RATE;
    else if (!strcmp(key + 4, "_listen")) kind = CAN_KEY_LISTEN;
    if (kind != CAN_KEY_NONE) *index = ch;
    return kind;
}
