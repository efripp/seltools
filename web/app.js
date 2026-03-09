const state = {
  dirHandle: null,
  handles: {
    desiredState: null,
    devicesDir: null,
    eventsDir: null,
  },
  view: "fleet",
  desiredState: {
    headers: [],
    rows: [],
    originalRows: [],
    selectedRowIndex: -1,
    dirty: false,
  },
  devices: new Map(),
  selectedDeviceSerial: "",
  inventoryBrowser: {
    selectedSerial: "",
    selectedEventIndex: -1,
    selectedSerEventIndex: -1,
    diffBaseIndex: -1,
    diffTargetIndex: -1,
  },
  serEvents: new Map(),
};

const el = {};

document.addEventListener("DOMContentLoaded", init);

function init() {
  bindElements();
  bindEvents();
  guardCapabilities();
  restoreSavedFolderHandle();
  renderAll();
}

function bindElements() {
  el.connectDataBtn = document.getElementById("connect-data-btn");
  el.saveCurrentBtn = document.getElementById("save-current-btn");
  el.revertCurrentBtn = document.getElementById("revert-current-btn");
  el.statusPill = document.getElementById("status-pill");
  el.statusMessage = document.getElementById("status-message");
  el.alertArea = document.getElementById("alert-area");
  el.navButtons = [...document.querySelectorAll(".nav-btn")];
  el.views = {
    fleet: document.getElementById("view-fleet"),
    metadata: document.getElementById("view-metadata"),
    inventory: document.getElementById("view-inventory"),
  };

  el.addRowBtn = document.getElementById("add-row-btn");
  el.deleteRowBtn = document.getElementById("delete-row-btn");
  el.fleetTable = document.getElementById("fleet-table");
  el.fleetRowEditor = document.getElementById("fleet-row-editor");
  el.fleetValidation = document.getElementById("fleet-validation");

  el.deviceList = document.getElementById("device-list");
  el.deviceName = document.getElementById("device-name");
  el.deviceDescription = document.getElementById("device-description");
  el.deviceEventsSummary = document.getElementById("device-events-summary");

  el.inventoryDeviceList = document.getElementById("inventory-device-list");
  el.inventoryEventList = document.getElementById("inventory-event-list");
  el.inventoryEventDetail = document.getElementById("inventory-event-detail");
  el.diffBase = document.getElementById("diff-base");
  el.diffTarget = document.getElementById("diff-target");
  el.inventoryDiffList = document.getElementById("inventory-diff-list");
  el.serEventList = document.getElementById("ser-event-list");
  el.serEventDetail = document.getElementById("ser-event-detail");
}

function bindEvents() {
  el.connectDataBtn.addEventListener("click", onConnectDataClick);
  el.saveCurrentBtn.addEventListener("click", onSaveCurrentClick);
  el.revertCurrentBtn.addEventListener("click", onRevertCurrentClick);
  el.addRowBtn.addEventListener("click", onAddRowClick);
  el.deleteRowBtn.addEventListener("click", onDeleteRowClick);
  el.deviceName.addEventListener("input", onDeviceMetadataInput);
  el.deviceDescription.addEventListener("input", onDeviceMetadataInput);
  el.diffBase.addEventListener("change", onDiffSelectionChange);
  el.diffTarget.addEventListener("change", onDiffSelectionChange);
  el.navButtons.forEach((btn) => {
    btn.addEventListener("click", () => switchView(btn.dataset.view));
  });
  window.addEventListener("beforeunload", (evt) => {
    if (hasUnsavedChanges()) {
      evt.preventDefault();
      evt.returnValue = "";
    }
  });
}

function guardCapabilities() {
  if (!window.showDirectoryPicker) {
    pushAlert(
      "error",
      "File System Access API is unavailable. Use modern Chrome or Edge on localhost/secure context."
    );
    el.connectDataBtn.disabled = true;
  }
}

async function onConnectDataClick() {
  clearAlerts();
  try {
    const savedHandle = await getSavedFolderHandle();
    if (savedHandle) {
      const savedPermission = await requestReadWritePermission(savedHandle);
      if (savedPermission === "granted") {
        await attachProjectFolder(savedHandle);
        setStatus("Connected to saved data folder.");
        return;
      }
      pushAlert(
        "info",
        "Saved folder access is unavailable. Select the data folder again to reconnect."
      );
    }

    pushAlert(
      "info",
      "Browse to /seltools/data when prompted."
    );
    const dirHandle = await window.showDirectoryPicker({ mode: "readwrite" });
    await attachProjectFolder(dirHandle);
    await saveFolderHandle(dirHandle);
    setStatus("Connected to data folder.");
  } catch (err) {
    if (err && err.name === "AbortError") {
      return;
    }
    pushAlert("error", `Failed to connect to data: ${err.message}`);
  }
}

async function onSaveCurrentClick() {
  clearAlerts();
  if (!state.dirHandle) {
    pushAlert("error", "Connect to data first.");
    return;
  }
  try {
    if (state.view === "fleet") {
      const validation = validateDesiredStateRows();
      if (validation.errors.length > 0) {
        renderFleetValidation(validation.errors);
        pushAlert("error", "Cannot save: fix validation errors first.");
        return;
      }
      await saveDesiredStateFile();
      setStatus("Saved desiredstate.csv");
    } else if (state.view === "metadata") {
      await saveSelectedDeviceMetadata();
      setStatus("Saved device metadata JSON.");
    } else {
      pushAlert("info", "Inventory Browser is read-only.");
    }
    renderAll();
  } catch (err) {
    pushAlert("error", `Save failed: ${err.message}`);
  }
}

async function onRevertCurrentClick() {
  clearAlerts();
  if (state.view === "fleet") {
    state.desiredState.rows = cloneRows(state.desiredState.originalRows);
    state.desiredState.dirty = false;
  } else if (state.view === "metadata") {
    const serial = state.selectedDeviceSerial;
    if (serial) {
      const dev = state.devices.get(serial);
      dev.doc.name = dev.originalDoc.name || "";
      dev.doc.description = dev.originalDoc.description || "";
      dev.dirty = false;
    }
  }
  renderAll();
  setStatus("Reverted current view changes.");
}

function onAddRowClick() {
  if (!state.desiredState.headers.length) {
    return;
  }
  const row = {};
  state.desiredState.headers.forEach((h) => {
    row[h] = "";
  });
  state.desiredState.rows.push(row);
  state.desiredState.selectedRowIndex = state.desiredState.rows.length - 1;
  state.desiredState.dirty = true;
  renderFleetView();
  renderTopbarActions();
}

function onDeleteRowClick() {
  const idx = state.desiredState.selectedRowIndex;
  if (idx < 0) {
    return;
  }
  state.desiredState.rows.splice(idx, 1);
  state.desiredState.selectedRowIndex = Math.min(
    idx,
    state.desiredState.rows.length - 1
  );
  state.desiredState.dirty = true;
  renderFleetView();
  renderTopbarActions();
}

function onDeviceMetadataInput() {
  const serial = state.selectedDeviceSerial;
  if (!serial) {
    return;
  }
  const dev = state.devices.get(serial);
  if (!dev) {
    return;
  }
  dev.doc.name = el.deviceName.value;
  dev.doc.description = el.deviceDescription.value;
  dev.dirty = true;
  renderTopbarActions();
}

function onDiffSelectionChange() {
  state.inventoryBrowser.diffBaseIndex = Number(el.diffBase.value);
  state.inventoryBrowser.diffTargetIndex = Number(el.diffTarget.value);
  renderInventoryDiff();
}

function switchView(nextView) {
  if (state.view === nextView) {
    return;
  }
  if (hasUnsavedChangesInView(state.view)) {
    const ok = window.confirm(
      "You have unsaved changes in this view. Switch anyway?"
    );
    if (!ok) {
      return;
    }
  }
  state.view = nextView;
  el.navButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.view === nextView);
  });
  Object.entries(el.views).forEach(([name, node]) => {
    node.classList.toggle("active", name === nextView);
  });
  renderTopbarActions();
}

async function attachProjectFolder(dirHandle) {
  const permission = await requestReadWritePermission(dirHandle);
  if (permission !== "granted") {
    throw new Error("Read/write permission was denied.");
  }
  state.dirHandle = dirHandle;
  state.handles = await resolveProjectHandles(dirHandle);
  await loadProjectData();
  renderAll();
}

async function resolveProjectHandles(root) {
  try {
    const desiredState = await root.getFileHandle("desiredstate.csv", {
      create: false,
    });
    const devicesDir = await root.getDirectoryHandle("devices", {
      create: false,
    });
    let eventsDir = null;
    try {
      eventsDir = await root.getDirectoryHandle("events", {
        create: false,
      });
    } catch {
      eventsDir = null;
    }
    return { desiredState, devicesDir, eventsDir };
  } catch {
    throw new Error(
      "Selected folder is not a SelTools data folder. Browse to /seltools/data."
    );
  }
}

async function loadProjectData() {
  await loadDesiredState();
  await loadDevices();
  await loadSerEvents();
  state.selectedDeviceSerial = [...state.devices.keys()][0] || "";
  state.inventoryBrowser.selectedSerial = state.selectedDeviceSerial;
  state.inventoryBrowser.selectedEventIndex = 0;
  state.inventoryBrowser.selectedSerEventIndex = 0;
}

async function loadDesiredState() {
  const text = await readFileText(state.handles.desiredState);
  const parsed = parseCsv(text);
  state.desiredState.headers = parsed.headers;
  state.desiredState.rows = parsed.rows;
  state.desiredState.originalRows = cloneRows(parsed.rows);
  state.desiredState.selectedRowIndex = parsed.rows.length ? 0 : -1;
  state.desiredState.dirty = false;
}

async function loadDevices() {
  state.devices.clear();
  for await (const [name, handle] of state.handles.devicesDir.entries()) {
    if (handle.kind !== "file" || !name.toLowerCase().endsWith(".json")) {
      continue;
    }
    try {
      const text = await readFileText(handle);
      const doc = JSON.parse(text);
      const serial = String(doc.serial || name.replace(/\.json$/i, ""));
      if (typeof doc.name !== "string") {
        doc.name = "";
      }
      if (typeof doc.description !== "string") {
        doc.description = "";
      }
      state.devices.set(serial, {
        serial,
        fileName: name,
        handle,
        doc,
        originalDoc: structuredCloneSafe(doc),
        dirty: false,
      });
    } catch (err) {
      pushAlert("error", `Failed to parse ${name}: ${err.message}`);
    }
  }
}

async function loadSerEvents() {
  state.serEvents.clear();
  if (!state.handles.eventsDir) {
    return;
  }

  for await (const [serialName, serialDir] of state.handles.eventsDir.entries()) {
    if (serialDir.kind !== "directory") {
      continue;
    }
    try {
      const serFile = await serialDir.getFileHandle("ser.jsonl", { create: false });
      const text = await readFileText(serFile);
      const records = text
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((line) => {
          try {
            return JSON.parse(line);
          } catch {
            return null;
          }
        })
        .filter(Boolean);
      state.serEvents.set(String(serialName), records);
    } catch {
      continue;
    }
  }
}

async function saveDesiredStateFile() {
  const csv = stringifyCsv(state.desiredState.headers, state.desiredState.rows);
  await writeFileText(state.handles.desiredState, csv);
  state.desiredState.originalRows = cloneRows(state.desiredState.rows);
  state.desiredState.dirty = false;
}

async function saveSelectedDeviceMetadata() {
  const serial = state.selectedDeviceSerial;
  if (!serial) {
    throw new Error("No device selected.");
  }
  const dev = state.devices.get(serial);
  if (!dev || !dev.dirty) {
    return;
  }
  const text = JSON.stringify(dev.doc, null, 2);
  await writeFileText(dev.handle, `${text}\n`);
  dev.originalDoc = structuredCloneSafe(dev.doc);
  dev.dirty = false;
}

function renderAll() {
  renderStatus();
  renderTopbarActions();
  renderFleetView();
  renderMetadataView();
  renderInventoryView();
}

function renderStatus() {
  if (!state.dirHandle) {
    el.statusPill.textContent = "Not connected to data yet";
    return;
  }
  el.statusPill.textContent = `Connected to data: ${state.dirHandle.name}`;
}

function renderTopbarActions() {
  const editableView = state.view === "fleet" || state.view === "metadata";
  el.saveCurrentBtn.disabled =
    !editableView || !state.dirHandle || !hasUnsavedChangesInView(state.view);
  el.revertCurrentBtn.disabled =
    !editableView || !state.dirHandle || !hasUnsavedChangesInView(state.view);
  el.addRowBtn.disabled = !state.dirHandle || state.view !== "fleet";
  el.deleteRowBtn.disabled =
    !state.dirHandle ||
    state.view !== "fleet" ||
    state.desiredState.selectedRowIndex < 0;
}

function renderFleetView() {
  renderFleetTable();
  renderFleetRowEditor();
  const validation = validateDesiredStateRows();
  renderFleetValidation(validation.errors);
}

function renderFleetTable() {
  const headers = state.desiredState.headers;
  const rows = state.desiredState.rows;
  if (!headers.length) {
    el.fleetTable.innerHTML = "<tr><td>No desiredstate.csv loaded.</td></tr>";
    return;
  }

  const thead = document.createElement("thead");
  const trHead = document.createElement("tr");
  headers.forEach((header) => {
    const th = document.createElement("th");
    th.textContent = header;
    trHead.appendChild(th);
  });
  thead.appendChild(trHead);

  const tbody = document.createElement("tbody");
  rows.forEach((row, rowIndex) => {
    const tr = document.createElement("tr");
    tr.classList.toggle("selected", rowIndex === state.desiredState.selectedRowIndex);
    tr.addEventListener("click", () => {
      state.desiredState.selectedRowIndex = rowIndex;
      renderFleetView();
      renderTopbarActions();
    });
    headers.forEach((header) => {
      const td = document.createElement("td");
      const input = document.createElement("input");
      input.value = String(row[header] ?? "");
      input.addEventListener("input", (evt) => {
        row[header] = evt.target.value;
        state.desiredState.dirty = true;
        renderFleetValidation(validateDesiredStateRows().errors);
        renderTopbarActions();
      });
      td.appendChild(input);
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  el.fleetTable.innerHTML = "";
  el.fleetTable.appendChild(thead);
  el.fleetTable.appendChild(tbody);
}

function renderFleetRowEditor() {
  const headers = state.desiredState.headers;
  const idx = state.desiredState.selectedRowIndex;
  const row = state.desiredState.rows[idx];
  if (!row || !headers.length) {
    el.fleetRowEditor.innerHTML = "<div>Select a row.</div>";
    return;
  }
  el.fleetRowEditor.innerHTML = "";
  headers.forEach((header) => {
    const label = document.createElement("label");
    label.textContent = header;
    const field =
      header.toLowerCase() === "description" || header.toLowerCase() === "notes"
        ? document.createElement("textarea")
        : document.createElement("input");
    field.value = String(row[header] ?? "");
    field.addEventListener("input", (evt) => {
      row[header] = evt.target.value;
      state.desiredState.dirty = true;
      renderFleetTable();
      renderFleetValidation(validateDesiredStateRows().errors);
      renderTopbarActions();
    });
    el.fleetRowEditor.appendChild(label);
    el.fleetRowEditor.appendChild(field);
  });
}

function renderFleetValidation(errors) {
  if (!errors.length) {
    el.fleetValidation.textContent = "Validation: OK";
    return;
  }
  el.fleetValidation.textContent = `Validation errors (${errors.length}): ${errors
    .slice(0, 4)
    .join(" | ")}${errors.length > 4 ? " ..." : ""}`;
}

function renderMetadataView() {
  const serials = [...state.devices.keys()].sort();
  el.deviceList.innerHTML = "";
  serials.forEach((serial) => {
    const li = document.createElement("li");
    const dev = state.devices.get(serial);
    li.textContent = `${serial}${dev.dirty ? " *" : ""}`;
    li.classList.toggle("active", serial === state.selectedDeviceSerial);
    li.addEventListener("click", () => {
      state.selectedDeviceSerial = serial;
      renderMetadataView();
      renderInventoryView();
      renderTopbarActions();
    });
    el.deviceList.appendChild(li);
  });

  const active = state.devices.get(state.selectedDeviceSerial);
  if (!active) {
    el.deviceName.value = "";
    el.deviceDescription.value = "";
    el.deviceEventsSummary.textContent = "No device selected.";
    el.deviceName.disabled = true;
    el.deviceDescription.disabled = true;
    return;
  }
  el.deviceName.disabled = false;
  el.deviceDescription.disabled = false;
  el.deviceName.value = String(active.doc.name || "");
  el.deviceDescription.value = String(active.doc.description || "");
  const eventCount = Array.isArray(active.doc.events) ? active.doc.events.length : 0;
  el.deviceEventsSummary.textContent = JSON.stringify(
    {
      file: active.fileName,
      serial: active.serial,
      events: eventCount,
      lastEvent:
        eventCount > 0 ? active.doc.events[eventCount - 1].timestamp || "n/a" : "n/a",
    },
    null,
    2
  );
}

function renderInventoryView() {
  const serials = [...state.devices.keys()].sort();
  if (!serials.includes(state.inventoryBrowser.selectedSerial)) {
    state.inventoryBrowser.selectedSerial = serials[0] || "";
  }
  el.inventoryDeviceList.innerHTML = "";
  serials.forEach((serial) => {
    const li = document.createElement("li");
    li.textContent = serial;
    li.classList.toggle("active", serial === state.inventoryBrowser.selectedSerial);
    li.addEventListener("click", () => {
      state.inventoryBrowser.selectedSerial = serial;
      state.inventoryBrowser.selectedEventIndex = 0;
      state.inventoryBrowser.selectedSerEventIndex = 0;
      renderInventoryView();
    });
    el.inventoryDeviceList.appendChild(li);
  });

  const dev = state.devices.get(state.inventoryBrowser.selectedSerial);
  const events = Array.isArray(dev?.doc?.events)
    ? dev.doc.events.filter((e) => e && e.action === "inventory")
    : [];

  if (state.inventoryBrowser.selectedEventIndex >= events.length) {
    state.inventoryBrowser.selectedEventIndex = events.length - 1;
  }
  if (state.inventoryBrowser.selectedEventIndex < 0 && events.length > 0) {
    state.inventoryBrowser.selectedEventIndex = 0;
  }

  el.inventoryEventList.innerHTML = "";
  events.forEach((event, idx) => {
    const li = document.createElement("li");
    li.textContent = `${event.timestamp || "unknown"} | ${event.status || "n/a"}`;
    li.classList.toggle("active", idx === state.inventoryBrowser.selectedEventIndex);
    li.addEventListener("click", () => {
      state.inventoryBrowser.selectedEventIndex = idx;
      renderInventoryEventDetail(events);
    });
    el.inventoryEventList.appendChild(li);
  });

  renderInventoryEventDetail(events);
  renderDiffSelectors(events);
  renderInventoryDiff();
  renderSerEventBrowser();
}

function renderInventoryEventDetail(events) {
  const idx = state.inventoryBrowser.selectedEventIndex;
  const event = events[idx];
  el.inventoryEventDetail.textContent = event
    ? JSON.stringify(event, null, 2)
    : "No inventory events found.";
}

function renderDiffSelectors(events) {
  el.diffBase.innerHTML = "";
  el.diffTarget.innerHTML = "";
  events.forEach((event, idx) => {
    const label = `${idx}: ${event.timestamp || "unknown"}`;
    const o1 = document.createElement("option");
    o1.value = String(idx);
    o1.textContent = label;
    const o2 = o1.cloneNode(true);
    el.diffBase.appendChild(o1);
    el.diffTarget.appendChild(o2);
  });

  if (!events.length) {
    state.inventoryBrowser.diffBaseIndex = -1;
    state.inventoryBrowser.diffTargetIndex = -1;
    return;
  }
  if (state.inventoryBrowser.diffBaseIndex < 0) {
    state.inventoryBrowser.diffBaseIndex = 0;
  }
  if (state.inventoryBrowser.diffTargetIndex < 0) {
    state.inventoryBrowser.diffTargetIndex = events.length - 1;
  }
  el.diffBase.value = String(state.inventoryBrowser.diffBaseIndex);
  el.diffTarget.value = String(state.inventoryBrowser.diffTargetIndex);
}

function renderInventoryDiff() {
  const dev = state.devices.get(state.inventoryBrowser.selectedSerial);
  const events = Array.isArray(dev?.doc?.events)
    ? dev.doc.events.filter((e) => e && e.action === "inventory")
    : [];
  const base = events[state.inventoryBrowser.diffBaseIndex];
  const target = events[state.inventoryBrowser.diffTargetIndex];
  const diffs = compareInventorySnapshots(base, target);
  el.inventoryDiffList.innerHTML = "";
  if (!diffs.length) {
    const li = document.createElement("li");
    li.textContent = "No differences for selected snapshots.";
    el.inventoryDiffList.appendChild(li);
    return;
  }
  diffs.forEach((d) => {
    const li = document.createElement("li");
    li.textContent = `${d.label}: ${d.before} -> ${d.after}`;
    el.inventoryDiffList.appendChild(li);
  });
}

function renderSerEventBrowser() {
  const serial = state.inventoryBrowser.selectedSerial;
  const serEvents = state.serEvents.get(serial) || [];

  if (state.inventoryBrowser.selectedSerEventIndex >= serEvents.length) {
    state.inventoryBrowser.selectedSerEventIndex = serEvents.length - 1;
  }
  if (state.inventoryBrowser.selectedSerEventIndex < 0 && serEvents.length > 0) {
    state.inventoryBrowser.selectedSerEventIndex = 0;
  }

  el.serEventList.innerHTML = "";
  serEvents.forEach((event, idx) => {
    const li = document.createElement("li");
    const ts = String(event.ts || "n/a");
    const msg = String(event.event || "event").slice(0, 80);
    li.textContent = `${ts} | ${msg}`;
    li.classList.toggle("active", idx === state.inventoryBrowser.selectedSerEventIndex);
    li.addEventListener("click", () => {
      state.inventoryBrowser.selectedSerEventIndex = idx;
      renderSerEventDetail(serEvents);
    });
    el.serEventList.appendChild(li);
  });

  renderSerEventDetail(serEvents);
}

function renderSerEventDetail(serEvents) {
  const idx = state.inventoryBrowser.selectedSerEventIndex;
  const event = serEvents[idx];
  el.serEventDetail.textContent = event
    ? JSON.stringify(event, null, 2)
    : "No SER events found for this device.";
}

function compareInventorySnapshots(base, target) {
  if (!base || !target) {
    return [];
  }
  const baseFid = String(
    getPath(base, "inventory.STA.FID") ??
      ""
  );
  const targetFid = String(
    getPath(target, "inventory.STA.FID") ??
      ""
  );
  const baseCid = String(
    getPath(base, "inventory.STA.CID") ??
      ""
  );
  const targetCid = String(
    getPath(target, "inventory.STA.CID") ??
      ""
  );

  const fields = [
    { label: "Host IP", path: "hostIp" },
    { label: "Observed IP", path: "inventory.ETH.IP" },
    { label: "Observed MAC", path: "inventory.ETH.MAC" },
    { label: "Observed Mask", path: "inventory.ETH.Mask" },
    { label: "Observed Gateway", path: "inventory.ETH.Gateway" },
    { label: "Serial", path: "identity.observedSerial" },
    { label: "Device Name", path: "identity.name" },
    { label: "Description", path: "identity.description" },
  ];
  const diffs = [];

  if (baseFid !== targetFid) {
    diffs.push({
      label: "FID",
      before: baseFid || "<blank>",
      after: targetFid || "<blank>",
    });
  }
  if (baseCid !== targetCid) {
    diffs.push({
      label: "CID",
      before: baseCid || "<blank>",
      after: targetCid || "<blank>",
    });
  }

  fields.forEach((f) => {
    const a = String(getPath(base, f.path) ?? "");
    const b = String(getPath(target, f.path) ?? "");
    if (a !== b) {
      diffs.push({
        label: f.label,
        before: a || "<blank>",
        after: b || "<blank>",
      });
    }
  });
  return diffs;
}

function getPath(obj, path) {
  return path.split(".").reduce((acc, key) => (acc ? acc[key] : undefined), obj);
}

function validateDesiredStateRows() {
  const headers = new Set(state.desiredState.headers.map((h) => h.trim()));
  const errors = [];
  state.desiredState.rows.forEach((row, idx) => {
    const serial = String(row.Serial ?? "").trim();
    const isTemplate = serial.toUpperCase() === "TEMPLATE";
    if (!serial && !isTemplate) {
      errors.push(`Row ${idx + 1}: Serial is required.`);
    }
    if (headers.has("Active")) {
      const active = String(row.Active ?? "").trim().toUpperCase();
      if (active && !["TRUE", "FALSE", "1", "0", "YES", "NO", "Y", "N"].includes(active)) {
        errors.push(`Row ${idx + 1}: Active must be TRUE/FALSE/1/0/YES/NO.`);
      }
    }

    ["DesiredIP", "DesiredGateway", "ObservedIP"].forEach((col) => {
      if (headers.has(col)) {
        const v = String(row[col] ?? "").trim();
        if (v && !isValidIpv4(v)) {
          errors.push(`Row ${idx + 1}: ${col} is not valid IPv4.`);
        }
      }
    });
    if (headers.has("DesiredSubnetMask")) {
      const v = String(row.DesiredSubnetMask ?? "").trim();
      if (v && !isValidIpv4(v)) {
        errors.push(`Row ${idx + 1}: DesiredSubnetMask is not valid IPv4.`);
      }
    }
  });
  return { errors };
}

function isValidIpv4(value) {
  const parts = value.split(".");
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((p) => /^\d+$/.test(p) && Number(p) >= 0 && Number(p) <= 255);
}

function hasUnsavedChangesInView(view) {
  if (view === "fleet") {
    return state.desiredState.dirty;
  }
  if (view === "metadata") {
    return [...state.devices.values()].some((d) => d.dirty);
  }
  return false;
}

function hasUnsavedChanges() {
  return hasUnsavedChangesInView("fleet") || hasUnsavedChangesInView("metadata");
}

function cloneRows(rows) {
  return rows.map((row) => ({ ...row }));
}

function structuredCloneSafe(value) {
  return JSON.parse(JSON.stringify(value));
}

function clearAlerts() {
  el.alertArea.innerHTML = "";
}

function pushAlert(type, text) {
  const div = document.createElement("div");
  div.className = `alert ${type}`;
  div.textContent = text;
  el.alertArea.appendChild(div);
}

function setStatus(text) {
  el.statusMessage.textContent = text;
}

async function readFileText(fileHandle) {
  const file = await fileHandle.getFile();
  return await file.text();
}

async function writeFileText(fileHandle, text) {
  const writable = await fileHandle.createWritable();
  await writable.write(text);
  await writable.close();
}

async function requestReadWritePermission(handle) {
  const opts = { mode: "readwrite" };
  let permission = await handle.queryPermission(opts);
  if (permission === "granted") {
    return permission;
  }
  permission = await handle.requestPermission(opts);
  return permission;
}

async function openHandleStore() {
  return await new Promise((resolve, reject) => {
    const req = indexedDB.open("seltools-fleet-browser", 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("handles")) {
        db.createObjectStore("handles");
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function saveFolderHandle(handle) {
  const db = await openHandleStore();
  await new Promise((resolve, reject) => {
    const tx = db.transaction("handles", "readwrite");
    tx.objectStore("handles").put(handle, "projectDir");
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

async function getSavedFolderHandle() {
  const db = await openHandleStore();
  const handle = await new Promise((resolve, reject) => {
    const tx = db.transaction("handles", "readonly");
    const req = tx.objectStore("handles").get("projectDir");
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
  db.close();
  return handle;
}

async function restoreSavedFolderHandle() {
  if (!window.showDirectoryPicker) {
    return;
  }
  try {
    const dirHandle = await getSavedFolderHandle();
    if (!dirHandle) {
      return;
    }
    const permission = await dirHandle.queryPermission({ mode: "readwrite" });
    if (permission === "granted") {
      await attachProjectFolder(dirHandle);
      setStatus("Restored saved data folder.");
    } else {
      setStatus("Saved data folder found. Click Connect to data to grant access.");
    }
  } catch (err) {
    pushAlert("info", `Could not restore saved folder: ${err.message}`);
  }
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let i = 0;
  let inQuotes = false;
  while (i < text.length) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      cell += ch;
      i += 1;
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (ch === ",") {
      row.push(cell);
      cell = "";
      i += 1;
      continue;
    }
    if (ch === "\n") {
      row.push(cell.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      cell = "";
      i += 1;
      continue;
    }
    cell += ch;
    i += 1;
  }
  if (cell.length || row.length) {
    row.push(cell.replace(/\r$/, ""));
    rows.push(row);
  }

  if (!rows.length) {
    return { headers: [], rows: [] };
  }
  const headers = rows[0];
  const dataRows = rows.slice(1).map((raw) => {
    const out = {};
    headers.forEach((header, idx) => {
      out[header] = raw[idx] ?? "";
    });
    return out;
  });
  return { headers, rows: dataRows };
}

function stringifyCsv(headers, dataRows) {
  const out = [];
  out.push(headers.map(csvEscape).join(","));
  dataRows.forEach((row) => {
    const cols = headers.map((h) => csvEscape(String(row[h] ?? "")));
    out.push(cols.join(","));
  });
  return `${out.join("\n")}\n`;
}

function csvEscape(value) {
  const escaped = value.replace(/"/g, '""');
  return `"${escaped}"`;
}
