import assert from "node:assert/strict";
import test from "node:test";

import { createOperatorRefreshHeartbeat } from "../assets/js/operator-refresh-heartbeat.mjs";

class ElementStub {
  constructor(name) {
    this.name = name;
    this.children = [];
    this.parentElement = null;
    this.dataset = {};
    this.attributes = new Map();
    this.className = "";
    this.textContent = "";
    this.listeners = new Map();
    this.classList = { add: (value)=>{ this.className = value; } };
  }
  append(...elements) {
    for (const element of elements) {
      element.remove();
      element.parentElement = this;
      this.children.push(element);
    }
  }
  before(element) {
    const index = this.parentElement.children.indexOf(this);
    element.remove();
    element.parentElement = this.parentElement;
    this.parentElement.children.splice(index, 0, element);
  }
  remove() {
    if (!this.parentElement) return;
    const index = this.parentElement.children.indexOf(this);
    if (index >= 0) this.parentElement.children.splice(index, 1);
    this.parentElement = null;
  }
  setAttribute(name, value) { this.attributes.set(name, value); }
  addEventListener(name, listener) { this.listeners.set(name, listener); }
  removeEventListener(name, listener) {
    if (this.listeners.get(name) === listener) this.listeners.delete(name);
  }
  dispatchEvent(event) {
    event.target = this;
    this.listeners.get(event.type)?.(event);
  }
  querySelector(selector) {
    const moduleKey = selector.match(/data-operator-refresh-heartbeat="([^"]+)"/)?.[1];
    return this.children.find((child)=>child.dataset.operatorRefreshHeartbeat === moduleKey)
      || this.children.map((child)=>child.querySelector(selector)).find(Boolean) || null;
  }
}

function documentStub() {
  return {
    createElement: (name)=>new ElementStub(name),
    createElementNS: (_namespace, name)=>new ElementStub(name),
  };
}

test("Operator refresh heartbeat presents lifecycle health without owning a timer", () => {
  const root = documentStub();
  const parent = new ElementStub("div");
  const title = new ElementStub("h1");
  parent.append(title);
  const heartbeat = createOperatorRefreshHeartbeat({
    root,
    moduleKey: "finance",
    titleElement: title,
  });
  const indicator = parent.children[0].children[1];
  const path = indicator.children[0].children[0];
  const label = indicator.children[1];
  assert.equal(indicator.dataset.state, "idle");
  assert.equal(label.textContent, "Wachten op verversing");
  assert.equal(label.className, "operator-refresh-heartbeat__label");
  heartbeat.update({ moduleKey: "messages", state: "refreshing" });
  assert.equal(indicator.dataset.state, "idle");
  heartbeat.update({ moduleKey: "finance", state: "refreshing" });
  assert.equal(indicator.dataset.state, "refreshing");
  heartbeat.update({ moduleKey: "finance", state: "success" });
  assert.equal(indicator.dataset.state, "refreshing");
  path.dispatchEvent({ type: "animationend", animationName: "unrelated-animation" });
  assert.equal(indicator.dataset.state, "refreshing");
  path.dispatchEvent({ type: "animationend", animationName: "operator-heartbeat-flow" });
  assert.equal(indicator.dataset.state, "success");
  heartbeat.update({ moduleKey: "finance", state: "refreshing" });
  heartbeat.update({ moduleKey: "finance", state: "idle" });
  assert.equal(indicator.dataset.state, "idle");
  heartbeat.update({ moduleKey: "finance", state: "stale" });
  assert.equal(indicator.dataset.state, "stale");
  path.getAnimations = ()=>[];
  heartbeat.update({ moduleKey: "finance", state: "refreshing" });
  heartbeat.update({ moduleKey: "finance", state: "success" });
  assert.equal(indicator.dataset.state, "success");
  assert.equal(createOperatorRefreshHeartbeat({ root, moduleKey: "finance", titleElement: title }), heartbeat);
  heartbeat.dispose();
  assert.deepEqual(parent.children, [title]);
});
