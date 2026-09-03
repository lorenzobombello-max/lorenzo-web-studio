import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { createOperatorMessagesRealtime } from "../assets/js/operator-messages.mjs";

test("Messages uses Realtime delivery events with one guarded eight-second recovery lifecycle", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-messages.mjs", import.meta.url), "utf8");
  assert.match(source, /createOperatorAutoRefresh\(\{[\s\S]*moduleKey: "messages"/);
  assert.match(source, /loadMessages\(\{ background: true \}\)/);
  assert.match(source, /workspace\.dataset\.panelMode === "compose" \|\| sending \|\| markingRead\.size > 0/);
  assert.match(source, /if \(refreshed \|\| !background\) renderList\(\)/);
  assert.match(source, /selectedId = messages\.some\(\(message\)=>message\.id === selectedId\) \? selectedId : null/);
  assert.match(source, /setInvalidationPublisher\(publisher\)/);
  assert.match(source, /createOperatorMessagesRealtime\(\{ client, onInvalidate: autoRefresh\.request \}\)/);
  assert.match(source, /event: "INSERT"[\s\S]*table: "operator_message_recipients"/);
  assert.match(source, /client\.removeChannel\(channel\)/);
  assert.match(source, /autoRefresh\.dispose\(\)/);
  assert.doesNotMatch(source, /location\.reload|window\.location|setTimeout\([^)]*loadMessages/);
});

test("Messages Realtime invalidates on delivery, recovers on reconnect, and disposes once", async ()=>{
  const listeners = [];
  let subscribeListener = null;
  let invalidations = 0;
  let removals = 0;
  const channel = {
    on(type, filter, listener) { listeners.push({ type, filter, listener }); return this; },
    subscribe(listener) { subscribeListener = listener; return this; },
  };
  const realtime = createOperatorMessagesRealtime({
    client: {
      channel: (name)=>{ assert.equal(name, "messages-test"); return channel; },
      removeChannel: async (removed)=>{ assert.equal(removed, channel); removals += 1; },
    },
    channelName: "messages-test",
    onInvalidate: async ()=>{ invalidations += 1; },
  });
  assert.deepEqual(listeners.map(({ type, filter })=>[type, filter.event, filter.table]), [
    ["postgres_changes", "INSERT", "operator_message_recipients"],
    ["postgres_changes", "UPDATE", "operator_message_recipients"],
  ]);
  subscribeListener("SUBSCRIBED");
  assert.equal(invalidations, 0);
  listeners[0].listener();
  assert.equal(invalidations, 1);
  subscribeListener("CHANNEL_ERROR");
  subscribeListener("SUBSCRIBED");
  assert.equal(invalidations, 2);
  realtime.dispose();
  realtime.dispose();
  listeners[0].listener();
  assert.equal(invalidations, 2);
  assert.equal(removals, 1);
});