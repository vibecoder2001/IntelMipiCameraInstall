# 📸 IntelMipiCamera

**IntelMipiCamera** is a streamlined Windows installer for Intel IPU / MIPI camera drivers across multiple Intel platforms.

It automatically detects your hardware, installs the correct core drivers, and enables supported camera sensors with minimal manual work.

Built for reliability, reproducibility, and clean system behavior — no leftover staging files, no driver spam, and no unnecessary reinstalls.

> 🤖 This installer is built with the help of **ChatGPT**, acting as a development copilot to design and refine the NSIS build system.

---

## ✨ Features

✅ Automatic platform detection via **Intel IPU PCI IDs**  
✅ Supports multiple Intel generations  
✅ Sensor installs deduplicated (core drivers install only once)  
✅ Temporary payload extraction — nothing left behind on disk  
✅ Clean uninstaller for overlay files  
✅ GitHub Actions build pipeline  
✅ No test-signing required (IMX208 intentionally disabled)  

---

## 🧠 Supported Platforms

| Platform | Status |
|--------|--------|
| **Kaby Lake (KBL)** | ✅ Supported |
| **Jasper Lake (JSL)** | ✅ Supported |
| **Tiger Lake (TGL)** | ✅ Supported |
| **Alder / Raptor Lake (ADL/RPL/ADL-N)** | ✅ Supported |
| **Meteor Lake (MTL)** | ✅ Supported |

Detection is performed using the Intel IPU PCI device to ensure accurate hardware matching.

---

## 📷 Supported Sensors

| Sensor | Platforms |
|--------|------------|
| IMX258 | KBL |
| OV2740 | ADL / TGL |
| OV5675 | ADL / JSL |
| OV8856 | ADL / JSL |
| HI556 | ADL / MTL |
| OV08x40 | MTL |

> ⚠️ **IMX208 is currently disabled** because the available driver is Intel-signed but not Microsoft-signed.

---

## 🔧 Platform Notes

### Jasper Lake
Requires:

```

graph_settings + AIQB + CPF → System32\drivers

```

The installer copies these **before driver installation** so the INF can properly resolve the pipeline configuration.

---

### Tiger Lake

```

graph_settings → System32\drivers
AIQB + CPF → System32 AND SysWOW64

```

This mirrors common OEM layouts and prevents camera pipeline initialization failures.

---

## 🚀 Installation

Download the latest release from the **Releases** page and run:

```

IntelMipiCamera.<version>-installer.exe

```

The installer will:

1. Detect your platform  
2. Auto-select compatible sensors  
3. Install core drivers once  
4. Apply required overlays  

---

## 🧼 Uninstall Behavior

The uninstaller removes only files introduced by this installer:

- JSL overlay configs  
- TGL renamed pipeline files  
- Installer registration  

Driver packages themselves remain in the Windows driver store (standard Windows behavior).

---

## 🛠️ Building From Source

### Requirements

- Windows  
- NSIS  
- Git (with submodules)

Clone the repo:

```

git clone --recurse-submodules <repo>

```

Build:

```

makensis IntelMipiCamera.nsi

```

Output:

```

IntelMipiCamera.<version>-installer.exe

```

---

## 🤖 Built With ChatGPT

This project intentionally embraces modern tooling.

ChatGPT was used as a **development copilot** to help:

- Architect the NSIS installer  
- Deduplicate driver logic  
- Prevent filesystem redirection issues  
- Design hardware detection  
- Create the GitHub Actions pipeline  

All logic is still validated — AI accelerates development, it does not replace engineering judgment.

---

## ⚠️ Disclaimer

This project installs low-level camera drivers.

While care has been taken to mirror OEM behavior:

👉 **Use at your own risk.**

You should be comfortable recovering Windows drivers manually if something goes wrong.

---

## ❤️ Contributing

Pull requests are welcome!

Particularly helpful contributions include:

- Sensor validation  
- Additional pipeline configs  
- Platform testing  
- Driver packaging improvements  

---

## 🌟 Why This Exists

Intel IPU camera stacks are notoriously fragmented across OEMs.

This project exists to provide:

👉 a **clean, reproducible, vendor-neutral installer**  
👉 without mystery scripts  
👉 without registry clutter  
👉 without filesystem leftovers  

Just drivers — installed correctly.

---

**Enjoy working cameras 🙂**