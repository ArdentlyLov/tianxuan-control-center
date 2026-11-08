// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

// FX507ZM's WMNB unconditionally creates IIA0..IIA4 at offsets 0..16.
// Every request, including DSTS reads, must supply all five DWORDs.
template <typename Word>
struct VelaWMIArguments {
    Word words[5];
    VelaWMIArguments(Word device, Word value = 0, Word extra = 0,
                     Word third = 0, Word fourth = 0)
        : words{device, value, extra, third, fourth} {
        static_assert(sizeof(Word) == 4, "WMI arguments require 32-bit words");
    }
};
