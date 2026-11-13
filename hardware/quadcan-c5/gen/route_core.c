// A* search core for route.py (called through ctypes).
// State = (layer, incoming direction, cell). Direction is part of the state so turns can be
// penalised: that is what makes the router prefer long straight runs and clean 45-degree bends.
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ND 9          /* 8 directions + "none" (start / just came through a via) */
#define INF 1e30f
typedef struct { float f; uint32_t s; } node_t;

static node_t *heap; static size_t hn, hcap;
static float *G; static uint8_t *PV; static size_t cap;
static uint32_t *touched; static size_t nt, tcap;
static const int DX[8] = {1, 1, 0, -1, -1, -1, 0, 1};
static const int DY[8] = {0, 1, 1, 1, 0, -1, -1, -1};

static inline void hpush(float f, uint32_t s) {
    if (hn == hcap) { hcap = hcap ? hcap * 2 : 1 << 20; heap = realloc(heap, hcap * sizeof(node_t)); }
    size_t i = hn++;
    while (i) { size_t p = (i - 1) / 2; if (heap[p].f <= f) break; heap[i] = heap[p]; i = p; }
    heap[i].f = f; heap[i].s = s;
}
static inline node_t hpop(void) {
    node_t top = heap[0], last = heap[--hn];
    size_t i = 0;
    for (;;) {
        size_t c = 2 * i + 1;
        if (c >= hn) break;
        if (c + 1 < hn && heap[c + 1].f < heap[c].f) c++;
        if (last.f <= heap[c].f) break;
        heap[i] = heap[c]; i = c;
    }
    heap[i] = last;
    return top;
}
static inline void relax(uint32_t s, float g, uint8_t pv, float h) {
    if (g < G[s]) {
        if (G[s] >= INF) {
            if (nt == tcap) { tcap = tcap ? tcap * 2 : 1 << 20; touched = realloc(touched, tcap * sizeof(uint32_t)); }
            touched[nt++] = s;
        }
        G[s] = g; PV[s] = pv; hpush(g + h, s);
    }
}

/* returns path length (cells written to out as l,y,x triples, source first), -1 = no path, -2 = budget hit */
int route_astar(int W, int H, int L, const uint8_t *fr, const uint8_t *vfree, const uint8_t *target,
                const float *heur, const int32_t *src, int nsrc, const float *lcost, const uint8_t *lok,
                float via_cost, float turn45, float turn90, float hw, long max_exp, int32_t *out, int max_out) {
    size_t N = (size_t)W * H, NS = N * ND * L;
    if (cap < NS) {
        G = realloc(G, NS * sizeof(float)); PV = realloc(PV, NS);
        for (size_t i = 0; i < NS; i++) G[i] = INF;
        cap = NS; nt = 0;
    }
    for (size_t i = 0; i < nt; i++) G[touched[i]] = INF;
    nt = 0; hn = 0;
    for (int i = 0; i < nsrc; i++) {
        int l = src[3 * i], y = src[3 * i + 1], x = src[3 * i + 2];
        size_t r = (size_t)y * W + x;
        relax((uint32_t)(((size_t)l * ND + 8) * N + r), 0.0f, 0xFF, hw * heur[r]);
    }
    long exp = 0;
    while (hn) {
        node_t n = hpop();
        uint32_t s = n.s;
        size_t r = s % N; int ld = (int)(s / N); int l = ld / ND, d = ld % ND;
        float g = G[s];
        if (n.f > g + hw * heur[r] + 1e-3f) continue;
        if (target[(size_t)l * N + r]) {
            int cnt = 0;
            for (;;) {
                if (cnt >= max_out) return -1;
                out[3 * cnt] = l; out[3 * cnt + 1] = (int)(r / W); out[3 * cnt + 2] = (int)(r % W); cnt++;
                uint8_t pv = PV[s];
                if (d < 8) { r = r - (DX[d] + DY[d] * W); d = pv; }
                else if (pv == 0xFF) break;
                else { l = (pv >> 4) & 7; d = pv & 15; }
                s = (uint32_t)(((size_t)l * ND + d) * N + r);
            }
            for (int i = 0; i < cnt / 2; i++)
                for (int k = 0; k < 3; k++) { int32_t t = out[3 * i + k]; out[3 * i + k] = out[3 * (cnt - 1 - i) + k]; out[3 * (cnt - 1 - i) + k] = t; }
            return cnt;
        }
        if (++exp > max_exp) return -2;
        int x = (int)(r % W), y = (int)(r / W);
        const uint8_t *f = fr + (size_t)l * N;
        float lc = lcost[l];
        for (int nd = 0; nd < 8; nd++) {
            int nx = x + DX[nd], ny = y + DY[nd];
            if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
            size_t nr = (size_t)ny * W + nx;
            if (!f[nr]) continue;
            int diag = DX[nd] && DY[nd];
            if (diag && !(f[(size_t)y * W + nx] && f[(size_t)ny * W + x])) continue;
            float c = (diag ? 1.41421356f : 1.0f) * lc;
            if (d < 8) {
                int df = abs(nd - d); if (df > 4) df = 8 - df;
                if (df == 1) c += turn45; else if (df == 2) c += turn90; else if (df > 2) c += 4.0f * turn90;
            }
            relax((uint32_t)(((size_t)l * ND + nd) * N + nr), g + c, (uint8_t)d, hw * heur[nr]);
        }
        if (vfree[r]) {
            for (int l2 = 0; l2 < L; l2++) {
                if (l2 == l || !lok[l2] || !fr[(size_t)l2 * N + r]) continue;
                relax((uint32_t)(((size_t)l2 * ND + 8) * N + r), g + via_cost, (uint8_t)(0x80 | (l << 4) | d), hw * heur[r]);
            }
        }
    }
    return -1;
}
