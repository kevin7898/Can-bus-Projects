#include <assert.h>
#include <stdio.h>
#include "../main/power_policy.h"
int main(void) {
    backup_policy_t s = {0};
    // Repeated crank dips separated by recovered supply do not accumulate.
    for (int cycle=0; cycle<4; cycle++) {
        for (int i=0;i<100;i++) assert(!backup_policy_step(&s,false,true,3800,100));
        assert(!backup_policy_step(&s,true,true,3800,100));
        assert(s.absent_ms==0);
    }
    for (int i=0;i<299;i++) assert(!backup_policy_step(&s,false,true,3800,100));
    assert(backup_policy_step(&s,false,true,3800,100));
    s=(backup_policy_t){0};
    for(int i=0;i<9;i++) assert(!backup_policy_step(&s,false,true,3400,100));
    assert(backup_policy_step(&s,false,true,3400,100));
    // Missing ADC cannot suppress the time limit, or fabricate low battery.
    s=(backup_policy_t){0};
    assert(!backup_policy_step(&s,false,false,0,1000));
    assert(s.low_ms==0);
    assert(backup_policy_step(&s,false,false,0,29000));
    // Recovery clears a partial low-battery debounce; plugged-in depleted pack is allowed.
    s=(backup_policy_t){0};
    assert(!backup_policy_step(&s,false,true,3400,900));
    assert(!backup_policy_step(&s,false,true,3600,100));
    assert(s.low_ms==0);
    assert(!backup_policy_step(&s,true,true,3200,60000));
    assert(!backup_policy_step(&s,false,true,3450,1000));
    assert(backup_policy_step(&s,false,true,3800,UINT32_MAX));
    puts("power policy: crank recovery, timeout, low-cell debounce, ADC failure, saturation PASS");
}
