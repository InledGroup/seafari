# Seafari

Seafari is a browser made on top of Mozilla Firefox. Gets daily updates from Mozilla source and is fully open-source.  
Seafari replicates the UI and look of Safari, the browser of MacOS.  Seafari is WIP, so expect visual bugs or incoherences.

![Seafari Logo](seafari.png)

##  Features

- **Safari Aesthetic:** Complete UI overhaul using the MacTahoe theme and custom CSS.
- **Privacy First:** Pre-installed and force-enabled **uBlock Origin**.
- **Dynamic Styling:** Pre-installed **Adaptive Tab Bar Colour** for a seamless look.
- **Enterprise Ready:** Custom policies to disable telemetry, data collection, and unwanted Seafari features.
- **Multi-Arch Support:** Available for both **AMD64 (x86_64)** and **ARM64 (aarch64)**.
- **Multiple Formats:** Distributed as `.deb`, `.rpm`, and `AppImage`.

## Installation

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

## Development

To build Seafari locally:

1. Clone the repository:
   ```bash
   git clone https://github.com/InledGroup/seafari.git
   cd seafari
   ```
2. Run the build script (requires `dpkg-dev`, `binutils`, and `fpm` for RPM):
   ```bash
   ./build_seafari.sh amd64 --skip-rpm
   ```
`---skip-rpm` is optional, only is you want to generate a .deb and appimage faster.  

3. Clean your system for unwanted old configs
```bash
rm -rf ~/.mozilla/seafari-profile
```
4. Run the Appimage
```bash
./Seafari-x86_64.AppImage
```

## License and acknowledgment

Seafari is distributed under the same terms as Mozilla Firefox.  
The code made by Inled is licensed under [MIT-INLED](https://license.inled.es) 
The base theme is based on [Vinceliuice/MacTahoe GTK Theme](https://github.com/vinceliuice/MacTahoe-gtk-theme/tree/main/other/firefox).  

## Legal  
Seafari is a product of Inled Group, which is not affiliated with Mozilla or Apple.
If you'd like to integrate Seafari into your distribution, we would greatly appreciate it, and it would be even better if you mentioned us.
Feel free to contact us with any questions. We welcome pull requests and issues.
v1.3
