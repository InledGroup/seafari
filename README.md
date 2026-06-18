# 🧭 Seafari

Seafari is a professional-grade, Safari-styled web browser for Linux, built on top of a highly optimized and patched Firefox binary. It combines the privacy and extensibility of Firefox with the elegant aesthetic and user experience of macOS Safari.

![Seafari Logo](seafari.png)

## ✨ Features

- **Safari Aesthetic:** Complete UI overhaul using the MacTahoe theme and custom CSS.
- **Privacy First:** Pre-installed and force-enabled **uBlock Origin**.
- **Dynamic Styling:** Pre-installed **Adaptive Tab Bar Colour** for a seamless look.
- **Enterprise Ready:** Custom policies to disable telemetry, data collection, and unwanted Firefox features.
- **Multi-Arch Support:** Available for both **AMD64 (x86_64)** and **ARM64 (aarch64)**.
- **Multiple Formats:** Distributed as `.deb`, `.rpm`, and `AppImage`.

## 🚀 Installation

### Debian / Ubuntu / Mint (Recommended)

Add the InledGroup repository to your system:

```bash
curl -sS https://apt.inled.es/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/inled-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/inled-archive-keyring.gpg] https://apt.inled.es/ stable main" | sudo tee /etc/apt/sources.list.d/inled.list
sudo apt update
sudo apt install seafari
```

### Fedora / RHEL / CentOS

Download the latest `.rpm` from the [Releases](https://github.com/InledGroup/seafari/releases) page and install it:

```bash
sudo dnf install ./seafari-1.0.0-1.x86_64.rpm
```

### Generic Linux (AppImage)

Download the `.AppImage` from the [Releases](https://github.com/InledGroup/seafari/releases) page, make it executable, and run:

```bash
chmod +x Seafari-x86_64.AppImage
./Seafari-x86_64.AppImage
```

## 🛠️ Build from Source

To build Seafari locally:

1. Clone the repository:
   ```bash
   git clone https://github.com/InledGroup/seafari.git
   cd seafari
   ```
2. Run the build script (requires `dpkg-dev`, `binutils`, and `fpm` for RPM):
   ```bash
   ./build_seafari.sh amd64  # or arm64
   ```

## 📄 License

Seafari is distributed under the same terms as Mozilla Firefox. Theme components and branding are property of their respective owners.

v1.0
