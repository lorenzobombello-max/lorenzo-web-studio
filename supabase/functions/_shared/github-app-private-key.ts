type DerElement = Readonly<{
  tag: number;
  contentStart: number;
  contentEnd: number;
  next: number;
}>;

function invalid(): never {
  throw new Error("GITHUB_APP_PRIVATE_KEY_INVALID");
}

function readDerElement(bytes: Uint8Array, offset: number): DerElement {
  if (offset < 0 || offset + 2 > bytes.length) invalid();
  const tag = bytes[offset];
  const firstLength = bytes[offset + 1];
  let length = firstLength;
  let lengthBytes = 1;
  if ((firstLength & 0x80) !== 0) {
    const count = firstLength & 0x7f;
    if (count < 1 || count > 4 || offset + 2 + count > bytes.length) invalid();
    length = 0;
    lengthBytes += count;
    for (let index = 0; index < count; index += 1) {
      length = length * 256 + bytes[offset + 2 + index];
    }
    if (length < 128) invalid();
  }
  const contentStart = offset + 1 + lengthBytes;
  const contentEnd = contentStart + length;
  if (contentEnd > bytes.length) invalid();
  return { tag, contentStart, contentEnd, next: contentEnd };
}

function sequenceChildren(bytes: Uint8Array): readonly DerElement[] {
  const outer = readDerElement(bytes, 0);
  if (outer.tag !== 0x30 || outer.next !== bytes.length) invalid();
  const children: DerElement[] = [];
  let offset = outer.contentStart;
  while (offset < outer.contentEnd) {
    const child = readDerElement(bytes, offset);
    children.push(child);
    offset = child.next;
  }
  if (offset !== outer.contentEnd) invalid();
  return children;
}

function validPkcs1(bytes: Uint8Array): boolean {
  try {
    const children = sequenceChildren(bytes);
    return children.length >= 9 &&
      children.every((child) => child.tag === 0x02);
  } catch {
    return false;
  }
}

const RSA_ENCRYPTION_OID = new Uint8Array([
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x01,
]);

function validPkcs8(bytes: Uint8Array): boolean {
  try {
    const children = sequenceChildren(bytes);
    if (
      children.length < 3 || children[0].tag !== 0x02 ||
      children[1].tag !== 0x30 || children[2].tag !== 0x04
    ) return false;
    const algorithmBytes = bytes.slice(
      children[1].contentStart,
      children[1].contentEnd,
    );
    const algorithmChildren = sequenceChildren(wrapDer(0x30, algorithmBytes));
    const oid = algorithmChildren[0];
    return oid?.tag === 0x06 &&
      bytesEqual(
        algorithmBytes.slice(oid.contentStart - 2, oid.contentEnd - 2),
        RSA_ENCRYPTION_OID,
      ) &&
      validPkcs1(bytes.slice(children[2].contentStart, children[2].contentEnd));
  } catch {
    return false;
  }
}

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function decodeBase64(value: string): Uint8Array {
  if (
    !value || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)
  ) invalid();
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    invalid();
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function parsePrivateKeyPem(value: string): Readonly<{
  format: "pkcs1" | "pkcs8";
  bytes: Uint8Array;
}> {
  const lines = value.replaceAll("\r\n", "\n").split("\n");
  const header = lines[0];
  const format = header === "-----BEGIN RSA PRIVATE KEY-----"
    ? "pkcs1"
    : header === "-----BEGIN PRIVATE KEY-----"
    ? "pkcs8"
    : invalid();
  const footer = format === "pkcs1"
    ? "-----END RSA PRIVATE KEY-----"
    : "-----END PRIVATE KEY-----";
  if (lines.length < 3 || lines.at(-1) !== footer) invalid();
  const bytes = decodeBase64(lines.slice(1, -1).join(""));
  if (!(format === "pkcs1" ? validPkcs1(bytes) : validPkcs8(bytes))) invalid();
  return { format, bytes };
}

function encodeDerLength(length: number): Uint8Array {
  if (length < 128) return new Uint8Array([length]);
  const encoded: number[] = [];
  for (let value = length; value > 0; value = Math.floor(value / 256)) {
    encoded.unshift(value & 0xff);
  }
  return new Uint8Array([0x80 | encoded.length, ...encoded]);
}

function wrapDer(tag: number, content: Uint8Array): Uint8Array {
  const length = encodeDerLength(content.length);
  const result = new Uint8Array(1 + length.length + content.length);
  result[0] = tag;
  result.set(length, 1);
  result.set(content, 1 + length.length);
  return result;
}

function concatBytes(...values: readonly Uint8Array[]): Uint8Array {
  const result = new Uint8Array(
    values.reduce((length, value) => length + value.length, 0),
  );
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.length;
  }
  return result;
}

function pkcs1ToPkcs8(pkcs1: Uint8Array): Uint8Array {
  const algorithm = wrapDer(
    0x30,
    concatBytes(
      wrapDer(0x06, RSA_ENCRYPTION_OID),
      new Uint8Array([0x05, 0x00]),
    ),
  );
  return wrapDer(
    0x30,
    concatBytes(
      new Uint8Array([0x02, 0x01, 0x00]),
      algorithm,
      wrapDer(0x04, pkcs1),
    ),
  );
}

function pkcs8Bytes(privateKey: string): Uint8Array {
  const parsed = parsePrivateKeyPem(privateKey);
  return parsed.format === "pkcs1" ? pkcs1ToPkcs8(parsed.bytes) : parsed.bytes;
}

export function normalizeGitHubAppPrivateKey(privateKey: string): string {
  const bytes = pkcs8Bytes(privateKey);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const body = btoa(binary).match(/.{1,64}/g)?.join("\n") || invalid();
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
}

export function isValidGitHubAppPrivateKey(privateKey: string): boolean {
  try {
    normalizeGitHubAppPrivateKey(privateKey);
    return true;
  } catch {
    return false;
  }
}

export function githubAppPrivateKeyToPkcs8(privateKey: string): ArrayBuffer {
  return Uint8Array.from(pkcs8Bytes(privateKey)).buffer;
}
