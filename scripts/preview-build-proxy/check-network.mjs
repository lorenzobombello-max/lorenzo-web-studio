import net from "node:net";
import { pathToFileURL } from "node:url";

function probe(host, port, target) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host, port });
    const timer = setTimeout(() => { socket.destroy(); reject(new Error("NETWORK_TIMEOUT")); }, 5000);
    let response = "";
    socket.once("error", reject);
    socket.once("close", () => { clearTimeout(timer); if (target && !response.includes("\r\n")) reject(new Error("PROXY_RESPONSE_INVALID")); });
    socket.once("connect", () => {
      if (!target) { socket.destroy(); resolve(true); return; }
      socket.write(`CONNECT ${target}:443 HTTP/1.1\r\nHost: ${target}:443\r\n\r\n`);
    });
    socket.on("data", (chunk) => {
      response += chunk.toString();
      if (response.length > 4096) { socket.destroy(); reject(new Error("PROXY_RESPONSE_INVALID")); return; }
      if (response.includes("\r\n")) {
        socket.destroy();
        resolve(Number(response.match(/^HTTP\/1\.[01] ([0-9]{3}) /)?.[1]));
      }
    });
  });
}

export async function verifyProxyNetwork(proxyHost, request = probe) {
  let directReachable = false;
  try { directReachable = await request("registry.npmjs.org", 443); }
  catch { directReachable = false; }
  if (directReachable) throw new Error("DIRECT_EGRESS_NOT_BLOCKED");
  if (await request(proxyHost, 8888, "registry.npmjs.org") !== 200) throw new Error("NPM_PROXY_UNAVAILABLE");
  if (await request(proxyHost, 8888, "example.com") !== 403) throw new Error("PROXY_FILTER_NOT_ENFORCED");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) throw new Error("PROXY_HOST_REQUIRED");
  await verifyProxyNetwork(process.argv[2]);
}
