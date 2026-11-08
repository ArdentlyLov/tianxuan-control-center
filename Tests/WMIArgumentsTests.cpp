#include <cstdint>
#include <cassert>
#include <cstring>
#include <cstdio>
#include "../Drivers/VelaAsusWMI/WMIArguments.hpp"

int main() {
    VelaWMIArguments<uint32_t> read(0x00120075);
    assert(sizeof(read) == 20);
    assert(read.words[0] == 0x00120075);
    assert(read.words[1] == 0 && read.words[2] == 0 && read.words[3] == 0 && read.words[4] == 0);
    const unsigned char expected[20] = {0x75, 0, 0x12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    assert(std::memcmp(&read, expected, sizeof(expected)) == 0);
    VelaWMIArguments<uint32_t> rgb(0x00100056, 0x40FF01B4, 0xEB20);
    assert(rgb.words[1] == 0x40FF01B4 && rgb.words[2] == 0xEB20);
    assert(rgb.words[3] == 0 && rgb.words[4] == 0);
    std::puts("PASS: 6 actual kernel WMI argument checks");
}
