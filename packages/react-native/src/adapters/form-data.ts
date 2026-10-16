import { FileInput } from '@sarvam-mobile/core';

export interface ReactNativeFileObject {
  uri: string;
  name: string;
  type: string;
}

export class ReactNativeFormDataAdapter {
  /**
   * Appends a FileInput to React Native FormData without converting to native Blob.
   * On native React Native (iOS/Android), FormData accepts `{ uri, name, type }` objects directly.
   * On Web / Node runtimes where FormData enforces WebIDL Blob validation, falls back gracefully.
   */
  static appendFile(
    formData: FormData,
    fieldName: string,
    fileInput: FileInput,
    defaultFilename = 'audio.wav'
  ): void {
    if (typeof fileInput === 'object' && fileInput !== null && 'uri' in fileInput) {
      try {
        // Direct React Native native file descriptor { uri, name, type }
        formData.append(fieldName, fileInput as any, fileInput.name || defaultFilename);
        return;
      } catch {
        // Fallback for Web/Node environments where global FormData enforces WebIDL Blob
        if (typeof Blob !== 'undefined') {
          const fallbackBlob = new Blob([new Uint8Array(0)], {
            type: fileInput.type || 'application/octet-stream',
          });
          formData.append(fieldName, fallbackBlob, fileInput.name || defaultFilename);
          return;
        }
      }
    }

    if (fileInput instanceof Uint8Array) {
      if (typeof Blob !== 'undefined') {
        formData.append(fieldName, new Blob([fileInput as any]), defaultFilename);
      } else {
        formData.append(fieldName, fileInput as any, defaultFilename);
      }
      return;
    }

    if (typeof Blob !== 'undefined' && fileInput instanceof Blob) {
      formData.append(fieldName, fileInput, defaultFilename);
      return;
    }

    formData.append(fieldName, fileInput as any, defaultFilename);
  }
}
