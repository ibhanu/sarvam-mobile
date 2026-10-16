import { FileInput } from '../transport/http.js';

/**
 * Appends a FileInput (Uint8Array, Blob, or React Native file object) to FormData.
 * Avoids Node.js built-ins and maintains compatibility across Web, Node, and React Native.
 */
export function appendFileInput(
  formData: FormData,
  fieldName: string,
  fileInput: FileInput,
  defaultFileName = 'file.bin'
): void {
  if (fileInput instanceof Uint8Array) {
    formData.append(fieldName, new Blob([fileInput as any]), defaultFileName);
  } else if (typeof Blob !== 'undefined' && fileInput instanceof Blob) {
    formData.append(fieldName, fileInput, defaultFileName);
  } else if (typeof fileInput === 'object' && fileInput !== null && 'uri' in fileInput) {
    formData.append(fieldName, fileInput as any);
  } else {
    formData.append(fieldName, fileInput as any);
  }
}
