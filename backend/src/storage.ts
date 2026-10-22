export const ASSETS_BUCKET = "assets";

const importEsm = new Function(
  "specifier",
  "return import(specifier)"
) as <T = any>(specifier: string) => Promise<T>;

/**
 * Returns a Neon Object Storage client configured for the branch's `assets` bucket
 * using `files-sdk` and `files-sdk/neon`.
 * Uses the injected AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3, and AWS_REGION env vars.
 */
export async function getAssetsStorage() {
  const [{ Files }, { neon }] = await Promise.all([
    importEsm<{ Files: any }>("files-sdk"),
    importEsm<{ neon: any }>("files-sdk/neon"),
  ]);
  return new Files({
    adapter: neon({ bucket: ASSETS_BUCKET }),
  });
}

export async function uploadWorkshopAsset(
  key: string,
  body: Buffer | Uint8Array | string,
  contentType = "application/octet-stream"
): Promise<{ key: string; presignedUrl: string }> {
  const files = await getAssetsStorage();
  await files.upload(key, body, { contentType });
  const presignedUrl = await files.url(key, { expiresIn: 3600 });
  return { key, presignedUrl };
}

export async function downloadWorkshopAsset(key: string): Promise<Uint8Array> {
  const files = await getAssetsStorage();
  const file = await files.download(key);
  return new Uint8Array(await file.arrayBuffer());
}

export async function getWorkshopAssetPresignedUrl(
  key: string,
  expiresIn = 3600
): Promise<string> {
  const files = await getAssetsStorage();
  return files.url(key, { expiresIn });
}

export async function workshopAssetExists(key: string): Promise<boolean> {
  const files = await getAssetsStorage();
  return files.exists(key);
}

export async function deleteWorkshopAsset(key: string): Promise<void> {
  const files = await getAssetsStorage();
  await files.delete(key);
}
