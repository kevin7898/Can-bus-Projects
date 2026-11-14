#include <assert.h>
#include <stdio.h>
#include "../main/config_key.h"

int main(void)
{
    unsigned ch = 99;
    assert(can_config_key("can1", 4, &ch) == CAN_KEY_BITRATE && ch == 0);
    assert(can_config_key("can2_fd", 4, &ch) == CAN_KEY_DATA_RATE && ch == 1);
    assert(can_config_key("can4_listen", 4, &ch) == CAN_KEY_LISTEN && ch == 3);
    const char *invalid[] = {"", "c", "ca", "can", "can0", "can5", "can10", "can1_f", "can1_fd_extra", "can1_listen_extra", "can-1", "can1x", "wifi_ap"};
    for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        ch = 99;
        assert(can_config_key(invalid[i], 4, &ch) == CAN_KEY_NONE && ch == 99);
    }
    puts("config key tests passed");
}
