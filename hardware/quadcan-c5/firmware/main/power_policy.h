// Pure elapsed-time backup policy; also compiled by the host regression test.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#define BACKUP_GRACE_MS 30000u
#define BACKUP_LOW_MV 3450u
#define BACKUP_LOW_MS 1000u
typedef struct { uint32_t absent_ms, low_ms; } backup_policy_t;
static inline bool backup_policy_step(backup_policy_t *s, bool external_good,
                                     bool battery_valid, uint32_t battery_mv, uint32_t elapsed_ms)
{
    if (external_good) { s->absent_ms = s->low_ms = 0; return false; }
    // Saturation prevents rollover after long scheduling delays.
    s->absent_ms += elapsed_ms > BACKUP_GRACE_MS - s->absent_ms ? BACKUP_GRACE_MS - s->absent_ms : elapsed_ms;
    if (battery_valid && battery_mv < BACKUP_LOW_MV)
        s->low_ms += elapsed_ms > BACKUP_LOW_MS - s->low_ms ? BACKUP_LOW_MS - s->low_ms : elapsed_ms;
    else s->low_ms = 0;
    return s->absent_ms >= BACKUP_GRACE_MS || s->low_ms >= BACKUP_LOW_MS;
}
