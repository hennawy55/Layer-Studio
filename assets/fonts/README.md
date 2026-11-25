# Offline font bundle

Layer Studio packages **24 free font families** directly into the application:
- **12 Arabic families with Latin glyphs:** Cairo, Almarai, Alexandria, Amiri, Changa, Fustat, Mada, Harmattan, Kufam, Marhey, Oi, Rakkas.
- **12 Latin families:** Open Sans, Montserrat, Oswald, Lato, Poppins, Lora, Nunito, Raleway, Merriweather, Roboto, Inter, Archivo.

The build script retrieves each regular TTF and its matching SIL Open Font License notice from the official Google Fonts repository. It validates that Arabic families advertise both Arabic and Latin subsets before downloading them.

Run before `flutter pub get`:
- Linux/macOS: `bash tool/fetch_fonts.sh`
- Windows PowerShell: `./tool/fetch_fonts.ps1`

All font files are embedded in the APK and Windows application. The installed app does not download fonts and works offline. License notices are included under `assets/fonts/licenses/`.
