## Reglas de Compilación y Distribución de APKs

1. **Compilación bajo orden previa**: Compila la APK únicamente cuando el usuario lo solicite o dé una orden previa explícita (no lo hagas de forma automática tras realizar cambios de código). Cuando lo hagas, compila en modo release optimizado para la arquitectura ARM64 (Honor X6c y dispositivos modernos) usando:
   ```bash
   flutter build apk --release --target-platform android-arm64
   ```
2. **Ubicación de Distribución**: Al finalizar la compilación, copia el archivo APK resultante:
   * **Origen**: `licores_app/build/app/outputs/flutter-apk/app-release.apk`
   * **Destino**: `apks/app-release.apk` (en la raíz del espacio de trabajo).
3. **Presentación**: Proporciona al usuario la ruta absoluta y el enlace local (`file:///...`) al archivo copiado en la carpeta `apks/` para facilitar su descarga directa.
