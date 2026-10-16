import { FileInput } from '@sarvam-mobile/core';

/**
 * Creates a FileInput descriptor object from a local React Native file URI.
 *
 * @param uri Local file path or content URI (e.g. 'file:///data/user/0/.../sample.wav' or 'content://...')
 * @param name Optional display filename. Defaults to the trailing component of the URI.
 * @param mimeType Optional MIME type. Defaults to 'application/octet-stream' (or inferred from audio extensions).
 */
export function fromReactNativeUri(
  uri: string,
  name?: string,
  mimeType?: string
): FileInput {
  const resolvedName = name || uri.split('/').pop()?.split('?')[0] || 'audio.wav';
  let resolvedType = mimeType;
  if (!resolvedType) {
    if (resolvedName.endsWith('.wav')) {
      resolvedType = 'audio/wav';
    } else if (resolvedName.endsWith('.mp3')) {
      resolvedType = 'audio/mpeg';
    } else if (resolvedName.endsWith('.m4a') || resolvedName.endsWith('.aac')) {
      resolvedType = 'audio/aac';
    } else if (resolvedName.endsWith('.ogg') || resolvedName.endsWith('.opus')) {
      resolvedType = 'audio/ogg';
    } else {
      resolvedType = 'application/octet-stream';
    }
  }

  return {
    uri,
    name: resolvedName,
    type: resolvedType,
  };
}
