#pragma once
#include <cstdint>
#include <vector>
struct FqVideoFrame {
    int width = 0, height = 0, serial = 0;
    std::vector<uint8_t> pixels;
};
extern "C" int fq_cpu_video_factories();
void *fq_cpu_last_output();
bool fq_cpu_copy_frame(void *output, int previousSerial, FqVideoFrame &frame);
