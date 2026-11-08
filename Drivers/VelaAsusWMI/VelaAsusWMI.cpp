// SPDX-License-Identifier: GPL-3.0-or-later
// ASUS management WMI bridge. Protocol references are listed in README.md.
// Firmware methods only: no physical memory mapping or raw EC writes.
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLocks.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <mach/kmod.h>
#include "WMIArguments.hpp"

static const UInt32 DSTS = 0x53545344, DEVS = 0x53564544;
static const UInt32 Presence = 0x10000;
static const UInt32 Thermal = 0x00120075, FanBoost = 0x00110018;
static const UInt32 Keyboard = 0x00050021, Charge = 0x00120057;
static const UInt32 CPUFan = 0x00110013, GPUFan = 0x00110014;
static const UInt32 CPUCurve = 0x00110024, GPUCurve = 0x00110025;
static const UInt32 RGB = 0x00100056, RGB2 = 0x0010005A;

class VelaAsusWMI : public IOService {
    OSDeclareDefaultStructors(VelaAsusWMI)
    using super = IOService;
    IOACPIPlatformDevice *acpi = nullptr;
    IOLock *firmwareLock = nullptr;
    IOLock *probeLock = nullptr;
    bool firmwareProbed = false;
    char method[5] = {};
    UInt32 thermalDevice = 0, rgbDevice = 0;
    bool keyboard = false, charge = false, cpuFan = false, gpuFan = false;
    bool cpuCurve = false, gpuCurve = false;
    bool rgbSecondary = false;

    bool findManagementMethod(IOACPIPlatformDevice *device) {
        OSObject *object = nullptr;
        if (device->evaluateObject("_WDG", &object) != kIOReturnSuccess || !object) return false;
        const OSData *data = OSDynamicCast(OSData, object);
        // ACPI encoding of 97845ED0-4E6D-11DE-8A39-0800200C9A66.
        const UInt8 guid[16] = {0xD0,0x5E,0x84,0x97,0x6D,0x4E,0xDE,0x11,
                               0x8A,0x39,0x08,0x00,0x20,0x0C,0x9A,0x66};
        bool found = false;
        if (data) {
            const UInt8 *bytes = static_cast<const UInt8 *>(data->getBytesNoCopy());
            for (unsigned i = 0; i + 20 <= data->getLength(); i += 20) {
                if (memcmp(bytes + i, guid, 16) || !(bytes[i + 19] & 2)) continue;
                method[0] = 'W'; method[1] = 'M';
                method[2] = static_cast<char>(bytes[i + 16]); method[3] = static_cast<char>(bytes[i + 17]); method[4] = 0;
                found = device->validateObject(method) == kIOReturnSuccess;
                if (found) break;
            }
        }
        object->release();
        return found;
    }

    IOReturn evaluate(UInt32 operation, const UInt8 *payload, unsigned size, OSObject **output) {
        if (!acpi || !firmwareLock || isInactive()) return kIOReturnNotReady;
        if (!payload || size != 20) return kIOReturnBadArgument;
        OSNumber *instance = OSNumber::withNumber(static_cast<UInt64>(0), 32);
        OSNumber *op = OSNumber::withNumber(operation, 32);
        OSData *buffer = OSData::withBytes(payload, size);
        if (!instance || !op || !buffer) {
            if (instance) instance->release();
            if (op) op->release();
            if (buffer) buffer->release();
            return kIOReturnNoMemory;
        }
        OSObject *params[] = {instance, op, buffer};
        IOLockLock(firmwareLock);
        const IOReturn result = acpi->evaluateObject(method, output, params, 3);
        IOLockUnlock(firmwareLock);
        buffer->release(); op->release(); instance->release();
        return result;
    }

    bool present(UInt32 device) {
        UInt32 value = 0;
        return getStatus(device, &value) == kIOReturnSuccess && (value & Presence);
    }

public:
    bool start(IOService *provider) override {
        if (!super::start(provider)) return false;
        // Name-based RTTI avoids an unexported IOACPIPlatformDevice::metaClass
        // data symbol, which this machine's boot KC resolves to address zero.
        auto device = provider ? static_cast<IOACPIPlatformDevice *>(provider->metaCast("IOACPIPlatformDevice")) : nullptr;
        if (!device) return false;
        firmwareLock = IOLockAlloc();
        probeLock = IOLockAlloc();
        if (!firmwareLock || !probeLock) return false;
        acpi = device;
        // Do not evaluate even _WDG at boot. The user explicitly probes after login.
        setProperty("ProtocolVersion", 2, 32);
        setProperty("DriverVersion", "1.0.2");
        setProperty("FirmwareProbeState", "not-run");
        setProperty("FirmwareProbed", false);
        setProperty("NoFirmwareCallsAtBoot", true);
        publishCapabilities();
        registerService();
        return true;
    }

    bool isFirmwareProbed() {
        if (!probeLock) return false;
        IOLockLock(probeLock);
        const bool result = firmwareProbed;
        IOLockUnlock(probeLock);
        return result;
    }

    IOReturn probeFirmware() {
        if (!acpi || !probeLock || isInactive()) return kIOReturnNotReady;
        IOLockLock(probeLock);
        if (firmwareProbed) { IOLockUnlock(probeLock); return kIOReturnSuccess; }
        setProperty("FirmwareProbeState", "running");
        if (!findManagementMethod(acpi)) {
            setProperty("FirmwareProbeState", "management-guid-not-found");
            IOLockUnlock(probeLock);
            return kIOReturnUnsupported;
        }
        thermalDevice = present(Thermal) ? Thermal : (present(FanBoost) ? FanBoost : 0);
        keyboard = present(Keyboard); charge = present(Charge);
        cpuFan = present(CPUFan); gpuFan = present(GPUFan);
        rgbSecondary = present(RGB2);
        rgbDevice = present(RGB) ? RGB : (rgbSecondary ? RGB2 : 0);
        UInt8 curve[16];
        cpuCurve = getCurve(CPUCurve, 0, curve) == kIOReturnSuccess;
        gpuCurve = getCurve(GPUCurve, 0, curve) == kIOReturnSuccess;
        setProperty("WMIManagementMethod", method);
        publishCapabilities();
        firmwareProbed = true;
        setProperty("FirmwareProbed", true);
        setProperty("FirmwareProbeState", "complete");
        IOLockUnlock(probeLock);
        return kIOReturnSuccess;
    }

    void publishCapabilities() {
        setProperty("ThermalDevice", thermalDevice, 32);
        setProperty("KeyboardDevice", keyboard ? Keyboard : 0, 32);
        setProperty("ChargeDevice", charge ? Charge : 0, 32);
        setProperty("CPUFanDevice", cpuFan ? CPUFan : 0, 32);
        setProperty("GPUFanDevice", gpuFan ? GPUFan : 0, 32);
        setProperty("CPUCurveDevice", cpuCurve ? CPUCurve : 0, 32);
        setProperty("GPUCurveDevice", gpuCurve ? GPUCurve : 0, 32);
        setProperty("RGBDevice", rgbDevice, 32);
        setProperty("RGBSecondaryDevice", rgbSecondary ? RGB2 : 0, 32);
        setProperty("ReadOnlyAtBoot", true);
    }

    void free() override {
        if (firmwareLock) { IOLockFree(firmwareLock); firmwareLock = nullptr; }
        if (probeLock) { IOLockFree(probeLock); probeLock = nullptr; }
        super::free();
    }

    IOReturn getStatus(UInt32 device, UInt32 *value) {
        switch (device) {
        case Thermal: case FanBoost: case Keyboard: case Charge: case CPUFan: case GPUFan: case RGB: case RGB2: break;
        default: return kIOReturnBadArgument;
        }
        VelaWMIArguments<UInt32> args(device);
        OSObject *object = nullptr;
        IOReturn result = evaluate(DSTS, reinterpret_cast<UInt8 *>(&args), sizeof(args), &object);
        if (result == kIOReturnSuccess) {
            auto number = OSDynamicCast(OSNumber, object);
            if (!number) result = kIOReturnUnsupported;
            else {
                *value = number->unsigned32BitValue();
                if (*value == 0xFFFFFFFE || *value == 0xFFFFFFFF) result = kIOReturnUnsupported;
            }
        }
        if (object) object->release();
        return result;
    }

    IOReturn setDevice(UInt32 device, UInt32 value, UInt32 extra, UInt32 *response) {
        if (device == thermalDevice && thermalDevice) {
            if (value > 2 || extra) return kIOReturnBadArgument;
        } else if (device == Keyboard && keyboard) {
            if (value < 0x80 || value > 0x83 || extra) return kIOReturnBadArgument;
        } else if (device == Charge && charge) {
            if (value < 40 || value > 100 || extra) return kIOReturnBadArgument;
        } else if ((device == rgbDevice && rgbDevice) || (device == RGB2 && rgbSecondary)) {
            const UInt32 command = value & 255, mode = (value >> 8) & 255;
            const UInt32 speed = (extra >> 8) & 255;
            if ((command != 0xB3 && command != 0xB4) || (mode > 2 && mode != 10) ||
                (extra & 0xFFFF0000) || (speed != 0xE1 && speed != 0xEB && speed != 0xF5)) return kIOReturnBadArgument;
        } else return kIOReturnUnsupported;
        VelaWMIArguments<UInt32> args(device, value, extra);
        OSObject *object = nullptr;
        IOReturn result = evaluate(DEVS, reinterpret_cast<UInt8 *>(&args), sizeof(args), &object);
        if (result == kIOReturnSuccess) {
            auto number = OSDynamicCast(OSNumber, object);
            if (!number) result = kIOReturnUnsupported;
            else { *response = number->unsigned32BitValue(); if (*response > 1) result = kIOReturnError; }
        }
        if (object) object->release();
        return result;
    }

    IOReturn getCurve(UInt32 device, UInt32 slot, UInt8 *curve) {
        if ((device != CPUCurve && device != GPUCurve) || slot > 2) return kIOReturnBadArgument;
        VelaWMIArguments<UInt32> args(device, slot);
        OSObject *object = nullptr;
        IOReturn result = evaluate(DSTS, reinterpret_cast<UInt8 *>(&args), sizeof(args), &object);
        if (result == kIOReturnSuccess) {
            auto data = OSDynamicCast(OSData, object);
            // This FX507ZM DSDT returns a 32-byte buffer with the 16 curve
            // bytes first. Do not reject that documented firmware padding.
            if (!data || (data->getLength() != 16 && data->getLength() != 32)) result = kIOReturnUnsupported;
            else memcpy(curve, data->getBytesNoCopy(), 16);
        }
        if (object) object->release();
        return result;
    }

    IOReturn setCurve(UInt32 device, const UInt8 *curve, UInt32 *response) {
        if (!((device == CPUCurve && cpuCurve) || (device == GPUCurve && gpuCurve))) return kIOReturnUnsupported;
        for (unsigned i = 0; i < 8; ++i) {
            if (curve[i] < 20 || curve[i] > 110 || curve[i + 8] > 100) return kIOReturnBadArgument;
            if (i && (curve[i] < curve[i - 1] || curve[i + 8] < curve[i + 7])) return kIOReturnBadArgument;
        }
        // DEVS payload: device ID followed by eight temperatures and eight duties.
        UInt8 payload[20]; memcpy(payload, &device, 4); memcpy(payload + 4, curve, 16);
        OSObject *object = nullptr;
        IOReturn result = evaluate(DEVS, payload, sizeof(payload), &object);
        if (result == kIOReturnSuccess) {
            auto number = OSDynamicCast(OSNumber, object);
            if (!number) result = kIOReturnUnsupported;
            else { *response = number->unsigned32BitValue(); if (*response > 1) result = kIOReturnError; }
        }
        if (object) object->release();
        return result;
    }
};

class VelaAsusWMIUserClient : public IOUserClient {
    OSDeclareDefaultStructors(VelaAsusWMIUserClient)
    using super = IOUserClient;
    VelaAsusWMI *driver = nullptr;
    bool administrator = false;
public:
    bool initWithTask(task_t task, void *token, UInt32 type, OSDictionary *properties) override {
        if (type != 0 || !super::initWithTask(task, token, type, properties)) return false;
        administrator = clientHasPrivilege(task, kIOClientPrivilegeAdministrator) == kIOReturnSuccess;
        setProperty("IOUserClientDefaultLocking", true);
        return true;
    }
    bool start(IOService *provider) override {
        driver = OSDynamicCast(VelaAsusWMI, provider);
        return driver && super::start(provider);
    }
    IOReturn clientClose() override { terminate(); return kIOReturnSuccess; }

    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                           IOExternalMethodDispatch *dispatch = nullptr,
                           OSObject *target = nullptr, void *reference = nullptr) override {
        if (!driver || isInactive() || driver->isInactive()) return kIOReturnNotReady;
        if (!args || args->structureInputDescriptor || args->structureOutputDescriptor || args->asyncWakePort) return kIOReturnBadArgument;
        if (selector > 4) return kIOReturnUnsupported;
        if (selector == 4) {
            if (args->scalarInputCount || args->structureInputSize || args->structureOutputSize ||
                args->scalarOutputCount != 1 || !args->scalarOutput) return kIOReturnBadArgument;
            const IOReturn result = driver->probeFirmware();
            args->scalarOutput[0] = result == kIOReturnSuccess ? 1 : 0;
            return result;
        }
        if (!driver->isFirmwareProbed()) return kIOReturnNotReady;
        if ((selector == 1 || selector == 3) && !administrator) return kIOReturnNotPrivileged;
        const UInt32 inputCount = selector == 0 || selector == 3 ? 1 : (selector == 1 ? 3 : 2);
        if (args->scalarInputCount != inputCount || !args->scalarInput) return kIOReturnBadArgument;
        for (unsigned i = 0; i < inputCount; ++i) if (args->scalarInput[i] > 0xFFFFFFFF) return kIOReturnBadArgument;
        const UInt32 device = static_cast<UInt32>(args->scalarInput[0]);
        if (selector == 2) {
            if (args->structureInputSize || args->scalarOutputCount ||
                args->structureOutputSize != 16 || !args->structureOutput) return kIOReturnBadArgument;
            return driver->getCurve(device, static_cast<UInt32>(args->scalarInput[1]), static_cast<UInt8 *>(args->structureOutput));
        }
        if (args->scalarOutputCount != 1 || !args->scalarOutput || args->structureOutputSize) return kIOReturnBadArgument;
        UInt32 value = 0;
        IOReturn result;
        if (selector == 3) {
            if (args->structureInputSize != 16 || !args->structureInput) return kIOReturnBadArgument;
            result = driver->setCurve(device, static_cast<const UInt8 *>(args->structureInput), &value);
        } else {
            if (args->structureInputSize) return kIOReturnBadArgument;
            result = selector == 0 ? driver->getStatus(device, &value) :
                driver->setDevice(device, static_cast<UInt32>(args->scalarInput[1]),
                                  static_cast<UInt32>(args->scalarInput[2]), &value);
        }
        args->scalarOutput[0] = value;
        return result;
    }
};

OSDefineMetaClassAndStructors(VelaAsusWMI, IOService)
OSDefineMetaClassAndStructors(VelaAsusWMIUserClient, IOUserClient)

// OSKext initializes C++ constructors before invoking the module entry point.
extern "C" {
    kern_return_t VelaAsusWMI_start(kmod_info_t *, void *) { return KERN_SUCCESS; }
    kern_return_t VelaAsusWMI_stop(kmod_info_t *, void *) { return KERN_SUCCESS; }
    KMOD_EXPLICIT_DECL(dev.vela.VelaAsusWMI, "1.0.2", VelaAsusWMI_start, VelaAsusWMI_stop)
    __private_extern__ int _kext_apple_cc = __APPLE_CC__;
}
