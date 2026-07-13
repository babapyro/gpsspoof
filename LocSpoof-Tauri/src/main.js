const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// App State
let state = {
  isPremium: false,
  isTrial: false,
  licenseKey: "",
  currentPlatform: "ios", // "ios" or "android"
  devices: [],
  selectedDevice: null,
  activeFeature: "teleport", // "teleport", "route", "joystick", "gpx"
  antiDetection: true,
  
  // Simulation / Map state
  map: null,
  marker: null,
  currentCoords: [37.774900, -122.419400], // Default: San Francisco
  waypoints: [],
  routeLine: null,
  
  // Route Simulation Run State
  isSimulating: false,
  simSpeedKmh: 12,
  simIntervalId: null,
  simCurrentIndex: 0,
  simFraction: 0,
  
  // Joystick Run State
  joystickActive: false,
  joystickKeys: { w: false, a: false, s: false, d: false, ArrowUp: false, ArrowLeft: false, ArrowDown: false, ArrowRight: false },
  joystickLoopId: null
};

// DOM Elements
let el = {};

window.addEventListener("DOMContentLoaded", async () => {
  // Bind DOM Elements
  el.dependencyOverlay = document.getElementById("dependency-overlay");
  el.depSubtitle = document.getElementById("dep-subtitle");
  el.depProgressBar = document.getElementById("dep-progress-bar");
  el.depProgressLabel = document.getElementById("dep-progress-label");
  el.depConsoleLog = document.getElementById("dep-console-log");
  el.depErrorActions = document.getElementById("dep-error-actions");
  el.btnDepRetry = document.getElementById("btn-dep-retry");

  el.licenseModal = document.getElementById("license-modal");
  el.licenseKeyInput = document.getElementById("license-key-input");
  el.licenseErrorMsg = document.getElementById("license-error-msg");
  el.modalLicenseStatus = document.getElementById("modal-license-status");
  el.deactivateSection = document.getElementById("deactivate-section");
  
  el.btnLicenseSettings = document.getElementById("btn-license-settings");
  el.btnCloseLicense = document.getElementById("btn-close-license");
  el.btnStartTrial = document.getElementById("btn-start-trial");
  el.btnSubmitLicense = document.getElementById("btn-submit-license");
  el.btnDeactivate = document.getElementById("btn-deactivate");

  el.premiumGateModal = document.getElementById("premium-gate-modal");
  el.btnCloseUpgrade = document.getElementById("btn-close-upgrade");
  el.btnUpgradeLicense = document.getElementById("btn-upgrade-license");

  el.appTierBadge = document.getElementById("app-tier-badge");
  el.segmentIos = document.getElementById("segment-ios");
  el.segmentAndroid = document.getElementById("segment-android");
  el.deviceSelect = document.getElementById("device-select");
  el.btnScan = document.getElementById("btn-scan");
  el.scanLoader = document.getElementById("scan-loader");
  el.deviceStatusIndicator = document.getElementById("device-status-indicator");
  el.deviceStatusText = document.getElementById("device-status-text");
  el.chkAntiDetection = document.getElementById("chk-anti-detection");

  el.teleportLat = document.getElementById("teleport-lat");
  el.teleportLng = document.getElementById("teleport-lng");
  el.btnTeleportExecute = document.getElementById("btn-teleport-execute");
  
  el.waypointCount = document.getElementById("waypoint-count");
  el.speedSlider = document.getElementById("speed-slider");
  el.speedLabel = document.getElementById("speed-label");
  el.btnRouteClear = document.getElementById("btn-route-clear");
  el.btnRouteStart = document.getElementById("btn-route-start");

  el.joystickHandleEl = document.getElementById("joystick-handle-el");

  el.btnGpxUpload = document.getElementById("btn-gpx-upload");
  el.btnResetLocation = document.getElementById("btn-reset-location");

  el.btnToggleLogPanel = document.getElementById("btn-toggle-log-panel");
  el.logPanelIndicator = document.getElementById("log-panel-indicator");
  el.consoleLogPanel = document.getElementById("console-log-panel");
  el.appConsoleLog = document.getElementById("app-console-log");
  el.btnClearConsoleLogs = document.getElementById("btn-clear-console-logs");

  el.mapSearchInput = document.getElementById("map-search-input");
  el.btnMapSearch = document.getElementById("btn-map-search");

  // Setup Event Listeners
  setupEventListeners();

  // Initialize Map
  initMap();

  // Check Dependencies
  await checkAppDependencies();

  // Get License Status
  await updateLicenseState();
});

// EVENT LISTENERS BINDING
function setupEventListeners() {
  // OS Toggles
  el.segmentIos.addEventListener("click", () => switchPlatform("ios"));
  el.segmentAndroid.addEventListener("click", () => switchPlatform("android"));

  // Device Selection & Scanning
  el.deviceSelect.addEventListener("change", (e) => selectDevice(e.target.value));
  el.btnScan.addEventListener("click", scanDevices);

  // License Modal actions
  el.btnLicenseSettings.addEventListener("click", () => showModal(el.licenseModal));
  el.btnCloseLicense.addEventListener("click", () => hideModal(el.licenseModal));
  el.btnStartTrial.addEventListener("click", startTrialMode);
  el.btnSubmitLicense.addEventListener("click", submitLicenseKey);
  el.btnDeactivate.addEventListener("click", deactivateLicense);

  // Premium modal actions
  el.btnCloseUpgrade.addEventListener("click", () => hideModal(el.premiumGateModal));
  el.btnUpgradeLicense.addEventListener("click", () => {
    hideModal(el.premiumGateModal);
    showModal(el.licenseModal);
  });

  // Feature Headers (Accordion) toggling
  document.querySelectorAll(".feature-box-header").forEach(header => {
    header.addEventListener("click", () => {
      const box = header.parentElement;
      const featId = box.id.replace("feat-", "");
      
      // If it is locked and user is not premium, open premium upgrade gate
      if (box.classList.contains("locked") && !state.isPremium) {
        showModal(el.premiumGateModal);
        return;
      }

      // Deactivate all boxes and activate current
      document.querySelectorAll(".feature-box").forEach(b => b.classList.remove("active"));
      box.classList.add("active");
      state.activeFeature = featId;
      
      // Feature specific initializations
      if (featId === "joystick") {
        startJoystickLoop();
      } else {
        stopJoystickLoop();
      }
    });
  });

  // Teleport Execute
  el.btnTeleportExecute.addEventListener("click", teleportExecute);

  // Route Simulation controls
  el.speedSlider.addEventListener("input", (e) => {
    state.simSpeedKmh = parseInt(e.target.value);
    el.speedLabel.textContent = `${state.simSpeedKmh} km/h`;
  });
  el.btnRouteClear.addEventListener("click", clearRoute);
  el.btnRouteStart.addEventListener("click", toggleRouteSimulation);

  // GPX Upload Trigger
  el.btnGpxUpload.addEventListener("click", triggerGPXUpload);

  // Reset Location
  el.btnResetLocation.addEventListener("click", resetDeviceLocation);

  // Anti detection toggle
  el.chkAntiDetection.addEventListener("change", (e) => {
    state.antiDetection = e.target.checked;
    logMessage(`Anti-Detection Jitter: ${state.antiDetection ? "ENABLED" : "DISABLED"}`, "info");
  });

  // Console toggle
  el.btnToggleLogPanel.addEventListener("click", () => {
    el.consoleLogPanel.classList.toggle("hidden");
    el.logPanelIndicator.textContent = el.consoleLogPanel.classList.contains("hidden") ? "▲" : "▼";
  });
  el.btnClearConsoleLogs.addEventListener("click", () => {
    el.appConsoleLog.innerHTML = "";
  });

  // Dependency Onboarding actions
  el.btnDepRetry.addEventListener("click", installDependencies);

  // Search Address/Coordinates
  el.btnMapSearch.addEventListener("click", performMapSearch);
  el.mapSearchInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") performMapSearch();
  });
}

// DIAGNOSTIC LOGGING
function logMessage(text, type = "muted") {
  const line = document.createElement("div");
  line.className = `log-line text-${type}`;
  line.textContent = `[${new Date().toLocaleTimeString()}] ${text}`;
  
  el.appConsoleLog.appendChild(line);
  el.appConsoleLog.scrollTop = el.appConsoleLog.scrollHeight;

  // Mirror to Onboarding console if active
  if (!el.dependencyOverlay.classList.contains("hidden")) {
    const depLine = line.cloneNode(true);
    el.depConsoleLog.appendChild(depLine);
    el.depConsoleLog.scrollTop = el.depConsoleLog.scrollHeight;
  }
}

// TOAST NOTIFICATIONS
function showToast(title, body, type = "info") {
  const container = document.getElementById("toast-container");
  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  
  toast.innerHTML = `
    <div class="toast-header">
      <span>${title}</span>
      <span class="toast-close">&times;</span>
    </div>
    <div class="toast-body">${body}</div>
  `;
  
  toast.querySelector(".toast-close").addEventListener("click", () => {
    toast.style.animation = "fadeIn 0.2s reverse forwards";
    setTimeout(() => toast.remove(), 200);
  });
  
  container.appendChild(toast);
  
  // Auto remove after 5 seconds
  setTimeout(() => {
    if (toast.parentElement) {
      toast.style.animation = "fadeIn 0.2s reverse forwards";
      setTimeout(() => toast.remove(), 200);
    }
  }, 5000);
}

// MODAL CONTROLS
function showModal(modalEl) {
  modalEl.classList.remove("hidden");
}

function hideModal(modalEl) {
  modalEl.classList.add("hidden");
}

// DEPENDENCY ONBOARDING LOGIC
async function checkAppDependencies() {
  logMessage("Verifying backend environments...", "info");
  try {
    const status = await invoke("check_dependencies");
    
    if (status.python_installed && status.pymobiledevice3_installed && status.adb_installed) {
      logMessage("Dependencies verified: Python, pymobiledevice3, ADB active.", "success");
      el.dependencyOverlay.classList.add("hidden");
      scanDevices();
    } else {
      logMessage("Missing critical environment toolchains. Prompting setup...", "warn");
      el.dependencyOverlay.classList.remove("hidden");
      
      // Auto run dependency install on start if missing
      installDependencies();
    }
  } catch (err) {
    logMessage(`Dependency verification crash: ${err}`, "error");
    showToast("Dependency Error", "Failed to communicate with Tauri core.", "error");
  }
}

async function installDependencies() {
  el.depErrorActions.classList.add("hidden");
  el.depSubtitle.textContent = "Installing backend dependency engines...";
  
  logMessage("Launching Zero-Touch setup processes asynchronously...", "info");
  
  // Listen for progress updates
  const unlistenProgress = await listen("dependency-progress", (event) => {
    const payload = event.payload;
    const progressPercent = Math.round(payload.progress * 100);
    
    el.depProgressBar.style.width = `${progressPercent}%`;
    el.depProgressLabel.textContent = `${payload.message} (${progressPercent}%)`;
    logMessage(payload.message, "info");
  });

  // Listen for completion
  const unlistenComplete = await listen("dependency-complete", (event) => {
    const payload = event.payload;
    
    unlistenProgress();
    unlistenComplete();
    
    if (payload.success) {
      logMessage("Setup complete! Initializing GPS control panels...", "success");
      el.depProgressBar.style.width = "100%";
      el.depProgressLabel.textContent = "All set! Starting LocSpoof...";
      
      setTimeout(() => {
        el.dependencyOverlay.classList.add("hidden");
        scanDevices();
      }, 1500);
    } else {
      logMessage(`Setup Failed: ${payload.error}`, "error");
      el.depSubtitle.textContent = "Setup encountered a problem.";
      el.depProgressLabel.textContent = "Error: Check installation logs below.";
      el.depErrorActions.classList.remove("hidden");
      showToast("Setup Failed", payload.error || "Failed to setup packages.", "error");
    }
  });

  try {
    await invoke("install_dependencies");
  } catch (err) {
    logMessage(`Failed to invoke installer: ${err}`, "error");
    el.depErrorActions.classList.remove("hidden");
  }
}

// LICENSE MANAGEMENT LOGIC
async function updateLicenseState() {
  try {
    const status = await invoke("get_license_status");
    state.isPremium = status.is_premium;
    state.isTrial = status.is_trial;
    state.licenseKey = status.license_key;

    // Update Tier badges
    if (state.isPremium) {
      if (state.isTrial) {
        el.appTierBadge.textContent = "TRIAL";
        el.appTierBadge.className = "badge free-badge";
        el.modalLicenseStatus.innerHTML = `Status: <span class="status-badge unlicensed">Trial Mode Active</span>`;
      } else {
        el.appTierBadge.textContent = "PRO";
        el.appTierBadge.className = "badge premium-badge";
        el.modalLicenseStatus.innerHTML = `Status: <span class="status-badge pro">Pro Activated</span>`;
      }
    } else {
      el.appTierBadge.textContent = "UNLICENSED";
      el.appTierBadge.className = "badge free-badge";
      el.modalLicenseStatus.innerHTML = `Status: <span class="status-badge unlicensed">Unlicensed</span>`;
    }

    // Toggle Locks on Accordion boxes
    const premiumBoxes = ["feat-route", "feat-joystick", "feat-gpx"];
    premiumBoxes.forEach(id => {
      const box = document.getElementById(id);
      const pill = box.querySelector(".status-pill");
      
      if (state.isPremium) {
        box.classList.remove("locked");
        if (pill) {
          pill.className = "status-pill free";
          pill.textContent = "UNLOCKED";
        }
      } else {
        box.classList.add("locked");
        if (pill) {
          pill.className = "status-pill lock-pill";
          pill.textContent = "🔒 PRO";
        }
        
        // If currently open and now locked, close it and go back to teleport
        if (box.classList.contains("active")) {
          box.classList.remove("active");
          document.getElementById("feat-teleport").classList.add("active");
          state.activeFeature = "teleport";
        }
      }
    });

    // License Modal Form Settings
    if (state.isPremium && !state.isTrial) {
      el.licenseKeyInput.value = state.licenseKey;
      el.licenseKeyInput.disabled = true;
      el.btnStartTrial.classList.add("hidden");
      el.btnSubmitLicense.classList.add("hidden");
      el.deactivateSection.classList.remove("hidden");
    } else {
      el.licenseKeyInput.value = "";
      el.licenseKeyInput.disabled = false;
      el.btnStartTrial.classList.toggle("hidden", state.isTrial);
      el.btnSubmitLicense.classList.remove("hidden");
      el.deactivateSection.classList.add("hidden");
    }
  } catch (err) {
    logMessage(`Error loading license data: ${err}`, "error");
  }
}

async function startTrialMode() {
  try {
    const status = await invoke("start_license_trial");
    showToast("Trial Started", "You have unlocked a 7-day free trial containing premium engines.", "success");
    logMessage("Activated Free Trial mode.", "success");
    hideModal(el.licenseModal);
    await updateLicenseState();
  } catch (err) {
    showToast("Trial Error", err.toString(), "error");
  }
}

async function submitLicenseKey() {
  const key = el.licenseKeyInput.value.trim();
  if (!key) {
    el.licenseErrorMsg.textContent = "Please enter a license key.";
    el.licenseErrorMsg.classList.remove("hidden");
    return;
  }

  el.licenseErrorMsg.classList.add("hidden");
  logMessage(`Activating key: ${key}...`, "info");
  
  try {
    const status = await invoke("activate_license", { key });
    showToast("Licensing Success", "LocSpoof Pro license key activated successfully!", "success");
    logMessage("Successfully activated Pro licensing state securely.", "success");
    hideModal(el.licenseModal);
    await updateLicenseState();
  } catch (err) {
    el.licenseErrorMsg.textContent = err.toString();
    el.licenseErrorMsg.classList.remove("hidden");
    logMessage(`Activation failed: ${err}`, "error");
  }
}

async function deactivateLicense() {
  try {
    await invoke("deactivate_license");
    showToast("Deactivated", "Your license has been deactivated on this machine.", "info");
    logMessage("License deactivated.", "info");
    hideModal(el.licenseModal);
    await updateLicenseState();
  } catch (err) {
    showToast("Deactivation Error", err.toString(), "error");
  }
}

// DEVICE MANAGEMENT LOGIC
function switchPlatform(platform) {
  if (state.currentPlatform === platform) return;
  
  state.currentPlatform = platform;
  if (platform === "ios") {
    el.segmentIos.classList.add("active");
    el.segmentAndroid.classList.remove("active");
  } else {
    el.segmentIos.classList.remove("active");
    el.segmentAndroid.classList.add("active");
  }

  logMessage(`Switched platform focus: ${platform.toUpperCase()}`, "info");
  scanDevices();
}

async function scanDevices() {
  el.scanLoader.classList.remove("hidden");
  el.btnScan.disabled = true;
  el.deviceSelect.innerHTML = '<option value="">Scanning devices...</option>';
  logMessage("Querying USB/Wi-Fi connection bridges...", "info");

  try {
    const devs = await invoke("scan_devices");
    
    // Filter devices based on current platform toggle
    state.devices = devs.filter(d => d.platform === state.currentPlatform);
    
    el.deviceSelect.innerHTML = "";
    
    if (state.devices.length === 0) {
      el.deviceSelect.innerHTML = '<option value="">No device found.</option>';
      state.selectedDevice = null;
      updateDeviceStatusUI(false);
      logMessage(`No ${state.currentPlatform.toUpperCase()} devices found.`, "warn");
    } else {
      state.devices.forEach(d => {
        const opt = document.createElement("option");
        opt.value = d.id;
        opt.textContent = `${d.name} (${d.model}) [${d.connection_type.toUpperCase()}]`;
        el.deviceSelect.appendChild(opt);
      });
      
      // Auto select first device
      selectDevice(state.devices[0].id);
      updateDeviceStatusUI(true);
    }
  } catch (err) {
    el.deviceSelect.innerHTML = '<option value="">Scan failed.</option>';
    updateDeviceStatusUI(false);
    logMessage(`Scan failed: ${err}`, "error");
    showToast("Scan Error", err.toString(), "error");
  } finally {
    el.scanLoader.classList.add("hidden");
    el.btnScan.disabled = false;
  }
}

function selectDevice(id) {
  state.selectedDevice = state.devices.find(d => d.id === id) || null;
  if (state.selectedDevice) {
    logMessage(`Selected Device: ${state.selectedDevice.name} [ID: ${state.selectedDevice.id}]`, "success");
    updateDeviceStatusUI(true);
  } else {
    updateDeviceStatusUI(false);
  }
}

function updateDeviceStatusUI(connected) {
  const dot = el.deviceStatusIndicator.querySelector(".status-dot");
  if (connected && state.selectedDevice) {
    dot.className = "status-dot dot-green";
    el.deviceStatusText.textContent = `Connected: ${state.selectedDevice.model}`;
  } else {
    dot.className = "status-dot dot-red";
    el.deviceStatusText.textContent = "Disconnected";
  }
}

// MAP INTEGRATION (LEAFLET)
function initMap() {
  state.map = L.map("map", {
    zoomControl: true,
    attributionControl: false
  }).setView(state.currentCoords, 13);

  // Add OpenStreetMap tiles
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19
  }).addTo(state.map);

  // Add a marker
  state.marker = L.marker(state.currentCoords, {
    draggable: true
  }).addTo(state.map);

  // Update coordinates coordinates display when marker is dragged
  state.marker.on("dragend", (event) => {
    const position = event.target.getLatLng();
    setMapCoordinates(position.lat, position.lng);
  });

  // Double click or single click to set coordinates depending on mode
  state.map.on("click", (e) => {
    const lat = e.latlng.lat;
    const lng = e.latlng.lng;
    
    if (state.activeFeature === "route") {
      // Add waypoint to path simulation
      addRouteWaypoint(lat, lng);
    } else {
      // Move marker and update teleport panels
      state.marker.setLatLng(e.latlng);
      setMapCoordinates(lat, lng);
    }
  });

  // Trigger resize to prevent layout glitching
  setTimeout(() => state.map.invalidateSize(), 300);
}

function setMapCoordinates(lat, lng) {
  state.currentCoords = [lat, lng];
  el.teleportLat.textContent = lat.toFixed(6);
  el.teleportLng.textContent = lng.toFixed(6);
}

async function performMapSearch() {
  const query = el.mapSearchInput.value.trim();
  if (!query) return;

  logMessage(`Searching: "${query}"...`, "info");
  
  // Check if query is latitude/longitude coordinates directly
  const coordRegex = /^[-+]?([1-8]?\d(\.\d+)?|90(\.0+)?),\s*[-+]?(180(\.0+)?|((1[0-7]\d)|([1-9]?\d))(\.\d+)?)$/;
  if (coordRegex.test(query)) {
    const parts = query.split(",").map(p => parseFloat(p.trim()));
    state.map.setView(parts, 14);
    state.marker.setLatLng(parts);
    setMapCoordinates(parts[0], parts[1]);
    logMessage(`Geocoded coordinate: ${parts[0]}, ${parts[1]}`, "success");
    return;
  }

  try {
    // Call Nominatim open geocoding API
    const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=1`;
    const response = await fetch(url);
    const data = await response.json();
    
    if (data.length > 0) {
      const result = data[0];
      const lat = parseFloat(result.lat);
      const lon = parseFloat(result.lon);
      
      state.map.setView([lat, lon], 14);
      state.marker.setLatLng([lat, lon]);
      setMapCoordinates(lat, lon);
      
      logMessage(`Location found: ${result.display_name}`, "success");
    } else {
      logMessage("Search returned zero matches.", "warn");
      showToast("Search Failed", "Address not found.", "warn");
    }
  } catch (err) {
    logMessage(`Geocoding error: ${err}`, "error");
  }
}

// GPS SPOOFING ENGINE ACTIONS
async function teleportExecute() {
  if (!state.selectedDevice) {
    showToast("Teleport Failed", "Please scan and connect a target device.", "error");
    return;
  }

  const [lat, lon] = state.currentCoords;
  logMessage(`Spoofing coordinate: ${lat.toFixed(6)}, ${lon.toFixed(6)}...`, "info");
  
  try {
    await invoke("teleport_device", {
      device: state.selectedDevice,
      lat,
      lon,
      antiDetection: state.antiDetection
    });
    
    showToast("Location Spoofed", `Teleported device coordinates successfully.`, "success");
    logMessage("Location injection completed successfully.", "success");
  } catch (err) {
    logMessage(`Teleport error: ${err}`, "error");
    showToast("Spoofing Error", err.toString(), "error");
  }
}

async function resetDeviceLocation() {
  if (!state.selectedDevice) {
    showToast("Reset Failed", "Please connect a device first.", "error");
    return;
  }

  logMessage("Sending location reset command to device...", "info");
  
  try {
    await invoke("reset_device_location", { device: state.selectedDevice });
    showToast("Real GPS Restored", "Cleared simulated location on device.", "success");
    logMessage("Successfully restored real coordinates.", "success");
  } catch (err) {
    logMessage(`Reset location error: ${err}`, "error");
    showToast("Reset Error", err.toString(), "error");
  }
}

// ROUTE SIMULATION ENGINE
function addRouteWaypoint(lat, lng) {
  state.waypoints.push([lat, lng]);
  el.waypointCount.textContent = state.waypoints.length;
  
  // Draw/update path polyline
  if (state.routeLine) {
    state.routeLine.setLatLngs(state.waypoints);
  } else {
    state.routeLine = L.polyline(state.waypoints, {
      color: "#0078d4",
      weight: 4,
      dashArray: "6, 8"
    }).addTo(state.map);
  }
  
  logMessage(`Waypoint added: ${lat.toFixed(6)}, ${lng.toFixed(6)}`, "info");
}

function clearRoute() {
  state.waypoints = [];
  el.waypointCount.textContent = "0";
  if (state.routeLine) {
    state.routeLine.remove();
    state.routeLine = null;
  }
  
  if (state.isSimulating) {
    stopRouteSimulation();
  }
  
  logMessage("Route path cleared.", "info");
}

function toggleRouteSimulation() {
  if (state.isSimulating) {
    stopRouteSimulation();
  } else {
    startRouteSimulation();
  }
}

function startRouteSimulation() {
  if (!state.selectedDevice) {
    showToast("Simulation Failed", "Connect a device first.", "error");
    return;
  }

  if (state.waypoints.length < 2) {
    showToast("Path Missing", "Draw at least 2 points on the map to simulate a route.", "warn");
    return;
  }

  state.isSimulating = true;
  el.btnRouteStart.textContent = "Stop Route";
  el.btnRouteStart.className = "fluent-button btn-danger flex-1";
  
  state.simCurrentIndex = 0;
  state.simFraction = 0;
  
  logMessage(`Starting simulation path at speed: ${state.simSpeedKmh} km/h...`, "success");
  
  // Every 500ms, compute intermediate coordinate and teleport
  const intervalMs = 500;
  state.simIntervalId = setInterval(() => {
    runSimulationStep(intervalMs);
  }, intervalMs);
}

function stopRouteSimulation() {
  state.isSimulating = false;
  el.btnRouteStart.textContent = "Start Route";
  el.btnRouteStart.className = "fluent-button btn-primary flex-1";
  
  if (state.simIntervalId) {
    clearInterval(state.simIntervalId);
    state.simIntervalId = null;
  }
  logMessage("Route simulation stopped.", "info");
}

function runSimulationStep(intervalMs) {
  if (state.simCurrentIndex >= state.waypoints.length - 1) {
    logMessage("Route simulation finished.", "success");
    stopRouteSimulation();
    return;
  }

  const p1 = state.waypoints[state.simCurrentIndex];
  const p2 = state.waypoints[state.simCurrentIndex + 1];

  // Calculate distance between waypoints in meters (Haversine formula approximation)
  const R = 6371000; // Earth's radius in meters
  const dLat = (p2[0] - p1[0]) * Math.PI / 180;
  const dLon = (p2[1] - p1[1]) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(p1[0] * Math.PI / 180) * Math.cos(p2[0] * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distanceMeters = R * c;

  // Calculate step speed
  const speedMps = state.simSpeedKmh / 3.6;
  const stepDistance = speedMps * (intervalMs / 1000);
  
  state.simFraction += stepDistance / distanceMeters;
  
  if (state.simFraction >= 1.0) {
    state.simFraction = 0;
    state.simCurrentIndex++;
    runSimulationStep(intervalMs); // jump to next segment
    return;
  }

  // Linear interpolation of coordinates
  const lat = p1[0] + (p2[0] - p1[0]) * state.simFraction;
  const lon = p1[1] + (p2[1] - p1[1]) * state.simFraction;

  state.marker.setLatLng([lat, lon]);
  setMapCoordinates(lat, lon);

  // Send teleport to device
  invoke("teleport_device", {
    device: state.selectedDevice,
    lat,
    lon,
    antiDetection: state.antiDetection
  }).catch(err => {
    logMessage(`Simulation inject error: ${err}`, "error");
    stopRouteSimulation();
  });
}

// REAL-TIME JOYSTICK CONTROL
function startJoystickLoop() {
  if (state.joystickLoopId) return;

  state.joystickActive = true;
  logMessage("Real-Time Joystick active: Use W/A/S/D keys to move marker.", "info");

  // Key Listeners
  window.addEventListener("keydown", handleJoystickKeyDown);
  window.addEventListener("keyup", handleJoystickKeyUp);

  const loopMs = 200;
  state.joystickLoopId = setInterval(() => {
    processJoystickMovement(loopMs);
  }, loopMs);
}

function stopJoystickLoop() {
  state.joystickActive = false;
  if (state.joystickLoopId) {
    clearInterval(state.joystickLoopId);
    state.joystickLoopId = null;
  }

  window.removeEventListener("keydown", handleJoystickKeyDown);
  window.removeEventListener("keyup", handleJoystickKeyUp);
}

function handleJoystickKeyDown(e) {
  const key = e.key.toLowerCase();
  if (key in state.joystickKeys || e.key in state.joystickKeys) {
    state.joystickKeys[key] = true;
    state.joystickKeys[e.key] = true; // handle Arrow keys
    e.preventDefault();
  }
}

function handleJoystickKeyUp(e) {
  const key = e.key.toLowerCase();
  if (key in state.joystickKeys || e.key in state.joystickKeys) {
    state.joystickKeys[key] = false;
    state.joystickKeys[e.key] = false;
  }
}

function processJoystickMovement(loopMs) {
  if (!state.selectedDevice) return;

  let dx = 0;
  let dy = 0;

  if (state.joystickKeys.w || state.joystickKeys.arrowup) dy += 1;
  if (state.joystickKeys.s || state.joystickKeys.arrowdown) dy -= 1;
  if (state.joystickKeys.d || state.joystickKeys.arrowright) dx += 1;
  if (state.joystickKeys.a || state.joystickKeys.arrowleft) dx -= 1;

  if (dx === 0 && dy === 0) {
    // Reset handle animation offsets
    el.joystickHandleEl.style.transform = "translate(0px, 0px)";
    return;
  }

  // Animate handle handle direction offsets
  el.joystickHandleEl.style.transform = `translate(${dx * 12}px, ${-dy * 12}px)`;

  // Convert movement direction coordinates (lat/lon offsets)
  // 1 degree latitude = ~111,000 meters
  // 1 degree longitude = ~111,000 * cos(latitude)
  const latMetersPerDegree = 111111;
  const lonMetersPerDegree = 111111 * Math.cos(state.currentCoords[0] * Math.PI / 180);

  const speedMps = state.simSpeedKmh / 3.6;
  const distanceMoved = speedMps * (loopMs / 1000);

  // Normalize vector
  const len = Math.sqrt(dx*dx + dy*dy);
  const ndx = dx / len;
  const ndy = dy / len;

  const latOffset = (ndy * distanceMoved) / latMetersPerDegree;
  const lonOffset = (ndx * distanceMoved) / lonMetersPerDegree;

  const newLat = state.currentCoords[0] + latOffset;
  const newLon = state.currentCoords[1] + lonOffset;

  state.marker.setLatLng([newLat, newLon]);
  setMapCoordinates(newLat, newLon);

  // Teleport in loop
  invoke("teleport_device", {
    device: state.selectedDevice,
    lat: newLat,
    lon: newLon,
    antiDetection: state.antiDetection
  }).catch(err => {
    logMessage(`Joystick write error: ${err}`, "error");
  });
}

// GPX FILES PARSER IMPORT
function triggerGPXUpload() {
  const fileInput = document.createElement("input");
  fileInput.type = "file";
  fileInput.accept = ".gpx";
  
  fileInput.addEventListener("change", (e) => {
    const file = e.target.files[0];
    if (!file) return;

    logMessage(`Parsing GPX tracker file: ${file.name}...`, "info");
    
    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const text = event.target.result;
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(text, "text/xml");
        
        const trackpoints = xmlDoc.getElementsByTagName("trkpt");
        if (trackpoints.length === 0) {
          showToast("GPX Parse Error", "No trackpoints (<trkpt>) found inside GPX file.", "error");
          logMessage("GPX file lacks trackpoints", "error");
          return;
        }

        clearRoute();
        
        // Parse track points
        for (let i = 0; i < trackpoints.length; i++) {
          const lat = parseFloat(trackpoints[i].getAttribute("lat"));
          const lon = parseFloat(trackpoints[i].getAttribute("lon"));
          addRouteWaypoint(lat, lon);
        }

        // Center map to first coordinate point
        const firstPt = state.waypoints[0];
        state.map.setView(firstPt, 14);
        state.marker.setLatLng(firstPt);
        setMapCoordinates(firstPt[0], firstPt[1]);

        showToast("GPX Imported", `Loaded ${state.waypoints.length} route coordinates trackpoints.`, "success");
        logMessage(`Loaded GPX route track with ${state.waypoints.length} points.`, "success");
      } catch (err) {
        logMessage(`GPX parsing crash: ${err}`, "error");
        showToast("GPX Error", "Failed to parse XML GPX schema.", "error");
      }
    };

    reader.readAsText(file);
  });
  
  fileInput.click();
}
